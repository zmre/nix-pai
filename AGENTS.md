# Agents Memory for nix-pai
## Project Overview

**nix-pai** (Nix Personal AI Infrastructure) is a NixOS flake that provides a customizable, sandboxed AI development environment. It's not meant to be run directly, but serves as a configurable template for building personalized AI assistant systems.

The project packages multiple AI tools (claude, codex, gemini, fabric) with:
- Centralized secrets management via system keychains
- Skills-based context management
- Configurable permissions and hooks
- Shared filesystem-first prompts and helpers

Based on Daniel Miessler's Personal AI Infrastructure but heavily modified for Nix-based deployment, privacy-first operation, and multi-AI tool support.

## Core Architecture

### Flake Structure

The flake uses **flake-parts** for modularity:
- `flake.nix` - Main flake entry point, imports the PAI module
- `modules/pai.nix` - Core module that builds the PAI package
- `modules/options.nix` - All configurable options for the PAI system

The PAI module creates a single derivation that bundles:
1. Multiple AI CLI tools (claude-code, codex, gemini-cli, fabric-ai)
2. Configuration files (settings.json, mcp.json, hooks, skills, agents)
3. A customized wrapper command that loads secrets and sets environment

### Build Process Flow

1. **Module options** define user customization (assistant name, colors, permissions, skills)
2. **pai.nix buildPhase** packages core tools from nixpkgs and nix-ai-tools
3. **installPhase** symlinks all tools to $out/bin
4. **Wrapper creation** around each tool to inject secrets from keychain
5. **Main command wrapper** created with custom name, loading all PAI context
6. **postFixup** copies user's extra skills/hooks/agents and performs substitutions

The result is a single package where running the custom command (e.g., `iris` or `jv`) starts claude with full PAI configuration.

### Package Categories

The flake separates packages into two categories to avoid conflicts with user-installed tools:

**corePackages** - Globally available when PAI is installed:
- AI CLI tools (claude-code, codex, gemini-cli, fabric-ai)
- ccstatusline and other PAI-specific utilities

**hiddenPackages** - Available only to the AI assistant via PATH:
- Runtime dependencies: `bun`, `jq`, `curl`, `nodejs`
- User's `extraPackages`
- Linux-specific: `libsecret` (for secret-tool)

This separation prevents PAI's bundled tools (like `jq` or `bun`) from conflicting with versions the user may have installed system-wide. The `localPath` variable constructs a PATH containing only hiddenPackages, which is injected into AI tool wrappers.

### Secrets Management

Secrets are loaded at runtime (not build time) via wrappers:
- **macOS**: Uses `security` command to fetch from Apple Keychain
- **Linux**: Uses `secret-tool` from libsecret/gnome-keyring

Default secrets: `openaikey`, `geminikey`, `anthropickey`, `reftoolskey`, `ollamakey`

Add custom secrets via `extraSecrets` option in flake configuration.

### Configuration Substitution

Template placeholders in config files are replaced during build:
- `@assistantName@` - Custom assistant name
- `@paiBasePath@` - Path to PAI installation ($out)
- `@userFullName@` - User's full name
- `@permissionsAllow@/@permissionsAsk@/@permissionsDeny@` - Permission rules
- `@defaultMode@/@outputStyle@/@companyAnnouncements@` - Claude settings

These substitutions happen in `installPhase` via `substituteInPlace`.

### Skills System

Skills are markdown files in `claude/skills/` that provide specialized context:
- `SKILL.md` - Main skill definition with description and instructions
- `workflows/*.md` - Specific task workflows
- `assets/*.md` or `resources/*.md` - Reference materials

Users can add extra skills via `extraSkills` option (list of paths).

### Hooks System

TypeScript hooks in `claude/hooks/` respond to events:
- `SessionStart` - Load core context, initialize session
- `UserPromptSubmit` - Update tab titles
- `Stop` - Capture events, run cleanup

Hooks use Bun runtime and have access to full PAI environment.

## Development Commands

### Building the Flake

```bash
nix build
```

This creates `result/` symlink to the built PAI package.

### Running Directly

```bash
nix run
```

Runs the default package (the custom assistant command).

### Checking Flake

```bash
nix flake check
```

