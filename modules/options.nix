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
          default = "http://127.0.0.1:11434";
          #default = "https://avalon.savannah-basilisk.ts.net:11434";
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
        automaticPrivacy = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "When enabled, automatically detect private vs public repos and route to local ollama for private work via claude-code-router.";
        };
        privateModel = lib.mkOption {
          type = lib.types.str;
          # ollama
          default = "gpt-oss:20b"; # works for thinking and tools
          #default = "qwen3:30b-thinking"; # think value high not supported
          #default = "magistral:24b"; # think value high not supported
          #default = "nemotron-3-nano:latest"; # think value high not supported for this model

          #default = "qwen3-coder:30b"; # does not support thinking
          #default = "devstral-small-2:24b"; # does not support thinking
          #default = "gemma3:27b"; # does not support thinking
          #default = "deepseek-r1:32b"; # does not support tools
          #default = "glm4:9b"; # does not support thinking

          # llama-cpp
          #default = "Qwen3-Coder-30B-A3B-Instruct-Q8_0.gguf";
          #default = "Qwen_Qwen3-30B-A3B-Instruct-2507-Q8_0.gguf";
          #default = "Devstral-Small-2507-Q4_K_M.gguf";
          description = "Model to use when routing to ollama in private mode";
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

        # MCP servers configuration - generated as mcp.json at build time
        mcpServers = lib.mkOption {
          type = lib.types.attrsOf (lib.types.submodule {
            freeformType = lib.types.attrsOf lib.types.anything;
            options = {
              type = lib.mkOption {
                type = lib.types.str;
                default = "http";
                description = "MCP server type (http, stdio, etc.)";
              };
              url = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
                description = "URL for http-type MCP servers";
              };
              command = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
                description = "Command for stdio-type MCP servers";
              };
              args = lib.mkOption {
                type = lib.types.nullOr (lib.types.listOf lib.types.str);
                default = null;
                description = "Arguments for stdio-type MCP servers";
              };
              headers = lib.mkOption {
                type = lib.types.attrsOf lib.types.str;
                default = {};
                description = "HTTP headers for the MCP server";
              };
              env = lib.mkOption {
                type = lib.types.attrsOf lib.types.str;
                default = {};
                description = "Environment variables for stdio-type MCP servers";
              };
            };
          });
          default = {
            Ref = {
              type = "http";
              url = "https://api.ref.tools/mcp";
              headers = {
                "x-ref-api-key" = "\${REF_TOOLS_KEY}";
              };
            };
          };
          description = ''
            MCP server configurations for Claude Code.
            Each key is the server name, value is the server configuration.
            Use @paiBasePath@ and @assistantName@ as placeholders - they are substituted during build.
            Any server can be added or overridden using standard Nix module merging.
            Example:
              mcpServers = {
                MyServer = {
                  type = "stdio";
                  command = "my-mcp-server";
                  args = ["--port" "8080"];
                };
              };
          '';
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
                  CLAUDE_CODE_ENABLE_TELEMETRY= "0";
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
              attribution = lib.mkOption {
                default = {};
                description = "Attribution settings for git/github actions";
                type = lib.types.submodule {
                  options = {
                    commit = lib.mkOption {
                      type = lib.types.str;
                      default = "🤖 Co-Authored-By: @assistantName@";
                      description = "Attribution for git commits, including any trailers. Empty string hides commit attribution";
                    };
                    pr = lib.mkOption {
                      type = lib.types.str;
                      default = "🤖 Generated with @assistantName@";
                      description = "Attribution for pull request descriptions. Empty string hides pull request attribution";
                    };
                  };
                };
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
                        else null;
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
                        # this will result in a path like "//nix/store/wkcx98..." -- that double slash is necessary for
                        # an absolute filesystem path instead of a project relative one
                        "Read(/@paiBasePath@**)"
                        "Glob(/@paiBasePath@*)"
                        "Grep(/@paiBasePath@*)"
                        "Skill(*)"
                        "mcp__Ref"
                        "Bash(npm *)"
                        "Bash(git *)"
                        "Bash(nix build:*)"
                        "Bash(nix flake *)"
                        "Bash(nix flake *)"
                        "Bash(nix develop *)"
                        "Bash(git stash *)"
                        "Bash(gh *)"
                        "Bash(sbt *)"
                        "Bash(bun *)"
                        "Bash(cargo *)"
                        "Bash(rustc *)"
                        "Bash(readlink *)"
                        "Bash(grep *)"
                        "Bash(rg *)"
                        "Bash(fabric *)"
                        "Bash(gemini *)"
                        "Bash(codex *)"
                        "Bash(make *)"
                        "Bash(ls *)"
                        "Bash(configure *)"
                        "Bash(build *)"
                        "Bash(jq *)"
                        "Bash(tsc *)"
                        "Bash(cat *)"
                        "Bash(find *)"
                        "Bash(pip *)"
                        "Bash(magick *)"
                        "Bash(uv *)"
                        "Bash(./target/release/:*)"
                        "Bash(./target/debug/:*)"
                        "WebFetch(domain:docs.rs)"
                        "WebFetch(domain:github.com)"
                        "Read(./**)"
                        "Read(/tmp/**)"
                        "Bash(cat @paiBasePath@*)"
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
                        "Bash(rm:*)"
                        "Bash(git rm:*)"
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
                  #command = "bash @paiBasePath@/claude/statusline-command.sh";
                  command = "HOME=@paiBasePath@ ccstatusline";
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

        # OpenCode settings.json structure - generated as JSON at build time
        opencodeSettings = lib.mkOption {
          type = lib.types.submodule {
            freeformType = lib.types.attrsOf lib.types.anything;
            options = {
              theme = lib.mkOption {
                type = lib.types.str;
                default = "opencode";
                description = "OpenCode theme name";
              };
              instructions = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = ["@paiBasePath@/claude/skills/CORE/SKILL.md" "AGENTS.md" "CONTRIBUTING.md" "DEVELOPMENT.md"];
                description = "List of instruction file paths. Use @paiBasePath@ placeholder.";
              };
              model = lib.mkOption {
                type = lib.types.str;
                default = "ollama/gpt-oss:20b";
                description = "Default model to use (format: provider/model)";
              };
              tui = lib.mkOption {
                type = lib.types.submodule {
                  freeformType = lib.types.attrsOf lib.types.anything;
                  options = {
                    scroll_speed = lib.mkOption {
                      type = lib.types.int;
                      default = 3;
                      description = "Scroll speed for the TUI";
                    };
                  };
                };
                default = {};
                description = "TUI settings for OpenCode";
              };
              keybinds = lib.mkOption {
                type = lib.types.submodule {
                  freeformType = lib.types.attrsOf lib.types.str;
                  options = {
                    leader = lib.mkOption {
                      type = lib.types.str;
                      default = ",";
                      description = "Leader key for keybinds (e.g., \",\" or \"ctrl+x\")";
                    };
                    app_exit = lib.mkOption {
                      type = lib.types.nullOr lib.types.str;
                      default = null;
                      description = "Exit the application";
                    };
                    session_new = lib.mkOption {
                      type = lib.types.nullOr lib.types.str;
                      default = null;
                      description = "Create a new session";
                    };
                    session_interrupt = lib.mkOption {
                      type = lib.types.nullOr lib.types.str;
                      default = null;
                      description = "Stop session execution";
                    };
                    sidebar_toggle = lib.mkOption {
                      type = lib.types.nullOr lib.types.str;
                      default = null;
                      description = "Show/hide the sidebar";
                    };
                    model_list = lib.mkOption {
                      type = lib.types.nullOr lib.types.str;
                      default = null;
                      description = "Show available models";
                    };
                  };
                };
                default = {};
                description = ''
                  Keybind settings for OpenCode. See https://opencode.ai/docs/keybinds/
                  Common keys: leader, app_exit, session_new, session_interrupt, sidebar_toggle, model_list
                  Any keybind from the docs can be added as an arbitrary key/value pair.
                '';
              };
              provider = lib.mkOption {
                type = lib.types.attrsOf (lib.types.submodule {
                  freeformType = lib.types.attrsOf lib.types.anything;
                  options = {
                    npm = lib.mkOption {
                      type = lib.types.str;
                      description = "NPM package for the provider SDK";
                    };
                    name = lib.mkOption {
                      type = lib.types.str;
                      description = "Display name for the provider";
                    };
                    options = lib.mkOption {
                      type = lib.types.attrsOf lib.types.anything;
                      default = {};
                      description = "Provider-specific options (e.g., baseURL)";
                    };
                    models = lib.mkOption {
                      type = lib.types.attrsOf (lib.types.submodule {
                        freeformType = lib.types.attrsOf lib.types.anything;
                        options = {
                          name = lib.mkOption {
                            type = lib.types.str;
                            description = "Display name for the model";
                          };
                          tool_call = lib.mkOption {
                            type = lib.types.nullOr lib.types.bool;
                            default = null;
                            description = "Whether the model supports tool calls";
                          };
                          reasoning = lib.mkOption {
                            type = lib.types.nullOr lib.types.bool;
                            default = null;
                            description = "Whether the model supports reasoning";
                          };
                          temperature = lib.mkOption {
                            type = lib.types.nullOr lib.types.bool;
                            default = null;
                            description = "Whether the model supports temperature setting";
                          };
                          options = lib.mkOption {
                            type = lib.types.attrsOf lib.types.anything;
                            default = {};
                            description = "Model-specific options (e.g., num_ctx)";
                          };
                        };
                      });
                      default = {};
                      description = "Models available for this provider";
                    };
                  };
                });
                default = {
                  ollama = {
                    npm = "@ai-sdk/openai-compatible";
                    name = "Ollama";
                    options = {
                      baseURL = "@ollamaHost@/v1";
                    };
                    models = {
                      "gpt-oss:20b" = {
                        name = "GPT OSS 20b";
                        tool_call = true;
                        reasoning = true;
                        temperature = true;
                        options = {
                          num_ctx = 65536;
                        };
                      };
                      "devstral-small-2:24b" = {
                        name = "Devstral Small 24b";
                        tool_call = true;
                        reasoning = true;
                        temperature = true;
                        options = {
                          num_ctx = 32768;
                        };
                      };
                      "nemotron-3-nano:latest" = {
                        name = "Nemotron 3 Nano";
                        tool_call = true;
                        reasoning = true;
                        temperature = true;
                        options = {
                          num_ctx = 65536;
                        };
                      };
                      "ministral-3:14b" = {
                        name = "Ministral 3 14b";
                        tool_call = true;
                        reasoning = true;
                        temperature = true;
                        options = {
                          num_ctx = 32768;
                        };
                      };
                      "qwen3:30b" = {
                        name = "Qwen3 30b A3B";
                        tool_call = true;
                        reasoning = true;
                        temperature = true;
                      };
                      "qwen3-coder:30b" = {
                        name = "Qwen3 Coder 30b";
                        tool_call = true;
                        reasoning = true;
                        temperature = true;
                        options = {
                          num_ctx = 100000;
                        };
                      };
                      "deepseek-r1:32b" = {
                        name = "Deepseek-r1 32b";
                        tool_call = false;
                        reasoning = true;
                        temperature = true;
                        options = {
                          num_ctx = 65536;
                        };
                      };
                      "gemma3:27b" = {
                        name = "Gemma3 27b";
                      };
                      "llama3:8b" = {
                        name = "Llama3 8b";
                      };
                      "glm4:9b" = {
                        name = "GLM4";
                      };
                    };
                  };
                };
                description = "Provider configurations with their models";
              };
            };
          };
          default = {};
          description = ''
            OpenCode config.json configuration.
            Generated as JSON at build time with hardcoded $schema and autoupdate.
            Use @paiBasePath@ and @ollamaHost@ as placeholders - they are substituted during build.
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
