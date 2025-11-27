{
  lib,
  flake-parts-lib,
  ...
}: {
  options = {
    perSystem = flake-parts-lib.mkPerSystemOption ({config, ...}: {
      options.pai = {
        extraPackages = lib.mkOption {
          type = lib.types.listOf lib.types.package;
          default = [];
          description = "Other packages to add to the environment for your assistant and the shell/install.";
        };
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
          enableOpencode = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "OpenCode included and given an environment";
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
          permissionsAsk = lib.mkOption {
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
    });
  };
}
