# Rust Project Flake Patterns

Two primary approaches for Rust projects in Nix: simple (buildRustPackage) and advanced (crane).

## Simple Approach: flake-utils + rust-overlay

Best for straightforward projects without complex caching needs.

```nix
{
  description = "My Rust project";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    rust-overlay.url = "github:oxalica/rust-overlay";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { nixpkgs, rust-overlay, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        overlays = [ (import rust-overlay) ];
        pkgs = import nixpkgs { inherit system overlays; };
        # Load toolchain from rust-toolchain.toml
        rusttoolchain =
          pkgs.rust-bin.fromRustupToolchainFile ./rust-toolchain.toml;
      in
      rec {
        packages = {
          my-project = pkgs.rustPlatform.buildRustPackage {
            pname = "my-project";
            version = "0.1.0";
            src = ./.;
            cargoLock.lockFile = ./Cargo.lock;
            nativeBuildInputs = [ pkgs.pkg-config ];
            buildInputs = [ rusttoolchain pkgs.libiconv ];
          };
        };
        defaultPackage = packages.my-project;

        devShell = pkgs.mkShell {
          buildInputs = with pkgs; [
            rusttoolchain
            pkg-config
            libiconv
          ];
        };
      });
}
```

## Advanced Approach: crane + rust-overlay

Best for larger projects needing dependency caching, multiple outputs, and CI checks.

### Core Setup

```nix
{
  nixConfig = {
    extra-substituters = [
      "https://cache.nixos.org"
      "https://nix-community.cachix.org"
    ];
    extra-trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];
  };
  description = "My Rust project";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    rust-overlay.url = "github:oxalica/rust-overlay";
    crane.url = "github:ipetkov/crane";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, rust-overlay, crane, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system: let
      overlays = [(import rust-overlay)];
      pkgs = import nixpkgs {
        inherit system overlays;
        config.allowUnfree = true;  # If needed
      };

      # Toolchain from rust-toolchain.toml
      rustToolchain = pkgs.rust-bin.fromRustupToolchainFile ./rust-toolchain.toml;

      # Create crane lib with our toolchain
      craneLib = (crane.mkLib pkgs).overrideToolchain rustToolchain;

      # Single source of truth for version
      cargoToml = builtins.fromTOML (builtins.readFile ./Cargo.toml);
      version = cargoToml.package.version;
```

### Source Filtering

Filter sources to avoid unnecessary rebuilds:

```nix
      # Include Rust sources plus any embedded assets
      src = pkgs.lib.cleanSourceWith {
        src = ./.;
        filter = path: type:
          (craneLib.filterCargoSources path type)
          || (builtins.match ".*templates.*" path != null)
          || (builtins.match ".*\\.md$" path != null)
          || (builtins.match ".*\\.png$" path != null);
      };
```

### Platform-Specific Build Inputs

```nix
      # Shared native build inputs
      commonNativeBuildInputs = with pkgs; [
        pkg-config
        llvmPackages.libclang
      ] ++ (pkgs.lib.optionals pkgs.stdenv.isDarwin [
        pkgs.apple-sdk
      ]);

      # Shared build inputs
      commonBuildInputs = with pkgs; [
        openssl
      ] ++ (pkgs.lib.optionals pkgs.stdenv.isLinux [
        gtk3
        glib
        webkitgtk_4_1
      ]) ++ (pkgs.lib.optionals pkgs.stdenv.isDarwin [
        darwin.apple_sdk.frameworks.Security
        darwin.apple_sdk.frameworks.SystemConfiguration
      ]);

      # Shared environment variables
      commonEnvVars = {
        LIBCLANG_PATH = "${pkgs.llvmPackages.libclang.lib}/lib";
        # Linux-specific bindgen config
        BINDGEN_EXTRA_CLANG_ARGS =
          pkgs.lib.optionalString pkgs.stdenv.isLinux
          "-isystem ${pkgs.stdenv.cc.libc.dev}/include";
      };
```

### Dependency Caching with cargoArtifacts

The key crane pattern - build dependencies separately:

```nix
      # Common arguments shared between builds
      commonArgs = commonEnvVars // {
        inherit src;
        strictDeps = true;
        pname = "my-project";
        inherit version;
        nativeBuildInputs = commonNativeBuildInputs;
        buildInputs = commonBuildInputs;
      };

      # Build dependencies only (cached separately from source changes)
      cargoArtifacts = craneLib.buildDepsOnly (commonArgs // {
        # Use clean source for dependency-only build
        src = craneLib.cleanCargoSource ./.;
      });
```

