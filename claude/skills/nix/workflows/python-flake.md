# Python Project Flake Patterns

Modern uv2nix approach for reproducible Python environments with Nix.

## Required Inputs

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";

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
}
```

Use `follows` extensively to prevent duplicate nixpkgs in the closure.

## Core Setup

```nix
outputs = { nixpkgs, uv2nix, pyproject-nix, pyproject-build-systems, flake-utils, ... }:
  flake-utils.lib.eachDefaultSystem (system:
  let
    inherit (nixpkgs) lib;
    pkgs = nixpkgs.legacyPackages.${system};
    python = pkgs.python312;

    # Load uv workspace from workspace root
    workspace = uv2nix.lib.workspace.loadWorkspace { workspaceRoot = ./.; };

    # Prefer wheels - sdists may need additional overrides
    overlay = workspace.mkPyprojectOverlay { sourcePreference = "wheel"; };

    # Build fixups for packages needing extra dependencies
    pyprojectOverrides = _final: _prev: { };

    # Construct package set with composed overlays
    pythonSet =
      (pkgs.callPackage pyproject-nix.build.packages { inherit python; }).overrideScope
        (lib.composeManyExtensions [
          pyproject-build-systems.overlays.default  # Build tools first
          overlay                                    # Project dependencies
          pyprojectOverrides                         # Custom fixups
        ]);
  in { ... });
```

## Editable Development Shell

```nix
devShell =
  let
    # Enable editable mode for local packages
    editableOverlay = workspace.mkEditablePyprojectOverlay {
      root = "$REPO_ROOT";  # Expanded at runtime
    };

    editablePythonSet = pythonSet.overrideScope (
      lib.composeManyExtensions [
        editableOverlay
        (final: prev: {
          my-package = prev.my-package.overrideAttrs (old: {
            # Filter sources to minimize rebuilds
            src = lib.fileset.toSource {
              root = old.src;
              fileset = lib.fileset.unions [
                (old.src + "/pyproject.toml")
                (old.src + "/README.md")
                (old.src + "/src/my_package/__init__.py")
              ];
            };
            # Hatchling needs editables for PEP-660
            nativeBuildInputs = old.nativeBuildInputs
              ++ final.resolveBuildSystem { editables = [ ]; };
          });
        })
      ]
    );

    venv = editablePythonSet.mkVirtualEnv "my-package-dev-env" workspace.deps.all;
  in
  pkgs.mkShell {
    packages = [ venv pkgs.uv ];

    env = {
      UV_NO_SYNC = "1";              # Don't create venv with uv
      UV_PYTHON = "${venv}/bin/python";  # Use Nix Python
      UV_PYTHON_DOWNLOADS = "never";     # No managed Python downloads
    };

    shellHook = ''
      unset PYTHONPATH  # Undo nixpkgs propagation
      export REPO_ROOT=$(git rev-parse --show-toplevel)
    '';
  };
```

## Key Patterns

### Source Filtering for Editables

Prevents rebuilds when unrelated files change:

```nix
src = lib.fileset.toSource {
  root = old.src;
  fileset = lib.fileset.unions [
    (old.src + "/pyproject.toml")
    (old.src + "/src/package_name/__init__.py")
  ];
};
```

### Build System Dependencies

```nix
# Hatchling with editables
final.resolveBuildSystem { editables = [ ]; }

# Setuptools
final.resolveBuildSystem { setuptools = [ ]; wheel = [ ]; }

# Poetry-core
final.resolveBuildSystem { poetry-core = [ ]; }
```

### Native Library Dependencies

```nix
pyprojectOverrides = final: prev: {
  package-name = prev.package-name.overrideAttrs (old: {
    buildInputs = old.buildInputs ++ [ pkgs.openssl pkgs.libffi ];
  });
};
```

## Legacy: poetry2nix

For older Poetry projects (migration to uv2nix recommended):

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    poetry2nix.url = "github:nix-community/poetry2nix";
  };

  outputs = { nixpkgs, poetry2nix, ... }:
    let
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
      p2n = poetry2nix.lib.mkPoetry2Nix { inherit pkgs; };
    in {
      devShell = pkgs.mkShell {
        packages = [ (p2n.mkPoetryEnv { projectDir = ./.; }) ];
      };
    };
}
```

## Troubleshooting

- **Missing build deps**: Add to `pyprojectOverrides` with `resolveBuildSystem`
- **Native libs**: Add `buildInputs` in override
- **Editable fails**: Ensure correct build system dependency (hatchling needs `editables`)
- **Wheel preference**: Use `sourcePreference = "wheel"` to avoid sdist build issues
