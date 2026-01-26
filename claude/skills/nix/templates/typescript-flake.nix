# TypeScript/Node.js Flake Template
# Uses bun as the preferred package manager
{
  description = "TypeScript project";

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
        # Development shell (most common use case)
        devShells.default = pkgs.mkShell {
          nativeBuildInputs = with pkgs; [
            nodejs_22
            bun
            typescript
          ];

          # Optional: Add native dependencies for node-gyp packages
          # buildInputs = with pkgs; [
          #   python3  # Required by node-gyp
          #   vips     # For sharp
          # ];

          shellHook = ''
            echo "TypeScript dev environment loaded"
            echo "Using bun: $(bun --version)"
          '';
        };

        # Optional: Build a distributable package
        # Uncomment and customize if you need npm package output
        # packages.default = pkgs.buildNpmPackage {
        #   pname = "my-package";
        #   version = "1.0.0";
        #   src = ./.;
        #
        #   # Generate with: nix build 2>&1 | grep "got:" | cut -d: -f2
        #   npmDepsHash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
        #
        #   nativeBuildInputs = with pkgs; [
        #     bun
        #     typescript
        #   ];
        #
        #   buildPhase = ''
        #     bun run build
        #   '';
        #
        #   installPhase = ''
        #     mkdir -p $out
        #     cp -r dist/* $out/
        #   '';
        # };

        # Optional: CLI wrapper
        # packages.cli = pkgs.writeShellApplication {
        #   name = "my-cli";
        #   runtimeInputs = [ pkgs.nodejs_22 ];
        #   text = ''
        #     exec node ${self.packages.${system}.default}/index.js "$@"
        #   '';
        # };
      });
}
