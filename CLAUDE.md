# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

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

Claude-specific settings:
- `pai.extraClaudeSettings.defaultMode` - Permission mode (default/acceptEdits/plan/bypassPermissions)
- `pai.extraClaudeSettings.permissionsAllow/Ask/Deny` - Permission rules
- `pai.extraClaudeSettings.outputStyle` - Output style (default/explanatory/learning)
- `pai.extraClaudeSettings.companyAnnouncements` - Startup message

User context (used in CORE skill):
- `pai.keyBio` - User biography
- `pai.keyContacts` - Important contacts
- `pai.socialMedia` - Social media links

## Important Files

- `claude/settings.json` - Claude Code settings with permissions and hooks
- `claude/mcp.json` - MCP server configuration
- `claude/skills/CORE/SKILL.md` - Core system identity and instructions
- `claude/hooks/load-core-context.ts` - Loads CORE skill on session start
- `opencode/config.json` - OpenCode configuration (private/local AI)
- `SECURITY.md` - Critical security guidelines for public repo

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

1. Add package to `corePackages` list in `pai.nix`
2. Optionally add to `binariesToWrap` if needs secrets
3. Add enable option in `modules/options.nix` under `otherTools`
4. Guard with `lib.optionals` in package list

### Testing Changes

After modifying the flake:
```bash
nix build
./result/bin/your-command-name
```

The built package is in `result/` with all files in their final form.
