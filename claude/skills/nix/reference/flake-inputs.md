# Flake Inputs Reference

Common flake inputs and how to configure them.

---

## Standard Inputs

### nixpkgs

```nix
inputs = {
  # Unstable (latest packages, may have breaking changes)
  nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  # Stable release (for production)
  nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";

  # Darwin-specific branch (macOS)
  nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-24.11-darwin";
};
```

### flake-utils

Simple multi-system support:

```nix
inputs.flake-utils.url = "github:numtide/flake-utils";
```

### flake-parts

Modular flake framework:

```nix
inputs.flake-parts.url = "github:hercules-ci/flake-parts";
```

---

## Rust Inputs

### rust-overlay

Provides Rust toolchains:

```nix
inputs = {
  rust-overlay.url = "github:oxalica/rust-overlay";
};

outputs = { nixpkgs, rust-overlay, ... }:
  let
    overlays = [ (import rust-overlay) ];
    pkgs = import nixpkgs { inherit system overlays; };

    # From rust-toolchain.toml (recommended)
    rustToolchain = pkgs.rust-bin.fromRustupToolchainFile ./rust-toolchain.toml;

    # Or specify directly
    rustToolchain = pkgs.rust-bin.stable.latest.default;
  in ...
```

### crane

Incremental Rust builds with dependency caching:

```nix
inputs = {
  crane.url = "github:ipetkov/crane";
};

outputs = { nixpkgs, crane, rust-overlay, ... }:
  let
    craneLib = (crane.mkLib pkgs).overrideToolchain rustToolchain;

    # Cache dependencies separately
    cargoArtifacts = craneLib.buildDepsOnly { src = ./.; };

    # Build uses cached deps
    package = craneLib.buildPackage {
      inherit cargoArtifacts;
      src = ./.;
    };
  in ...
```

---

## Python Inputs

### uv2nix (Recommended)

Modern Python with uv lock files:

```nix
inputs = {
  pyproject-nix = {
    url = "github:pyproject-nix/pyproject.nix";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  uv2nix = {
    url = "github:pyproject-nix/uv2nix";
    inputs.pyproject-nix.follows = "pyproject-nix";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  pyproject-build-systems = {
    url = "github:pyproject-nix/build-system-pkgs";
    inputs.pyproject-nix.follows = "pyproject-nix";
    inputs.uv2nix.follows = "uv2nix";
    inputs.nixpkgs.follows = "nixpkgs";
  };
};
```

### poetry2nix (Legacy)

For projects using Poetry:

```nix
inputs = {
  poetry2nix = {
    url = "github:nix-community/poetry2nix";
    inputs.nixpkgs.follows = "nixpkgs";
  };
};
```

---

## Unfree Packages

### nixpkgs-unfree (Recommended)

Works with `nix develop` (unlike `config.allowUnfree`):

```nix
inputs = {
  nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  nixpkgs-unfree = {
    url = "github:numtide/nixpkgs-unfree";
    inputs.nixpkgs.follows = "nixpkgs";
  };
};

outputs = { nixpkgs, nixpkgs-unfree, ... }:
  let
    # Use for unfree packages
    unfreePkgs = nixpkgs-unfree.legacyPackages.${system};

    # Regular pkgs for free packages
    pkgs = nixpkgs.legacyPackages.${system};
  in {
    devShells.default = pkgs.mkShell {
      buildInputs = [
        pkgs.git
        unfreePkgs.vscode  # Unfree package
      ];
    };
  };
```

---

## The `follows` Pattern

**Always** use `follows` to prevent duplicate nixpkgs:

```nix
inputs = {
  nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  flake-utils.url = "github:numtide/flake-utils";

  # This input depends on nixpkgs - make it follow ours
  some-overlay = {
    url = "github:example/overlay";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  # Chain follows for transitive dependencies
  another-tool = {
    url = "github:example/tool";
    inputs.nixpkgs.follows = "nixpkgs";
    inputs.flake-utils.follows = "flake-utils";
  };
};
```

**Why?** Without follows:
- Each input downloads its own nixpkgs
- Evaluation is slower
- Build closures are larger
- Version conflicts may occur

---

## All Inputs Must Appear in Outputs

Every declared input must be in the outputs function signature:

```nix
inputs = {
  nixpkgs.url = "...";
  flake-utils.url = "...";
  some-tool.url = "...";
};

# All inputs must be listed here (or use ...)
outputs = { self, nixpkgs, flake-utils, some-tool, ... }:
```

---

## Pinning Inputs

The `flake.lock` file pins all inputs. To update:

```bash
# Update all inputs
nix flake update

# Update specific input
nix flake update nixpkgs

# Lock without updating
nix flake lock
```

**Avoid** hardcoded hashes in flake.nix when possible:

```nix
# Prefer this (version in flake.lock)
inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

# Avoid this (version hardcoded)
src = fetchFromGitHub {
  owner = "...";
  repo = "...";
  rev = "abc123";  # Harder to update
  sha256 = "...";
};
```
