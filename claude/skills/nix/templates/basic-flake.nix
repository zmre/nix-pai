# Basic Flake Template
# A minimal flake with dev shell and optional package
{
  description = "Project description";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        # Development shell
        devShells.default = pkgs.mkShell {
          # Build-time tools (compilers, pkg-config, etc.)
          nativeBuildInputs = with pkgs; [
            # Add build tools here
          ];

          # Runtime dependencies
          buildInputs = with pkgs; [
            # Add dependencies here
            git
            jq
          ];

          # Environment variables
          # MY_VAR = "value";

          shellHook = ''
            echo "Development environment loaded"
          '';
        };

        # Uncomment to add a package output
        # packages.default = pkgs.stdenv.mkDerivation {
        #   pname = "my-package";
        #   version = "0.1.0";
        #   src = ./.;
        #
        #   nativeBuildInputs = [ ];
        #   buildInputs = [ ];
        #
        #   buildPhase = ''
        #     # Build commands
        #   '';
        #
        #   installPhase = ''
        #     mkdir -p $out/bin
        #     # Install commands
        #   '';
        # };
      });
}
