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

      ccusage = pkgs.writeShellScriptBin "ccusage" ''
        export PATH=${pkgs.lib.makeBinPath corePackages}:$PATH

        ${pkgs.bun}/bin/bunx ccusage@latest
      '';

      corePackages = with pkgs;
        [
          bun
          jq
          inputs.nix-ai-tools.packages.${pkgs.stdenv.hostPlatform.system}.claude-code
          #nix-ai-tools.package.${pkgs.stdenv.hostPlatform.system}.openskills
        ]
        ++ lib.optionals (perSystemConfig.pai.otherTools.enableCodex) [
          inputs.nix-ai-tools.packages.${pkgs.stdenv.hostPlatform.system}.codex
        ]
        ++ lib.optionals (perSystemConfig.pai.otherTools.enableFabric) [fabric-ai]
        ++ lib.optionals (perSystemConfig.pai.otherTools.enableGemini) [
          inputs.nix-ai-tools.packages.${pkgs.stdenv.hostPlatform.system}.gemini-cli
        ]
        ++ lib.optionals (perSystemConfig.pai.otherTools.enableOpencode) [
          inputs.nix-ai-tools.packages.${pkgs.stdenv.hostPlatform.system}.opencode
          #ollama
        ]
        ++ perSystemConfig.pai.extraPackages;

      mergedPackages = corePackages ++ [ccusage];

      binariesToWrap = ["fabric" "gemini" "codex" "claude"];

      # list of secrets to populate into the environment
      secrets = binary:
        {
          #MCP_API_KEY = "mcpkey";
          OPENAI_API_KEY = "openaikey";
          GOOGLE_API_KEY = "geminikey";
          REF_TOOLS_KEY = "reftoolskey";
          OLLAMA_KEY = "ollamakey";
        }
        // lib.optionalAttrs (binary != "claude") {
          ANTHROPIC_API_KEY = "anthropickey";
        }
        // perSystemConfig.pai.extraSecrets;

      # function returning the command for fetching secrets
      secretLookup = secretname:
        if pkgs.stdenv.isLinux
        then ''$(secret-tool lookup api ${secretname} 2>/dev/null | tr -d \"\n\")''
        else ''$(security find-generic-password -l ${secretname} -g -w 2>/dev/null |tr -d \"\n\")'';

      mkWrapSecret = binary: ''
        [ -e $out/bin/${binary} ] && wrapProgram $out/bin/${binary} \
        ${lib.concatStringsSep " " (lib.mapAttrsToList (
            key: value: ''--run 'export ${key}="${secretLookup value}"' ''
          )
          (secrets binary))} \
          --prefix PATH : "$out/bin" \
          --set CODEX_OSS_BASE_URL "${perSystemConfig.pai.ollamaServer}/v1" \
          --set OLLAMA_HOST "${perSystemConfig.pai.ollamaServer}" \
          --set OLLAMA_API_URL "${perSystemConfig.pai.ollamaServer}"
      '';

      pai = pkgs.stdenvNoCC.mkDerivation {
        # runCommand perSystemConfig.pai.commandName {
        name = perSystemConfig.pai.commandName;
        pname = perSystemConfig.pai.commandName;
        src = localsrc;
        # preferLocalBuild = true;
        # allowSubstitutes = false;
        buildInputs = mergedPackages;
        nativeBuildInputs = [
          #pkgs.makeBinaryWrapper
          pkgs.makeWrapper
        ];
        meta.mainProgram = perSystemConfig.pai.commandName;
        buildPhase = ''
        '';
        postFixup = ''
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
          # Next simulate symlinkJoin function by linking inputs
          mkdir -p $out/bin
          ${lib.strings.concatMapStrings (x: "ln -s ${x}/bin/* $out/bin/\n") mergedPackages}

          ${lib.concatStringsSep "\n" (
            lib.map mkWrapSecret binariesToWrap
          )}

          # Next put the ai assistant into bin with the proper added environment
          makeWrapper "$out/bin/claude" "$out/bin/${perSystemConfig.pai.commandName}" \
              --set PAI_DIR "$out" \
              --set DA "${perSystemConfig.pai.assistantName}" \
              --set DA_COLOR "${perSystemConfig.pai.assistantColor}" \
              --set ENGINEER_NAME "${perSystemConfig.pai.userFullName}" \
              --prefix PATH : "$out/bin" \
              --add-flags "--settings $out/claude/settings.json --mcp-config $out/claude/mcp.json --plugin-dir $out/claude"

          # Next put the private ollama ai assistant into bin with the proper added environment
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

          # Copy in all the settings files
          cp -R ${localsrc}/claude "$out/"

          # Create opencode directory structure and copy config
          mkdir -p $out/opencode
          cp ${localsrc}/opencode/config.json $out/opencode/

          # Link agents and skills from claude to opencode
          ln -s $out/claude/agents $out/opencode/agent
          ln -s $out/claude/skills $out/opencode/skills

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

          # Do substitutions

          substituteInPlace $out/claude/settings.json \
              --replace-quiet @paiBasePath@ "$out" \
              --replace-quiet @defaultMode@ '${perSystemConfig.pai.extraClaudeSettings.defaultMode}' \
              --replace-quiet @outputStyle@ '${perSystemConfig.pai.extraClaudeSettings.outputStyle}' \
              --replace-quiet @companyAnnouncements@ "${perSystemConfig.pai.extraClaudeSettings.companyAnnouncements}" \
              --replace-quiet @assistantName@ '${perSystemConfig.pai.assistantName}' \
              --replace-quiet @permissionsAllow@ '${lib.strings.concatMapStrings (x: ''"${x}", '') perSystemConfig.pai.extraClaudeSettings.permissionsAllow}' \
              --replace-quiet @permissionsAsk@ '${lib.strings.concatMapStrings (x: ''"${x}", '') perSystemConfig.pai.extraClaudeSettings.permissionsAsk}' \
              --replace-quiet @permissionsDeny@ '${lib.strings.concatMapStrings (x: ''"${x}", '') perSystemConfig.pai.extraClaudeSettings.permissionsAllow}'

          substituteInPlace $out/claude/agents/architect.md \
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
          substituteInPlace $out/claude/agents/claude-researcher.md \
              --replace-quiet @assistantName@ '${perSystemConfig.pai.assistantName}' \
              --replace-quiet @paiBasePath@ "$out"
          substituteInPlace $out/claude/agents/engineer.md \
              --replace-quiet @assistantName@ '${perSystemConfig.pai.assistantName}' \
              --replace-quiet @paiBasePath@ "$out"
          substituteInPlace $out/claude/agents/gemini-researcher.md \
              --replace-quiet @assistantName@ '${perSystemConfig.pai.assistantName}' \
              --replace-quiet @paiBasePath@ "$out"
          substituteInPlace $out/claude/agents/pentester.md \
              --replace-quiet @assistantName@ '${perSystemConfig.pai.assistantName}' \
              --replace-quiet @paiBasePath@ "$out"
          substituteInPlace $out/claude/agents/designer.md \
              --replace-quiet @assistantName@ '${perSystemConfig.pai.assistantName}' \
              --replace-quiet @paiBasePath@ "$out"
          substituteInPlace $out/claude/agents/researcher.md \
              --replace-quiet @assistantName@ '${perSystemConfig.pai.assistantName}' \
              --replace-quiet @paiBasePath@ "$out"
          substituteInPlace $out/claude/skills/CORE/SKILL.md \
              --replace-quiet @assistantName@ '${perSystemConfig.pai.assistantName}' \
              --replace-quiet @keyContacts@ '${perSystemConfig.pai.keyContacts}' \
              --replace-quiet @devStackPrefs@ '${perSystemConfig.pai.devStackPrefs}' \
              --replace-quiet @socialMedia@ '${perSystemConfig.pai.socialMedia}' \
              --replace-quiet @userFullName@ '${perSystemConfig.pai.userFullName}' \
              --replace-quiet @keyBio@ "${perSystemConfig.pai.keyBio}" \
              --replace-quiet @paiBasePath@ "$out"
          substituteInPlace $out/claude/skills/alex-hormozi-pitch/workflows/create-pitch.md \
              --replace-quiet @assistantName@ '${perSystemConfig.pai.assistantName}' \
              --replace-quiet @paiBasePath@ "$out"
          substituteInPlace $out/claude/skills/create-skill/SKILL.md \
              --replace-quiet @assistantName@ '${perSystemConfig.pai.assistantName}'
          substituteInPlace $out/claude/skills/agent-observability/SKILL.md \
              --replace-quiet @assistantName@ '${perSystemConfig.pai.assistantName}' \
              --replace-quiet @paiBasePath@ "$out"
          substituteInPlace $out/claude/skills/agent-observability/workflows/start.md \
              --replace-quiet @assistantName@ '${perSystemConfig.pai.assistantName}' \
              --replace-quiet @paiBasePath@ "$out"
          substituteInPlace $out/claude/skills/research/workflows/conduct.md \
              --replace-quiet @assistantName@ '${perSystemConfig.pai.assistantName}'
          substituteInPlace $out/opencode/config.json \
              --replace-quiet @ollamaHost@ '${perSystemConfig.pai.ollamaServer}' \
              --replace-quiet @paiBasePath@ "$out"

        '';
      };
    in {
      packages.pai = pai;
      #config.paipackages.pai = pai;
    };
  };
}