Validates flake structure.

### Updating Dependencies

```bash
nix flake update
```

Updates `flake.lock` with latest inputs (nixpkgs, nix-ai-tools).

## Configuration Options

Key options in `modules/options.nix`:

- `pai.assistantName` - Name of the AI assistant (default: "Iris")
- `pai.commandName` - Terminal command name (default: "iris")
- `pai.assistantColor` - Message color (default: "purple")
- `pai.userFullName` - User's full name (default: "Boss")
- `pai.extraPackages` - Additional packages to include
- `pai.extraSecrets` - Additional secrets to load from keychain
- `pai.extraSkills` - Additional skill directories to copy
- `pai.extraHooks` - Additional hook files to copy
- `pai.extraAgents` - Additional agent files to copy
- `pai.ollamaServer` - Ollama server URL (default: "127.0.0.1:11434")

Claude-specific settings (`pai.claudeSettings.*`):
- `permissions.defaultMode` - Permission mode (default/acceptEdits/plan/bypassPermissions)
- `permissions.allow/ask/deny` - Permission rule lists
- `outputStyle` - Output style (default/explanatory/learning)
- `companyAnnouncements` - Startup messages list
- `hooks` - Event hooks configuration
- `statusLine` - Status line configuration

MCP server configuration (`pai.mcpServers`):
- Attribute set of MCP server configurations
- Each server can have: type, url, command, args, headers, env
- Default includes `Ref` server for documentation lookup
- Supports `@paiBasePath@` and `@assistantName@` placeholders

User context (used in CORE skill):
- `pai.keyBio` - User biography
- `pai.keyContacts` - Important contacts
- `pai.socialMedia` - Social media links

## Important Files

- `claude/settings.json` - Generated from `pai.claudeSettings` option (not checked in)
- `claude/mcp.json` - Generated from `pai.mcpServers` option (not checked in)
- `claude/skills/CORE/SKILL.md` - Core system identity and instructions
- `claude/hooks/load-core-context.ts` - Loads CORE skill on session start
- `opencode/config.json` - OpenCode configuration (private/local AI)
- `SECURITY.md` - Critical security guidelines for public repo
- `modules/options.nix` - All configurable options including claudeSettings and mcpServers
- `modules/pai.nix` - Build logic that generates config files from options

## Security Guidelines

This is a **PUBLIC** repository. Never commit:
- Personal API keys or tokens
- Private contact information
- Personal context files
- Business-specific information
- Any content from your private `~/.claude/` directory without sanitizing

Before commits:
1. Run `git remote -v` to verify repository
2. Audit all changes for sensitive data
3. Use placeholders like `@assistantName@` instead of hardcoded values
4. Test in clean environment

## Technology Stack Preferences

Per the CORE skill configuration:
- **Languages**: Rust > TypeScript > Python
- **Package Managers**:
  - Rust: cargo
  - JavaScript/TypeScript: bun (NOT npm/yarn/pnpm)
  - Python: uv (NOT pip)

## Working with This Repository

### Adding New Skills

1. Create skill directory in `claude/skills/your-skill-name/`
2. Add `SKILL.md` with name, description, and instructions
3. Optionally add `workflows/*.md` for specific tasks
4. Skills are automatically loaded if in the base directory
5. Or add via `extraSkills` config option for external skills

### Modifying Hooks

1. Edit TypeScript files in `claude/hooks/`
2. Hooks run with Bun and access `@paiBasePath@` environment
3. Register hooks in `claude/settings.json` under `hooks` section
4. Use `substituteInPlace` in `pai.nix` if template variables needed

### Adding New Tools

1. Determine package category:
   - **corePackages**: For AI CLI tools that should be globally available
   - **hiddenPackages**: For dependencies that should only be available to AI wrappers (to avoid conflicts)
2. Add package to the appropriate list in `pai.nix`
3. Optionally add to `binariesToWrap` if the tool needs secrets injected
4. Add enable option in `modules/options.nix` under `otherTools` for optional tools
5. Guard with `lib.optionals` in package list for conditional inclusion

### Testing Changes

After modifying the flake:
```bash
nix build
./result/bin/your-command-name
```

The built package is in `result/` with all files in their final form.

