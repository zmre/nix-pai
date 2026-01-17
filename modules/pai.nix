{inputs, ...}: let
  localsrc = ../.;
in {
  imports = [./options.nix];
  # Define system-dependent outputs based on the option
  config = {
    perSystem = {
      lib,
      config,
      pkgs,
      ...
    }: let
      perSystemConfig = config;

      # Generate settings.json content from merged settings
      settingsJsonContent = builtins.toJSON (lib.filterAttrsRecursive (name: value: value != null) perSystemConfig.pai.claudeSettings);

      # Generate mcp.json content from mcpServers option
      # Filter out null values from each server config to keep JSON clean
      cleanMcpServer = server:
        lib.filterAttrs (name: value: value != null && value != {}) server;
      mcpJsonContent = builtins.toJSON {
        mcpServers = lib.mapAttrs (name: server: cleanMcpServer server) perSystemConfig.pai.mcpServers;
      };

      # Generate opencode config.json content from opencodeSettings option
      # Recursively filter out null values and empty attrs to keep JSON clean
      cleanAttrs = attrs:
        lib.filterAttrs (name: value: value != null && value != {}) (
          lib.mapAttrs (
            name: value:
              if builtins.isAttrs value
              then cleanAttrs value
              else value
          )
          attrs
        );
      cleanModel = model: cleanAttrs model;
      cleanProvider = provider:
        cleanAttrs (provider
          // {
            models = lib.mapAttrs (name: model: cleanModel model) (provider.models or {});
          });
      opencodeJsonContent = builtins.toJSON (
        {
          "$schema" = "https://opencode.ai/config.json";
          autoupdate = false;
        }
        // cleanAttrs (perSystemConfig.pai.opencodeSettings
          // {
            provider = lib.mapAttrs (name: provider: cleanProvider provider) (perSystemConfig.pai.opencodeSettings.provider or {});
          })
      );

      # Create JSON config files as derivations
      settingsJsonFile = pkgs.writeText "settings.json" settingsJsonContent;
      mcpJsonFile = pkgs.writeText "mcp.json" mcpJsonContent;
      opencodeJsonFile = pkgs.writeText "opencode-config.json" opencodeJsonContent;

      # Import fabric module with necessary dependencies
      fabricWrapped = import ./fabric.nix {
        inherit pkgs lib secretLookup perSystemConfig;
      };

      # Fabric patterns derivation (only built if patterns are included)
      fabricPatterns =
        if perSystemConfig.pai.fabric.includePatterns
        then
          import ./fabric-patterns.nix {
            inherit pkgs lib;
            patternsSource =
              if perSystemConfig.pai.fabric.patternsSource != null
              then perSystemConfig.pai.fabric.patternsSource
              else "${inputs.fabric}/data/patterns";
          }
        else null;

      corePackages = with pkgs;
        [
          bun
          jq
          curl # Required for wrapper script health checks
          nodejs # Required for hooks - Node.js runs nix store files instantly while bun has ~5s delay
          inputs.nix-ai-tools.packages.${pkgs.stdenv.hostPlatform.system}.claude-code
          inputs.nix-ai-tools.packages.${pkgs.stdenv.hostPlatform.system}.ccstatusline
          #nix-ai-tools.package.${pkgs.stdenv.hostPlatform.system}.openskills
        ]
        ++ lib.optionals perSystemConfig.pai.automaticPrivacy [
          inputs.nix-ai-tools.packages.${pkgs.stdenv.hostPlatform.system}.claude-code-router
        ]
        ++ lib.optionals perSystemConfig.pai.otherTools.enableCodex [
          inputs.nix-ai-tools.packages.${pkgs.stdenv.hostPlatform.system}.codex
        ]
        ++ lib.optionals perSystemConfig.pai.fabric.enable [fabricWrapped.package]
        ++ lib.optionals perSystemConfig.pai.otherTools.enableGemini [
          inputs.nix-ai-tools.packages.${pkgs.stdenv.hostPlatform.system}.gemini-cli
        ]
        ++ lib.optionals perSystemConfig.pai.otherTools.enableOpencode [
          inputs.nix-ai-tools.packages.${pkgs.stdenv.hostPlatform.system}.opencode
          #ollama
        ]
        ++ lib.optionals stdenv.isLinux [libsecret] # libsecret provides secret-tool on linux
        ++ perSystemConfig.pai.extraPackages;

      binariesToWrap =
        ["claude"]
        ++ lib.optionals perSystemConfig.pai.otherTools.enableGemini ["gemini"]
        ++ lib.optionals perSystemConfig.pai.otherTools.enableCodex ["codex"];

      # list of secrets to populate into the environment
      secrets = binary:
        {
          #MCP_API_KEY = "mcpkey";
          OPENAI_API_KEY = "openaikey";
          GOOGLE_API_KEY = "geminikey";
          REF_TOOLS_KEY = "reftoolskey";
          #OLLAMA_KEY = "ollamakey";
        }
        # // lib.optionalAttrs (binary != "claude") {
        #   ANTHROPIC_API_KEY = "anthropickey";
        # }
        // perSystemConfig.pai.extraSecrets;

      # function returning the command for fetching secrets
      # Security: secret names are quoted to prevent shell injection
      secretLookup = secretname:
        if pkgs.stdenv.isLinux
        then ''$(secret-tool lookup api '${secretname}' 2>/dev/null | tr -d \"\n\")''
        else ''$(security find-generic-password -l '${secretname}' -g -w 2>/dev/null | tr -d \"\n\")'';

      # needs to be rw, so this fails: --set CODEX_HOME $out/codex \
      mkWrapSecret = binary: ''
        [ -e $out/bin/${binary} ] && makeWrapper $out/bin/${binary} $out/bin/${perSystemConfig.pai.commandName}-${binary} \
        ${lib.concatStringsSep " " (lib.mapAttrsToList (
          key: value: ''--run 'export ${key}="${secretLookup value}"' ''
        ) (secrets binary))} \
          --prefix PATH : "$out/bin" \
          --set CODEX_OSS_BASE_URL "${perSystemConfig.pai.ollamaServer}/v1" \
          --set GEMINI_CLI_SYSTEM_DEFAULTS_PATH $out/gemini/settings-defaults.json \
          --set CODEX_MANAGED_CONFIG_PATH $out/codex/managed_config.toml \
          --set-default OLLAMA_HOST "${perSystemConfig.pai.ollamaServer}" \
          --set-default OLLAMA_API_URL "${perSystemConfig.pai.ollamaServer}"
      '';

      envPathBase = pkgs.lib.makeBinPath (with pkgs; [
        gawk
        coreutils
        jq
        bun
        curl
      ]);

      pai = pkgs.stdenvNoCC.mkDerivation {
        # runCommand perSystemConfig.pai.commandName {
        name = perSystemConfig.pai.commandName;
        pname = perSystemConfig.pai.commandName;
        src = localsrc;
        # preferLocalBuild = true;
        # allowSubstitutes = false;
        buildInputs = corePackages;
        nativeBuildInputs = [
          #pkgs.makeBinaryWrapper
          pkgs.makeWrapper
          pkgs.gawk
          pkgs.rsync
          pkgs.parallel
        ];
        meta.mainProgram = perSystemConfig.pai.commandName;
        postFixup = ''
          ###########################################
          # SECTION 8: Wrap binaries with secrets
          ###########################################
          ${lib.concatStringsSep "\n" (lib.map mkWrapSecret binariesToWrap)}

          ###########################################
          # SECTION 9: Copy user's extra files
          ###########################################
          # Copy in the user's settings files overwriting if needed
          ${lib.strings.concatMapStrings (x: "cp -R ${x}${
              if builtins.readFileType x == "directory"
              then "/*"
              else ""
            }  $out/claude/skills/\n")
            perSystemConfig.pai.extraSkills}
          ${lib.strings.concatMapStrings (x: "cp -R ${x}${
              if builtins.readFileType x == "directory"
              then "/*"
              else ""
            } $out/claude/hooks/\n")
            perSystemConfig.pai.extraHooks}
          ${lib.strings.concatMapStrings (x: "cp -R ${x}${
              if builtins.readFileType x == "directory"
              then "/*"
              else ""
            } $out/claude/agents/\n")
            perSystemConfig.pai.extraAgents}
        '';

        installPhase = ''
          ###########################################
          # SECTION 1: Link all core packages to $out/bin
          ###########################################
          mkdir -p $out/bin
          ${lib.strings.concatMapStrings (x: "ln -s ${x}/bin/* $out/bin/\n") corePackages}

          ###########################################
          # SECTION 2: Generate claude-code-router config (if enabled)
          ###########################################
          ${lib.optionalString perSystemConfig.pai.automaticPrivacy ''
            # CCR expects config at ~/.claude-code-router/config.json
            # We set HOME=$out at runtime, so put config at $out/.claude-code-router/
            # Also create plugins and logs dirs that CCR tries to create at startup
            mkdir -p $out/.claude-code-router/plugins
            mkdir -p $out/.claude-code-router/logs
            touch $out/.claude.json  # CCR expects this file to exist
            cp "${localsrc}/modules/ccr-config.json" $out/.claude-code-router/config.json
            cp "${localsrc}/modules/strip-thinking.js" $out/.claude-code-router/plugins/strip-thinking.js
          ''}

          ###########################################
          # SECTION 3: Create main command wrapper script
          ###########################################
          cp "${localsrc}/modules/claude-wrapper.sh" $out/bin/${perSystemConfig.pai.commandName}
          chmod +x $out/bin/${perSystemConfig.pai.commandName}

          ###########################################
          # SECTION 4: Create opencode wrapper (if enabled)
          ###########################################
          ${lib.optionalString (perSystemConfig.pai.otherTools.enableOpencode) ''
            makeWrapper "$out/bin/opencode" "$out/bin/${perSystemConfig.pai.commandName}-priv" \
                ${lib.concatStringsSep " " (lib.mapAttrsToList (
                key: value: ''--run 'export ${key}="${secretLookup value}"' ''
              )
              (secrets "opencode"))} \
                --set PAI_DIR "$out" \
                --set DA "${perSystemConfig.pai.assistantName}" \
                --set DA_COLOR "${perSystemConfig.pai.assistantColor}" \
                --set ENGINEER_NAME "${perSystemConfig.pai.userFullName}" \
                --set OPENCODE_CONFIG $out/opencode/config.json \
                --set OPENCODE_CONFIG_DIR $out/opencode \
                --prefix PATH : "$out/bin"
          ''}

          ###########################################
          # SECTION 5: Copy config files and directories
          ###########################################
          # Copy in all the settings files, excluding fabric patterns (handled separately)
          # and settings.json/mcp.json (generated from Nix options)
          # Use --chmod=u+w to ensure all files are writable (nix store sources are read-only)
          mkdir -p $out/claude
          rsync -a --chmod=u+w --exclude='skills/fabric/tools/patterns' --exclude='settings.json' --exclude='mcp.json' "${localsrc}/claude/" "$out/claude/"

          # Copy generated JSON config files from writeText derivations
          # Files need chmod u+w since nix store sources are read-only
          cp ${settingsJsonFile} $out/claude/settings.json
          chmod u+w $out/claude/settings.json
          cp ${mcpJsonFile} $out/claude/mcp.json
          chmod u+w $out/claude/mcp.json

          # Fabric patterns: copy from pre-built derivation if enabled
          ${lib.optionalString perSystemConfig.pai.fabric.includePatterns ''
            mkdir -p $out/claude/skills/fabric/tools
            cp -R ${fabricPatterns}/patterns $out/claude/skills/fabric/tools/
            cp ${fabricPatterns}/patterns-list.txt $out/claude/skills/fabric/.patterns-list.txt
          ''}

          # If patterns not included, create placeholder patterns list
          ${lib.optionalString (!perSystemConfig.pai.fabric.includePatterns) ''
            mkdir -p $out/claude/skills/fabric
            echo "Patterns not bundled. Use \`fabric -l\` to list available patterns, or \`fabric -p pattern_name\` to execute." > $out/claude/skills/fabric/.patterns-list.txt
          ''}

          mkdir -p "$out/codex"
          cp  "${localsrc}/codex/managed_config.toml" "$out/codex"
          mkdir -p "$out/gemini"
          cp "${localsrc}/gemini/settings-defaults.json" "$out/gemini/"
          cp "${localsrc}/claude/skills/CORE/SKILL.md" "$out/gemini/GEMINI.md"
          chmod u+w "$out/gemini/GEMINI.md"
          cp -r "${localsrc}/.config" "$out/"

          # Create opencode directory structure and copy config from writeText derivation
          mkdir -p $out/opencode
          cp ${opencodeJsonFile} $out/opencode/config.json
          chmod u+w $out/opencode/config.json

          # Link agents and skills from claude to opencode
          ln -s $out/claude/agents $out/opencode/agent
          ln -s $out/claude/skills $out/opencode/skills
          ln -s $out/claude/skills $out/codex/skills

          # Generate markdown describing all skills for gemini
          echo -e "\n\n## Skills\n\nYou have access to a number of skills files, which contain prompts and instructions to help you in achieving your and in using tools. Please read each skill description below carefully and read the associated file when it is relevant to your task.\n\n" >> $out/gemini/GEMINI.md

          SKILLS_DIR="$out/claude/skills"
          find "$out/claude/skills" -name "SKILL.md" -type f | sort | while read -r skill_file; do
            # Get relative path from skills directory
            rel_path="''${skill_file#$SKILLS_DIR/}"

            # Extract name and description from YAML frontmatter using awk
            eval "$(awk '
                BEGIN {
                    in_frontmatter = 0
                    name = ""
                    description = ""
                    reading_desc = 0
                }
                /^---$/ {
                    in_frontmatter++
                    next
                }
                in_frontmatter == 1 {
                    if ($1 == "name:") {
                        name = substr($0, 6)
                        gsub(/^[ \t]+|[ \t]+$/, "", name)  # trim whitespace
                        reading_desc = 0
                    } else if ($1 == "description:") {
                        description = substr($0, 13)
                        gsub(/^[ \t]+|[ \t]+$/, "", description)  # trim whitespace
                        reading_desc = 1
                    } else if (reading_desc && NF > 0 && $1 !~ /^[a-z]+:$/) {
                        # Continue reading multi-line description
                        description = description " " $0
                        gsub(/^[ \t]+|[ \t]+$/, "", description)
                    } else {
                        reading_desc = 0
                    }
                }
                in_frontmatter == 2 {
                    exit
                }
                END {
                    # Escape quotes for shell eval
                    gsub(/"/, "\\\"", name)
                    gsub(/"/, "\\\"", description)
                    print "skill_name=\"" name "\""
                    print "skill_desc=\"" description "\""
                }
            ' "$skill_file")"

            # Output in markdown format
            if [[ -n "$skill_name" && "$skill_name" != "PAI" ]]; then
                echo "* [$skill_name]($out/claude/skills/$rel_path) - $skill_desc" >> $out/gemini/GEMINI.md
            fi
          done

          # Generate skills-list.json from all SKILL.md files
          echo "{" > $out/opencode/skills-list.json
          first=true
          while IFS= read -r skill_file; do
              # Get relative path from skills directory
              rel_path="''${skill_file#$out/claude/skills/}"
              # Get immediate parent directory name
              parent_dir=$(basename $(dirname "$skill_file"))

              # Add comma separator for all but first entry
              if [ "$first" = true ]; then
                first=false
              else
                echo "," >> $out/opencode/skills-list.json
              fi

              # Add entry to JSON
              echo -n "  \"$parent_dir\": \"$rel_path\"" >> $out/opencode/skills-list.json
          done < <(find $out/claude/skills -name "SKILL.md" -type f | sort)
          echo "" >> $out/opencode/skills-list.json
          echo "}" >> $out/opencode/skills-list.json

          ###########################################
          # SECTION 6: Perform template substitutions
          ###########################################
          # Main command wrapper substitutions
          substituteInPlace $out/bin/${perSystemConfig.pai.commandName} \
              --replace-quiet @paiBasePath@ "$out" \
              --replace-quiet @assistantName@ '${perSystemConfig.pai.assistantName}' \
              --replace-quiet @assistantColor@ '${perSystemConfig.pai.assistantColor}' \
              --replace-quiet @userFullName@ '${perSystemConfig.pai.userFullName}' \
              --replace-quiet @automaticPrivacy@ '${lib.boolToString perSystemConfig.pai.automaticPrivacy}' \
              --replace-quiet @paiEnvPath@ '${envPathBase}' \
              --replace-quiet @privateModel@ '${perSystemConfig.pai.privateModel}'

          # Router config substitutions (if enabled)
          ${lib.optionalString perSystemConfig.pai.automaticPrivacy ''

            substituteInPlace $out/.claude-code-router/config.json \
                --replace-quiet @ollamaHost@ '${perSystemConfig.pai.ollamaServer}' \
                --replace-quiet @paiBasePath@ "$out" \
                --replace-quiet @privateModel@ '${perSystemConfig.pai.privateModel}'
          ''}

          # Settings and MCP config substitutions
          substituteInPlace $out/claude/settings.json \
              --replace-quiet @paiBasePath@ "$out" \
              --replace-quiet @assistantName@ '${perSystemConfig.pai.assistantName}'

          substituteInPlace $out/claude/mcp.json \
              --replace-quiet @paiBasePath@ "$out" \
              --replace-quiet @assistantName@ '${perSystemConfig.pai.assistantName}'

          substituteInPlace $out/gemini/settings-defaults.json \
              --replace-quiet @ollamaHost@ '${perSystemConfig.pai.ollamaServer}' \
              --replace-quiet @paiBasePath@ "$out"
          substituteInPlace $out/codex/managed_config.toml \
              --replace-quiet @ollamaHost@ '${perSystemConfig.pai.ollamaServer}' \
              --replace-quiet @assistantName@ '${perSystemConfig.pai.assistantName}' \
              --replace-quiet @paiEnvPath@ '${envPathBase}' \
              --replace-quiet @paiBasePath@ "$out"

          # Compute statusline counts at build time (nix store is read-only)
          skills_count=$(find $out/claude/skills -name SKILL.md 2>/dev/null | wc -l | tr -d ' ')
          mcps_count=$(${pkgs.jq}/bin/jq -r '.mcpServers | length' $out/claude/mcp.json 2>/dev/null || echo "0")
          mcp_names_raw=$(${pkgs.jq}/bin/jq -r '.mcpServers | keys | join(" ")' $out/claude/mcp.json 2>/dev/null || echo "")
          fabric_patterns_dir="$out/claude/skills/fabric/tools/patterns"
          if [ -d "$fabric_patterns_dir" ]; then
              fabric_count=$(find "$fabric_patterns_dir" -maxdepth 1 -type d -not -path "$fabric_patterns_dir" 2>/dev/null | wc -l | tr -d ' ')
          else
              fabric_count="0"
          fi
          substituteInPlace $out/claude/statusline-command.sh \
              --replace-quiet @paiBasePath@ "$out" \
              --replace-quiet @skills_count@ "$skills_count" \
              --replace-quiet @mcps_count@ "$mcps_count" \
              --replace-quiet @fabric_count@ "$fabric_count" \
              --replace-quiet @mcp_names_raw@ "$mcp_names_raw"

          substituteInPlace $out/.config/ccstatusline/settings.json \
              --replace-quiet @paiBasePath@ "$out" \
              --replace-quiet @assistantName@ '${perSystemConfig.pai.assistantName}' \
              --replace-quiet @assistantColor@ '${perSystemConfig.pai.assistantColor}' \
              --replace-quiet @userFullName@ '${perSystemConfig.pai.userFullName}' \
              --replace-quiet @automaticPrivacy@ '${lib.boolToString perSystemConfig.pai.automaticPrivacy}' \
              --replace-quiet @skills_count@ "$skills_count" \
              --replace-quiet @mcps_count@ "$mcps_count" \
              --replace-quiet @fabric_count@ "$fabric_count" \
              --replace-quiet @mcp_names_raw@ "$mcp_names_raw" \
              --replace-quiet @privateModel@ '${perSystemConfig.pai.privateModel}'

          substituteInPlace $out/opencode/config.json \
              --replace-quiet @ollamaHost@ '${perSystemConfig.pai.ollamaServer}' \
              --replace-quiet @paiBasePath@ "$out"

          # Hook-specific substitutions
          substituteInPlace $out/claude/hooks/load-core-context.ts \
              --replace-quiet @assistantName@ '${perSystemConfig.pai.assistantName}' \
              --replace-quiet @paiBasePath@ "$out"
          substituteInPlace $out/claude/hooks/capture-all-events.ts \
              --replace-quiet @assistantName@ '${perSystemConfig.pai.assistantName}' \
              --replace-quiet @paiBasePath@ "$out"
          substituteInPlace $out/claude/hooks/stop-hook.ts \
              --replace-quiet @assistantName@ '${perSystemConfig.pai.assistantName}' \
              --replace-quiet @paiBasePath@ "$out"
          substituteInPlace $out/claude/hooks/context-compression-hook.ts \
              --replace-quiet @assistantName@ '${perSystemConfig.pai.assistantName}' \
              --replace-quiet @paiBasePath@ "$out"

          # CORE skill and GEMINI.md have additional user-specific variables
          substituteInPlace $out/gemini/GEMINI.md \
              --replace-quiet @assistantName@ '${perSystemConfig.pai.assistantName}' \
              --replace-quiet @keyContacts@ '${perSystemConfig.pai.keyContacts}' \
              --replace-quiet @socialMedia@ '${perSystemConfig.pai.socialMedia}' \
              --replace-quiet @userFullName@ '${perSystemConfig.pai.userFullName}' \
              --replace-quiet @keyBio@ "${perSystemConfig.pai.keyBio}" \
              --replace-quiet @additionalCoreInstructions@ "${perSystemConfig.pai.additionalCoreInstructions}" \
              --replace-quiet @paiBasePath@ "$out"
          substituteInPlace $out/claude/skills/CORE/SKILL.md \
              --replace-quiet @assistantName@ '${perSystemConfig.pai.assistantName}' \
              --replace-quiet @keyContacts@ '${perSystemConfig.pai.keyContacts}' \
              --replace-quiet @socialMedia@ '${perSystemConfig.pai.socialMedia}' \
              --replace-quiet @userFullName@ '${perSystemConfig.pai.userFullName}' \
              --replace-quiet @keyBio@ "${perSystemConfig.pai.keyBio}" \
              --replace-quiet @additionalCoreInstructions@ "${perSystemConfig.pai.additionalCoreInstructions}" \
              --replace-quiet @paiBasePath@ "$out"

          # Fabric patterns list substitution (generated earlier in build)
          if [ -f "$out/claude/skills/fabric/.patterns-list.txt" ]; then
              PATTERNS_CONTENT=$(cat "$out/claude/skills/fabric/.patterns-list.txt")
              # Use awk for multi-line substitution since substituteInPlace doesn't handle it well
              awk -v patterns="$PATTERNS_CONTENT" '{gsub(/@fabricPatternsList@/, patterns); print}' \
                  "$out/claude/skills/fabric/SKILL.md" > "$out/claude/skills/fabric/SKILL.md.tmp"
              mv "$out/claude/skills/fabric/SKILL.md.tmp" "$out/claude/skills/fabric/SKILL.md"
              rm -f "$out/claude/skills/fabric/.patterns-list.txt"
          fi

          # Generic substitution for all *.md files in skills (except CORE which is handled above)
          # This allows parent modules to add skills with @assistantName@ and @paiBasePath@ placeholders
          find $out/claude/skills -name "*.md" -type f ! -path "*/CORE/*" | while read -r mdfile; do
              substituteInPlace "$mdfile" \
                  --replace-quiet @assistantName@ '${perSystemConfig.pai.assistantName}' \
                  --replace-quiet @paiBasePath@ "$out"
          done

          # Generic substitution for all *.md files in agents
          find $out/claude/agents -name "*.md" -type f | while read -r mdfile; do
              substituteInPlace "$mdfile" \
                  --replace-quiet @assistantName@ '${perSystemConfig.pai.assistantName}' \
                  --replace-quiet @paiBasePath@ "$out"
          done

          ###########################################
          # SECTION 7: Pre-compile TypeScript hooks
          ###########################################
          # IMPORTANT: We use Node.js (not Bun) to run hooks because:
          # - Bun has a ~5-10 second performance penalty when running files from /nix/store paths
          # - Node.js runs the same files from /nix/store in ~9ms
          # - This is a known issue with Bun on macOS + Nix store paths
          # We still use Bun for compilation since it's fast for that purpose
          echo "Pre-compiling TypeScript hooks to JavaScript for Node.js (parallel)..."
          export out
          find $out/claude/hooks -maxdepth 1 -name "*.ts" | \
            ${pkgs.parallel}/bin/parallel --will-cite '
              hookname=$(basename {} .ts)
              ${pkgs.bun}/bin/bun build {} --outfile '"$out"'/claude/hooks/$hookname.js --target node --minify 2>/dev/null
              rm {}
              ${pkgs.gnused}/bin/sed -i "1s|^#!.*|#!${pkgs.nodejs}/bin/node|" '"$out"'/claude/hooks/$hookname.js
              echo "  ✓ $hookname"
            '
          echo "Hook pre-compilation complete (using Node.js runtime)."

        '';
      };
    in {
      packages.pai = pai;

      # Set base hook configurations via lib.mkBefore (enables lib.mkAfter merging)
      # Users can use lib.mkAfter to append their hooks after these base hooks
      pai.claudeSettings.hooks = {
        UserPromptSubmit = lib.mkBefore [
          {
            hooks = [
              {
                type = "command";
                command = "@paiBasePath@/claude/hooks/update-tab-titles.js";
              }
            ];
          }
        ];
        SessionStart = lib.mkBefore [
          {
            hooks = [
              {
                type = "command";
                command = "@paiBasePath@/claude/hooks/load-core-context.js";
              }
              {
                type = "command";
                command = "@paiBasePath@/claude/hooks/initialize-pai-session.js";
              }
            ];
          }
        ];
        Stop = lib.mkBefore [
          {
            hooks = [
              {
                type = "command";
                command = "@paiBasePath@/claude/hooks/stop-hook.js";
              }
              {
                type = "command";
                command = "@paiBasePath@/claude/hooks/capture-all-events.js --event-type Stop";
              }
            ];
          }
        ];
        PermissionRequest = lib.mkBefore [
          {
            hooks = [
              {
                type = "command";
                command = "@paiBasePath@/claude/hooks/permission-prompt-hook.js";
              }
            ];
          }
        ];
      };
    };
  };
}
