---
name: nix
description: Nix language, flakes, and package management. ALWAYS LOAD when in any development project (detected by flake.nix, Cargo.toml, package.json, pyproject.toml) or when installing packages. Covers flake patterns, dev shells, packaging, and OS configuration.
---

# Nix Skill

Nix is a declarative package manager, build system, and the foundation for NixOS/nix-darwin/home-manager. This skill covers flake-based development workflows for projects on Nix-controlled systems.

## Critical Rules (ALWAYS ENFORCED)

### 1. NEVER Install Packages Globally

On this system, global package installation is **forbidden**. Never suggest or use:
- `npm install -g`
- `pip install` (outside a venv/flake)
- `cargo install` (to ~/.cargo/bin)
- `brew install` (on macOS)
- Any command that puts binaries in /usr/local, ~/.local/bin, etc.

### 2. Use Flakes for Everything

- **In a project**: Add packages to `flake.nix` devShell
- **One-off command**: Use `nix run nixpkgs#<pkg> -- <args>`
- **System-wide**: Add to home-manager or system configuration
- **Temporary shell**: Use `nix shell nixpkgs#pkg1 nixpkgs#pkg2`

### 3. Use `nix develop -c` for Commands

When running commands in a flake project, always use:
```bash
nix develop -c cargo build
nix develop -c npm run test
nix develop -c python -m pytest
```

### 4. Lock File Over Hardcoded Hashes

**Prefer** specifying inputs in flake.nix and using `flake.lock` for pinning:
```nix
inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
```

**Avoid** fetchers with hardcoded hashes unless absolutely necessary:
```nix
# Only when flake inputs won't work
src = fetchurl {
  url = "...";
  sha256 = "sha256-...";  # Avoid this pattern when possible
};
```

### 5. Use `path:.` Prefix for Local Flakes

Always use `path:` prefix to ensure all files are accessible (not just git-tracked):
```bash
nix build path:.
nix develop path:. -c cargo build
```

---

## Development Workflow

### Bootstrap New Projects

For temporary/bootstrap environments, use the pre-built dev environment:
```bash
nix develop github:zmre/pwdev#all
```

This provides Rust, TypeScript, Python, and common tools for initializing new projects.

### Direnv Integration (Recommended)

Create `.envrc` in project root:
```bash
use flake . --accept-flake-config
```

This automatically activates the dev shell when entering the directory.

### Adding Packages to a Project

1. Edit `flake.nix` to add packages to `devShell.buildInputs`
2. Run `nix develop` or let direnv reload
3. The package is now available in the project shell

### Running Temporary One-Off Commands

For tools you don't need permanently:
```bash
nix run nixpkgs#jq -- '.foo' file.json
nix run nixpkgs#ripgrep -- "pattern" .
nix run nixpkgs#imagemagick -- convert in.png out.jpg
```

---

## Unfree Packages

### Recommended: Use nixpkgs-unfree

The `config.allowUnfree = true` setting does **NOT** work with `nix develop`. Use `numtide/nixpkgs-unfree` instead:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-unfree.url = "github:numtide/nixpkgs-unfree";
    nixpkgs-unfree.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { nixpkgs, nixpkgs-unfree, ... }:
    # Use nixpkgs-unfree.legacyPackages.${system} for unfree packages
}
```

### Alternative: Impure Mode

For quick testing only:
```bash
NIXPKGS_ALLOW_UNFREE=1 nix develop --impure
```

---

## Caching Configuration

### nixConfig Block

Enable extra substituters for faster builds:
```nix
{
  nixConfig = {
    extra-substituters = [
      "https://cache.nixos.org"
      "https://nix-community.cachix.org"
      "https://your-cache.cachix.org"
    ];
    extra-trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "your-cache.cachix.org-1:..."
    ];
  };
  # ... rest of flake
}
```

### Accepting Flake Config

Options to accept nixConfig settings:
- Direnv: `use flake . --accept-flake-config` in `.envrc`
- Manual: `nix develop --accept-flake-config`
- System-wide: Add to `nix.settings.trusted-substituters` in system config

See `reference/caching-and-direnv.md` for detailed Cachix setup.

---

## Flake Helper Libraries

### flake-utils (Simple)

Best for: Single-system or basic multi-system support, most projects.

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in {
        devShells.default = pkgs.mkShell {
          buildInputs = [ pkgs.git pkgs.jq ];
        };
      });
}
```

### flake-parts (Modular)

Best for: Complex projects with many outputs, reusable modules, or accepting options.

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
  };

  outputs = inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" "aarch64-darwin" ];
      perSystem = { pkgs, ... }: {
        devShells.default = pkgs.mkShell {
          buildInputs = [ pkgs.git pkgs.jq ];
        };
      };
    };
}
```

### When to Use Each

| Criteria | flake-utils | flake-parts |
|----------|-------------|-------------|
| Simple dev shell | ✅ Preferred | Works |
| Single package | ✅ Preferred | Works |
| Multiple packages | Works | ✅ Preferred |
| Reusable modules | Limited | ✅ Preferred |
| Configurable options | Limited | ✅ Preferred |
| Learning curve | Lower | Higher |

---

## Quick Reference Commands

### Flake Management
```bash
nix flake init                    # Initialize new flake
nix flake update                  # Update all inputs
nix flake update nixpkgs          # Update specific input
nix flake lock                    # Lock without updating
nix flake check                   # Validate flake
nix flake show                    # Display outputs
nix flake metadata                # Inspect metadata
```

### Development
```bash
nix develop                       # Enter default devShell
nix develop -c <cmd>              # Run command in devShell
nix develop .#other-shell         # Enter named devShell
nix shell nixpkgs#pkg             # Temporary shell with package
```

### Building & Running
```bash
nix build                         # Build default package
nix build .#specific-package      # Build named package
nix run                           # Build and run default app
nix run nixpkgs#<pkg>             # Run package from nixpkgs
```

### Debugging
```bash
nix log /nix/store/...            # View build logs
nix why-depends .#a nixpkgs#b     # Show dependency path
nix eval --expr '...'             # Evaluate Nix expression
nix build --show-trace            # Show full error trace
nix build --no-substitute         # Bypass cache (debug cache issues)
```

---

## Workflow Links

Load these as needed for specific tasks:

| Task | Workflow File |
|------|---------------|
| Build failures, missing deps | `workflows/troubleshooting.md` |
| Package pre-built binary | `workflows/packaging-binary.md` |
| Package from source | `workflows/packaging-source.md` |
| Rust project flake | `workflows/rust-flake.md` |
| Python project flake | `workflows/python-flake.md` |
| TypeScript project flake | `workflows/typescript-flake.md` |
| GitHub Actions + Cachix | `workflows/ci-caching.md` |
| Multi-host OS config | `workflows/dendritic-pattern.md` |

## Reference Materials

| Topic | Reference File |
|-------|----------------|
| Common Nix patterns | `reference/common-patterns.md` |
| Flake inputs & follows | `reference/flake-inputs.md` |
| Common gotchas | `reference/gotchas.md` |
| Caching & Direnv setup | `reference/caching-and-direnv.md` |

## Templates

Copy these for new projects:
- `templates/basic-flake.nix` - Minimal flake
- `templates/rust-flake.nix` - Rust with crane + rust-overlay
- `templates/python-flake.nix` - Python with uv2nix
- `templates/typescript-flake.nix` - TypeScript/Node project
- `templates/ci-workflow.yml` - GitHub Actions with Cachix
- `templates/.envrc` - Direnv configuration
