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
          default = "Pai";
          description = "Name of the personal assistant.";
        };
        commandName = lib.mkOption {
          type = lib.types.str;
          default = "pai";
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
          description = "Add other secrets into the environment using this format: {ENV_VAR_NAME = \"secretname\"} and it will use the secrets manager to load it.";
        };
        otherTools = {
          enableCodex = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "OpenAI codex included and given an environment";
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
        fabric = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Enable fabric CLI tool";
          };
          includePatterns = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = ''
              Include fabric patterns in the build for native execution.
              When true (default), patterns are bundled from patternsSource.
              When false, uses CLI fallback (smaller build, patterns via fabric -p).
            '';
          };
          patternsSource = lib.mkOption {
            type = lib.types.nullOr lib.types.path;
            default = null;
            description = ''
              Path to fabric patterns directory. When null and includePatterns is true,
              uses patterns from the fabric flake input (github:danielmiessler/fabric/data/patterns).
              Can be overridden with a custom path pointing directly to a patterns directory.
            '';
          };
        };

        # Full Claude Code settings.json structure - generated as JSON at build time
        claudeSettings = lib.mkOption {
          type = lib.types.submodule {
            freeformType = lib.types.attrsOf lib.types.anything;
            options = {
              "$schema" = lib.mkOption {
                type = lib.types.str;
                default = "https://json.schemastore.org/claude-code-settings.json";
                description = "JSON schema for Claude Code settings";
              };
              env = lib.mkOption {
                type = lib.types.attrsOf lib.types.str;
                default = {
                  CLAUDE_CODE_MAX_OUTPUT_TOKENS = "64000";
                };
                description = "Environment variables to set";
              };
              companyAnnouncements = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = ["I'm @assistantName@; how can I help?"];
                description = "Messages shown on startup. Use @assistantName@ as placeholder.";
              };
              outputStyle = lib.mkOption {
                type = lib.types.enum ["default" "explanatory" "learning"];
                default = "default";
                description = "https://code.claude.com/docs/en/output-styles";
              };
              permissions = lib.mkOption {
                type = lib.types.submodule {
                  options = {
                    additionalDirectories = lib.mkOption {
                      type = lib.types.listOf lib.types.str;
                      default = ["/tmp" "/private/tmp" "@paiBasePath@"];
                      description = "Additional directories Claude can access; strongly recommend keeping the defaults.";
                    };
                    disableBypassPermissionsMode = lib.mkOption {
                      type = lib.types.bool;
                      default = true;
                      apply = v:
                        if v
                        then "disable"
                        else "";
                      description = "Whether to disable bypass permissions mode";
                    };
                    defaultMode = lib.mkOption {
                      type = lib.types.enum ["default" "acceptEdits" "plan" "bypassPermissions"];
                      default = "default";
                      description = "https://code.claude.com/docs/en/iam#permission-modes";
                    };
                    allow = lib.mkOption {
                      type = lib.types.listOf lib.types.str;
                      default = [
                        "Skill(:*)"
                        "mcp__Ref"
                        "Bash(npm:*)"
                        "Bash(git:*)"
                        "Bash(nix build:*)"
                        "Bash(nix flake check:*)"
                        "Bash(nix flake update:*)"
                        "Bash(nix develop:*)"
                        "Bash(git stash:*)"
                        "Bash(gh:*)"
                        "Bash(sbt:*)"
                        "Bash(bun:*)"
                        "Bash(cargo:*)"
                        "Bash(rustc:*)"
                        "Bash(grep:*)"
                        "Bash(rg:*)"
                        "Bash(fabric:*)"
                        "Bash(gemini:*)"
                        "Bash(codex:*)"
                        "Bash(make:*)"
                        "Bash(ls:*)"
                        "Bash(configure:*)"
                        "Bash(build:*)"
                        "Bash(jq:*)"
                        "Bash(tsc:*)"
                        "Bash(cat:*)"
                        "Bash(find:*)"
                        "Bash(pip:*)"
                        "Bash(magick:*)"
                        "Bash(uv:*)"
                        "Bash(./target/release/:*)"
                        "Bash(./target/debug/:*)"
                        "WebFetch(domain:docs.rs)"
                        "Read(./**)"
                        "Read(/tmp/**)"
                        "Read(/@paiBasePath@/claude/**)"
                        "Glob(/@paiBasePath@/claude/*)"
                        "Grep(/@paiBasePath@/claude/*)"
                        "Write(./*)"
                        "Write(/tmp/**)"
                        "Edit(./*)"
                        "Edit(/tmp/**)"
                        "Glob(./*)"
                        "Grep(./*)"
                        "WebFetch(domain:*)"
                        "WebSearch"
                        "NotebookEdit(./*)"
                      ];
                      description = "Tool permissions to allow. Use lib.mkAfter [...] to append to defaults.";
                    };
                    ask = lib.mkOption {
                      type = lib.types.listOf lib.types.str;
                      default = [
                        "Bash(sudo:*)"
                        "Bash(git push:*)"
                        "Read(./.env)"
                      ];
                      description = "Tool permissions that require user confirmation. Use lib.mkAfter [...] to append to defaults.";
                    };
                    deny = lib.mkOption {
                      type = lib.types.listOf lib.types.str;
                      default = [
                        "Bash(aws:*)"
                        "Bash(gcp:*)"
                        "Bash(gcloud:*)"
                        "Bash(kubectl:*)"
                        "Bash(vault:*)"
                        "Bash(diskutil:*)"
                        "Bash(rm -rf /)"
                        "Bash(rm -rf /*)"
                        "Bash(rm -rf ~)"
                        "Bash(rm -rf $HOME)"
                        "Bash(rm -rf $PAI_HOME)"
                        "Bash(rm -rf $PAI_DIR)"
                        "Bash(sudo rm -rf /)"
                        "Bash(sudo rm -rf /*)"
                        "Bash(fork bomb)"
                        "Bash(dd :*)"
                        "Bash(dd if=/dev/zero of=/dev/sda)"
                        "Bash(mkfs.ext4:*)"
                        "Bash( /dev/sda)"
                        "Bash(> /dev/sda)"
                      ];
                      description = "Tool permissions to always deny. Use lib.mkAfter [...] to append to defaults.";
                    };
                  };
                };
                default = {};
                description = "Permission settings for Claude Code";
              };
              enableAllProjectMcpServers = lib.mkOption {
                type = lib.types.bool;
                default = true;
                description = "Enable all project MCP servers";
              };
              enabledMcpjsonServers = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [];
                description = "List of enabled MCP JSON servers";
              };
              hooks = lib.mkOption {
                type = lib.types.attrsOf (lib.types.listOf lib.types.anything);
                default = {
                  UserPromptSubmit = [
                    {
                      hooks = [
                        {
                          type = "command";
                          command = "@paiBasePath@/claude/hooks/update-tab-titles.js";
                        }
                      ];
                    }
                  ];
                  SessionStart = [
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
                  Stop = [
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
                  PermissionRequest = [
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
                description = "Hook configurations for various Claude Code events";
              };
              statusLine = lib.mkOption {
                type = lib.types.attrsOf lib.types.anything;
                default = {
                  type = "command";
                  command = "bash @paiBasePath@/claude/statusline-command.sh";
                };
                description = "Status line configuration";
              };
              alwaysThinkingEnabled = lib.mkOption {
                type = lib.types.bool;
                default = true;
                description = "Enable always-thinking mode";
              };
              max_tokens = lib.mkOption {
                type = lib.types.int;
                default = 4096;
                description = "Maximum tokens for responses";
              };
            };
          };
          default = {};
          description = ''
            Full Claude Code settings.json configuration.
            This is generated as JSON at build time.
            Use @paiBasePath@ and @assistantName@ as placeholders - they are substituted during build.
            Any key can be added or overridden using standard Nix module merging.
          '';
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
        additionalCoreInstructions = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = "Add content to the bottom of the CORE skill file. You should use markdown headers and styling for this otherwise unlabeled section.";
        };
        keyBio = lib.mkOption {
          type = lib.types.str;
          default = "";
          example = ''
            Example:

            - Job: title at company doing work
            - Home town: grew up in state, now living in place
            - Core interests: security, cryptography, AI, ...
          '';
        };
        keyContacts = lib.mkOption {
          type = lib.types.str;
          default = "";
          example = ''
            Example:

            - **Name** [Role] - email@example.com
            - **Name** [Role] - email@example.com
          '';
        };
        socialMedia = lib.mkOption {
          type = lib.types.str;
          default = "";
          example = ''
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
