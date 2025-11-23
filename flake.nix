{
  description = "Template Module for Personal AI Assistant (PAI) - An advanced AI-powered development environment using Claude Code";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
  };

  outputs = inputs @ {
    self,
    flake-parts,
    nixpkgs,
    ...
  }:
    flake-parts.lib.mkFlake {inherit inputs;} (let
      localsrc = ./.;
    in {
      systems = ["x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin"];

      flake = {
        flakeModules.default = {
          config,
          lib,
          pkgs,
          ...
        }: let
          flakeConfig = config;
        in {
          options = {
            pai = {
              ollamaServer = lib.mkOption {
                type = lib.types.str;
                default = "127.0.0.1:11434";
                description = "Host of your ollama server, if applicable";
              };
              assistantName = lib.mkOption {
                type = lib.types.str;
                default = "Iris";
                description = "Name of the personal assistant.";
              };
              commandName = lib.mkOption {
                type = lib.types.str;
                default = "iris";
                description = "Command to run to start agent.";
              };
              assistantColor = lib.mkOption {
                type = lib.types.str;
                default = "purple";
                description = "Color of the personal assistant messages.";
              };
              userFullName = lib.mkOption {
                type = lib.types.str;
                default = "Boss";
                description = "Full name of the user";
              };
              extraPackages = lib.mkOption {
                type = lib.types.listOf lib.types.package;
                default = [];
                description = "Other packages to add to the environment for your assistant and the shell/install.";
              };
              extraSecrets = lib.mkOption {
                type = lib.types.attrsOf lib.types.str;
                default = {};
                description = "Add other secrets into the environment using this format: {ENV_VAR_NAME = \"secretname\"}";
              };
              otherTools = {
                enableCodex = lib.mkOption {
                  type = lib.types.bool;
                  default = true;
                  description = "OpenAI codex included and given an environment";
                };
                enableFabric = lib.mkOption {
                  type = lib.types.bool;
                  default = true;
                  description = "Fabric prompt library";
                };
                enableGemini = lib.mkOption {
                  type = lib.types.bool;
                  default = true;
                  description = "Gemini included and given an environment";
                };
              };
              extraClaudeSettings = {
                defaultMode = lib.mkOption {
                  type = lib.types.enum ["default" "acceptEdits" "plan" "bypassPermissions"];
                  default = "default";
                  description = "https://code.claude.com/docs/en/iam#permission-modes";
                };
                permissionsAllow = lib.mkOption {
                  type = lib.types.listOf lib.types.str;
                  default = [];
                  description = "https://code.claude.com/docs/en/iam#tool-specific-permission-rules";
                };
                permissionsDeny = lib.mkOption {
                  type = lib.types.listOf lib.types.str;
                  default = [];
                  description = "https://code.claude.com/docs/en/iam#tool-specific-permission-rules";
                };
                # TODO:
                # extraEnv = lib.mkOption {
                #   type = lib.types.attrsOf lib.types.str;
                #   default = {};
                #   description = "";
                # };
                outputStyle = lib.mkOption {
                  type = lib.types.enum ["default" "explanatory" "learning"];
                  default = "default";
                  description = "https://code.claude.com/docs/en/output-styles";
                };
                companyAnnouncements = lib.mkOption {
                  type = lib.types.str;
                  default = "I'm @assistantName@; how can I help?";
                  description = "Message to see on startup";
                };
              };
              extraSkills = lib.mkOption {
                type = lib.types.listOf lib.types.path;
                default = [];
              };
              extraAgents = lib.mkOption {
                type = lib.types.listOf lib.types.path;
                default = [];
              };
              extraHooks = lib.mkOption {
                type = lib.types.listOf lib.types.path;
                default = [];
              };
              devStackPrefs = lib.mkOption {
                type = lib.types.str;
                default = ''
                  - **Rust > TypeScript > Python**: Prefer Rust first, TypeScript second for development tasks
                  - **Package Managers**:
                    - Rust: cargo
                    - JavaScript/TypeScript: bun (NOT npm, yarn, or pnpm)
                    - Python (if needed): uv (NOT pip)
                '';
              };
              keyBio = lib.mkOption {
                type = lib.types.str;
                default = ''
                  Example:

                  - Job: title at company doing work
                  - Home town: grew up in state, now living in place
                  - Core interests: security, cryptography, AI, ...
                '';
              };
              keyContacts = lib.mkOption {
                type = lib.types.str;
                default = ''
                  Example:

                  - **Name** [Role] - email@example.com
                  - **Name** [Role] - email@example.com
                '';
              };
              socialMedia = lib.mkOption {
                type = lib.types.str;
                default = ''
                  Example:

                  - **YouTube**: https://www.youtube.com/@your-channel
                  - **X/Twitter**: https://x.com/yourhandle
                  - **LinkedIn**: https://www.linkedin.com/in/yourname/
                '';
              };
            };
          };

          # Define system-dependent outputs based on the option
          config = {
            perSystem = {
              system,
              lib,
              ...
            }: let
              pkgs = import nixpkgs {
                inherit system;
                config.allowUnfree = true;
              };

              ccusage = pkgs.writeShellScriptBin "ccusage" ''
                ${pkgs.bun}/bin/bunx ccusage
              '';

              mergedPackages = with pkgs;
                [
                  bun
                  jq
                  ccusage
                  claude-code
                ]
                ++ lib.optionals (flakeConfig.pai.otherTools.enableCodex) [codex]
                ++ lib.optionals (flakeConfig.pai.otherTools.enableFabric) [fabric-ai]
                ++ lib.optionals (flakeConfig.pai.otherTools.enableGemini) [gemini-cli]
                ++ flakeConfig.pai.extraPackages;

              binariesToWrap = ["fabric" "gemini" "codex" "claude"];
              mkWrapSecret = binary: let
                # list of secrets to populate into the environment
                secrets =
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
                  // flakeConfig.pai.extraSecrets;

                # function returning the command for fetching secrets
                secretLookup = secretname:
                  if pkgs.stdenv.isLinux
                  then ''$(secret-tool lookup api ${secretname} 2>/dev/null | tr -d \"\n\")''
                  else ''$(security find-generic-password -l ${secretname} -g -w 2>/dev/null |tr -d \"\n\")'';
              in ''
                [ -e $out/bin/${binary} ] && wrapProgram $out/bin/${binary} \
                ${lib.concatStringsSep " " (lib.mapAttrsToList (
                    key: value: ''--run 'export ${key}="${secretLookup value}"' ''
                  )
                  secrets)} \
                  --prefix PATH : "$out/bin" \
                  --set OLLAMA_HOST "${flakeConfig.pai.ollamaServer}"
              '';

              pai = pkgs.stdenvNoCC.mkDerivation {
                # runCommand flakeConfig.pai.commandName {
                name = flakeConfig.pai.commandName;
                pname = flakeConfig.pai.commandName;
                src = localsrc;
                # preferLocalBuild = true;
                # allowSubstitutes = false;
                buildInputs = mergedPackages;
                nativeBuildInputs = [
                  pkgs.makeBinaryWrapper
                  pkgs.makeWrapper
                ];
                meta.mainProgram = flakeConfig.pai.commandName;
                buildPhase = ''
                '';
                postFixup = ''
                  # Copy in the user's settings files overwriting if needed
                  ${lib.strings.concatMapStrings (x: "cp -R ${x}${
                      if builtins.readFileType x == "directory"
                      then "/*"
                      else ""
                    }  $out/claude/skills/\n")
                    flakeConfig.pai.extraSkills}
                  ${lib.strings.concatMapStrings (x: "cp -R ${x}${
                      if builtins.readFileType x == "directory"
                      then "/*"
                      else ""
                    } $out/claude/hooks/\n")
                    flakeConfig.pai.extraHooks}
                  ${lib.strings.concatMapStrings (x: "cp -R ${x}${
                      if builtins.readFileType x == "directory"
                      then "/*"
                      else ""
                    } $out/claude/agents/\n")
                    flakeConfig.pai.extraAgents}
                '';

                installPhase = ''
                  # Next simulate symlinkJoin function by linking inputs
                  mkdir -p $out/bin
                  ${lib.strings.concatMapStrings (x: "ln -s ${x}/bin/* $out/bin/\n") mergedPackages}

                  ${lib.concatStringsSep "\n" (
                    lib.map mkWrapSecret binariesToWrap
                  )}

                  # Next put the ai assistant into bin with the proper added environment
                  makeBinaryWrapper "$out/bin/claude" "$out/bin/${flakeConfig.pai.commandName}" \
                      --set PAI_DIR "$out" \
                      --set DA "${flakeConfig.pai.assistantName}" \
                      --set DA_COLOR "${flakeConfig.pai.assistantColor}" \
                      --set ENGINEER_NAME "${flakeConfig.pai.userFullName}" \
                      --prefix PATH : "$out/bin" \
                      --add-flags "--settings $out/claude/settings.json --mcp-config $out/claude/mcp.json --plugin-dir $out/claude"

                  # Copy in all the settings files
                  cp -R ${localsrc}/claude "$out/"


                  # Do substitutions

                  substituteInPlace $out/claude/settings.json \
                      --replace-quiet @paiBasePath@ "$out" \
                      --replace-quiet @defaultMode@ '${flakeConfig.pai.extraClaudeSettings.defaultMode}' \
                      --replace-quiet @outputStyle@ '${flakeConfig.pai.extraClaudeSettings.outputStyle}' \
                      --replace-quiet @companyAnnouncements@ "${flakeConfig.pai.extraClaudeSettings.companyAnnouncements}" \
                      --replace-quiet @assistantName@ '${flakeConfig.pai.assistantName}' \
                      --replace-quiet @permissionsAllow@ '${lib.strings.concatMapStrings (x: ''"${x}", '') flakeConfig.pai.extraClaudeSettings.permissionsAllow}' \
                      --replace-quiet @permissionsDeny@ '${lib.strings.concatMapStrings (x: ''"${x}", '') flakeConfig.pai.extraClaudeSettings.permissionsAllow}'

                  echo 2
                  substituteInPlace $out/claude/agents/architect.md \
                      --replace-quiet @assistantName@ '${flakeConfig.pai.assistantName}' \
                      --replace-quiet @paiBasePath@ "$out"
                  substituteInPlace $out/claude/hooks/capture-all-events.ts \
                      --replace-quiet @assistantName@ '${flakeConfig.pai.assistantName}' \
                      --replace-quiet @paiBasePath@ "$out"
                  substituteInPlace $out/claude/hooks/stop-hook.ts \
                      --replace-quiet @assistantName@ '${flakeConfig.pai.assistantName}' \
                      --replace-quiet @paiBasePath@ "$out"
                  substituteInPlace $out/claude/hooks/context-compression-hook.ts \
                      --replace-quiet @assistantName@ '${flakeConfig.pai.assistantName}' \
                      --replace-quiet @paiBasePath@ "$out"
                  substituteInPlace $out/claude/agents/claude-researcher.md \
                      --replace-quiet @assistantName@ '${flakeConfig.pai.assistantName}' \
                      --replace-quiet @paiBasePath@ "$out"
                  substituteInPlace $out/claude/agents/engineer.md \
                      --replace-quiet @assistantName@ '${flakeConfig.pai.assistantName}' \
                      --replace-quiet @paiBasePath@ "$out"
                  substituteInPlace $out/claude/agents/gemini-researcher.md \
                      --replace-quiet @assistantName@ '${flakeConfig.pai.assistantName}' \
                      --replace-quiet @paiBasePath@ "$out"
                  substituteInPlace $out/claude/agents/pentester.md \
                      --replace-quiet @assistantName@ '${flakeConfig.pai.assistantName}' \
                      --replace-quiet @paiBasePath@ "$out"
                  substituteInPlace $out/claude/agents/designer.md \
                      --replace-quiet @assistantName@ '${flakeConfig.pai.assistantName}' \
                      --replace-quiet @paiBasePath@ "$out"
                  substituteInPlace $out/claude/agents/researcher.md \
                      --replace-quiet @assistantName@ '${flakeConfig.pai.assistantName}' \
                      --replace-quiet @paiBasePath@ "$out"
                  echo core
                  substituteInPlace $out/claude/skills/CORE/SKILL.md \
                      --replace-quiet @assistantName@ '${flakeConfig.pai.assistantName}' \
                      --replace-quiet @keyContacts@ '${flakeConfig.pai.keyContacts}' \
                      --replace-quiet @devStackPrefs@ '${flakeConfig.pai.devStackPrefs}' \
                      --replace-quiet @socialMedia@ '${flakeConfig.pai.socialMedia}' \
                      --replace-quiet @userFullName@ '${flakeConfig.pai.userFullName}' \
                      --replace-quiet @keyBio@ "${flakeConfig.pai.keyBio}" \
                      --replace-quiet @paiBasePath@ "$out"
                  substituteInPlace $out/claude/skills/alex-hormozi-pitch/workflows/create-pitch.md \
                      --replace-quiet @assistantName@ '${flakeConfig.pai.assistantName}' \
                      --replace-quiet @paiBasePath@ "$out"
                  substituteInPlace $out/claude/skills/create-skill/SKILL.md \
                      --replace-quiet @assistantName@ '${flakeConfig.pai.assistantName}'
                  substituteInPlace $out/claude/skills/agent-observability/SKILL.md \
                      --replace-quiet @assistantName@ '${flakeConfig.pai.assistantName}' \
                      --replace-quiet @paiBasePath@ "$out"
                  substituteInPlace $out/claude/skills/agent-observability/workflows/start.md \
                      --replace-quiet @assistantName@ '${flakeConfig.pai.assistantName}' \
                      --replace-quiet @paiBasePath@ "$out"
                  substituteInPlace $out/claude/skills/research/workflows/conduct.md \
                      --replace-quiet @assistantName@ '${flakeConfig.pai.assistantName}'

                '';
              };
            in {
              packages.pai = pai;
            };
          };

          # TODO: provide optional default config so it can be tested without
          # customizing and building another flake first
          #perSystem = { config, pkgs, ... }: {
          #packages.default = pkgs.stdenv.mkDerivation { ...};
          #};
        };
      };
    });
}