### Package Definitions

```nix
    in rec {
      # Main package
      packages.my-project = craneLib.buildPackage (commonArgs // {
        inherit cargoArtifacts;
        cargoExtraArgs = "--locked --all-features";
        doCheck = false;  # Tests run separately

        meta = with pkgs.lib; {
          description = "My Rust project";
          homepage = "https://github.com/user/my-project";
          license = licenses.mit;
          mainProgram = "my-project";
          platforms = platforms.unix;
        };
      });

      packages.default = packages.my-project;

      # Clippy check
      packages.clippy = craneLib.cargoClippy (commonArgs // {
        inherit cargoArtifacts;
        cargoClippyExtraArgs = "--all-targets -- -D warnings";
      });

      # Test package
      packages.tests = craneLib.cargoTest (commonArgs // {
        inherit cargoArtifacts;
        cargoTestExtraArgs = "--all-features";
      });

      # Format check
      packages.fmt = craneLib.cargoFmt {
        inherit src;
      };
```

### Checks Attribute

Integrate with `nix flake check`:

```nix
      # Checks run by `nix flake check`
      checks = {
        inherit (packages) my-project clippy fmt tests;
      } // pkgs.lib.optionalAttrs pkgs.stdenv.isDarwin {
        # Darwin-only checks
        inherit (packages) macos-specific-check;
      };
```

### Release Packaging

Create distributable archives:

```nix
      # Platform-specific arch string
      archString =
        if system == "aarch64-darwin" then "macos-arm64"
        else if system == "x86_64-darwin" then "macos-x86_64"
        else if system == "aarch64-linux" then "linux-arm64"
        else if system == "x86_64-linux" then "linux-x86_64"
        else system;

      packages.release = pkgs.runCommand "my-project-release-${version}" {
        nativeBuildInputs = [pkgs.gnutar pkgs.gzip];
      } ''
        mkdir -p $out
        tar -czvf $out/my-project-${archString}.tar.gz \
          -C ${packages.my-project}/bin \
          my-project
        cd $out
        sha256sum *.tar.gz > SHA256SUMS
      '';
```

### Development Shell

```nix
      devShells.default = craneLib.devShell (commonEnvVars // {
        # Include checks to ensure dev environment matches CI
        checks = self.checks.${system};

        # Build inputs from common + dev tools
        inputsFrom = [packages.my-project];
        packages = with pkgs; [
          cargo-watch
          rust-analyzer
        ] ++ (pkgs.lib.optionals pkgs.stdenv.isDarwin [
          # macOS-specific dev tools
        ]);

        RUST_LOG = "my_project=debug";

        shellHook = ''
          # Configure git hooks if in a git repo
          if git rev-parse --git-dir > /dev/null 2>&1; then
            current_hooks_path=$(git config --local core.hooksPath 2>/dev/null || echo "")
            if [[ "$current_hooks_path" != ".githooks" ]]; then
              git config --local core.hooksPath .githooks
            fi
          fi
        '';
      });

      # Apps
      apps.default = flake-utils.lib.mkApp {drv = packages.my-project;};
    });
}
```

## Key Patterns Summary

| Pattern | Purpose |
|---------|---------|
| `rust-bin.fromRustupToolchainFile` | Load toolchain from `rust-toolchain.toml` |
| `crane.mkLib pkgs).overrideToolchain` | Create crane with custom toolchain |
| `craneLib.buildDepsOnly` | Cache dependencies separately |
| `craneLib.cleanCargoSource` | Filter to only Cargo-relevant files |
| `lib.cleanSourceWith + filter` | Custom source filtering |
| `lib.optionals stdenv.isDarwin` | Platform-specific dependencies |
| `builtins.fromTOML (builtins.readFile)` | Read version from Cargo.toml |
| `craneLib.cargoClippy/cargoTest/cargoFmt` | Separate check packages |
| `checks = { inherit ... }` | Enable `nix flake check` |

## When to Use Which

**Simple (buildRustPackage):**
- Small projects
- No CI caching needs
- Quick iteration during development
- Projects without platform-specific code

**Advanced (crane):**
- Large projects with slow dependency builds
- CI pipelines needing cached dependencies
- Multiple output variants (debug, release, checks)
- Platform-specific builds (Darwin/Linux differences)
- Projects with non-Rust assets to embed
