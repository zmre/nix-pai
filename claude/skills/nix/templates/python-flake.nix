# Python Flake Template (uv2nix)
# Modern Python development with uv and editable installs
{
  description = "Python project";

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

  outputs = { nixpkgs, uv2nix, pyproject-nix, pyproject-build-systems, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        inherit (nixpkgs) lib;
        pkgs = nixpkgs.legacyPackages.${system};
        python = pkgs.python312;

        # Load uv workspace from project root
        workspace = uv2nix.lib.workspace.loadWorkspace { workspaceRoot = ./.; };

        # Create package overlay from workspace
        overlay = workspace.mkPyprojectOverlay {
          sourcePreference = "wheel"; # Prefer wheels over sdists
        };

        # Override for build fixups (add as needed)
        pyprojectOverrides = _final: _prev: {
          # Example: Add native dependency
          # some-package = prev.some-package.overrideAttrs (old: {
          #   buildInputs = old.buildInputs ++ [ pkgs.some-lib ];
          # });
        };

        # Construct package set
        pythonSet = (pkgs.callPackage pyproject-nix.build.packages {
          inherit python;
        }).overrideScope (
          lib.composeManyExtensions [
            pyproject-build-systems.overlays.default
            overlay
            pyprojectOverrides
          ]
        );

        # Editable development environment
        editableOverlay = workspace.mkEditablePyprojectOverlay {
          root = "$REPO_ROOT";
        };

        editablePythonSet = pythonSet.overrideScope (
          lib.composeManyExtensions [
            editableOverlay
            # Add editable fixups here if needed
          ]
        );

        # Build virtual environment with all dependencies
        venv = editablePythonSet.mkVirtualEnv "dev-env" workspace.deps.all;
      in
      {
        devShells.default = pkgs.mkShell {
          packages = [
            venv
            pkgs.uv
          ];

          env = {
            # Don't let uv create its own venv
            UV_NO_SYNC = "1";
            # Use Python from our Nix venv
            UV_PYTHON = "${venv}/bin/python";
            # Don't download Python
            UV_PYTHON_DOWNLOADS = "never";
          };

          shellHook = ''
            # Undo nixpkgs PYTHONPATH propagation
            unset PYTHONPATH
            # Set repo root for editable installs
            export REPO_ROOT=$(git rev-parse --show-toplevel)
          '';
        };

        # Optional: Non-editable package for distribution
        # packages.default = pythonSet.mkVirtualEnv "my-package" workspace.deps.default;
      });
}
