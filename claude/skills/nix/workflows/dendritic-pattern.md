# Dendritic Pattern for Multi-Host NixOS/nix-darwin Configuration

The dendritic pattern is a flake-parts usage pattern where **every Nix file is a flake-parts module**. Named for its branch-like structure, it enables clean sharing of code between hosts while allowing per-host customization.

## Why Use It

- **Distributed inputs**: Flake inputs declared next to their usage, making modules self-contained
- **Auto-generated flake.nix**: Uses flake-file to generate flake.nix from modules
- **Platform-spanning modules**: Single module can define Darwin, NixOS, and home-manager configs
- **Path-based organization**: File location serves as feature identifier
- **Shared config system**: All modules contribute to flake-parts config, avoiding specialArgs complexity

## Key Principles

1. **Every file is a flake-parts module** - No exceptions
2. **One feature per file** - Each file implements a single concern
3. **Span all applicable module classes** - Features work across platforms when relevant
4. **Combined platform configs** - A module contains BOTH Darwin and NixOS config; the active platform determines which applies

## Directory Structure

```
.
├── flake.nix              # AUTO-GENERATED via `nix run .#write-flake`
└── modules/
    ├── base.nix           # Core: systems, nixpkgs, overlays
    ├── baseDarwin.nix     # Darwin module type definitions
    ├── baseHome.nix       # Home-manager integration
    ├── baseNixos.nix      # NixOS module type definitions
    ├── hosts/             # Host-specific configurations
    │   ├── mydarwin.nix   # macOS host
    │   └── mynixos.nix    # NixOS host
    ├── apps/              # Application modules (vim, dev tools, etc.)
    ├── services/          # System services (tailscale, ollama, etc.)
    └── system/            # System-level config (fonts, nix settings, etc.)
```

## Module Pattern Example

```nix
{inputs, ...}: {
  # Declare inputs this module needs (distributed, not centralized)
  flake-file.inputs.some-tool.url = "github:owner/repo";

  # Darwin-specific system config
  flake.darwinModules.my-feature = {pkgs, ...}: {
    homebrew.casks = ["some-app"];
  };

  # NixOS-specific system config
  flake.nixosModules.my-feature = {pkgs, ...}: {
    services.something.enable = true;
  };

  # Cross-platform home-manager config
  flake.modules.homeManager.my-feature = {pkgs, lib, ...}: {
    home.packages = [pkgs.something];
  };
}
```

## Reference Implementation

Canonical implementation: `~/src/pw-nix-dendritic/`

See the CLAUDE.md in that repository for complete documentation including:
- Full module patterns for Darwin, NixOS, and home-manager
- Host composition examples
- GPU-aware module patterns
- Common commands (rebuild, write-flake, update)
