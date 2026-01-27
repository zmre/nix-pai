# Rust Flake Template (crane + rust-overlay)
# Advanced setup with dependency caching and multiple outputs
{
  nixConfig = {
    extra-substituters = [
      "https://cache.nixos.org"
      "https://nix-community.cachix.org"
      # Add your cachix cache here
    ];
    extra-trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];
  };

  description = "Rust project";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    rust-overlay.url = "github:oxalica/rust-overlay";
    crane.url = "github:ipetkov/crane";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = {
    self,
    nixpkgs,
    rust-overlay,
    crane,
    flake-utils,
    ...
  }:
    flake-utils.lib.eachDefaultSystem (system: let
      overlays = [(import rust-overlay)];
      pkgs = import nixpkgs {inherit system overlays;};

      # Get rust toolchain from rust-toolchain.toml
      rustToolchain = pkgs.rust-bin.fromRustupToolchainFile ./rust-toolchain.toml;

      # Create crane lib with our toolchain
      craneLib = (crane.mkLib pkgs).overrideToolchain rustToolchain;

      # Read version from Cargo.toml
      cargoToml = builtins.fromTOML (builtins.readFile ./Cargo.toml);
      version = cargoToml.package.version;

      # Source filtering - include Rust sources and assets
      src = pkgs.lib.cleanSourceWith {
        src = ./.;
        filter =
          path: type: (craneLib.filterCargoSources path type)
          # Add additional patterns as needed:
          # || (builtins.match ".*\\.md$" path != null)
          # || (builtins.match ".*\\.json$" path != null)
          ;
      };

      # Common build inputs
      commonNativeBuildInputs = with pkgs; [
        pkg-config
      ];

      commonBuildInputs = with pkgs;
        [
          # Add runtime dependencies here
          # openssl
        ]
        ++ pkgs.lib.optionals pkgs.stdenv.isDarwin [
          pkgs.darwin.apple_sdk.frameworks.Security
          pkgs.darwin.apple_sdk.frameworks.SystemConfiguration
          pkgs.libiconv
        ]
        ++ pkgs.lib.optionals pkgs.stdenv.isLinux [
          # Linux-specific deps
        ];

      # Common args for all builds
      commonArgs = {
        inherit src version;
        pname = "my-project";
        strictDeps = true;
        nativeBuildInputs = commonNativeBuildInputs;
        buildInputs = commonBuildInputs;
      };

      # Build dependencies separately (cached)
      cargoArtifacts = craneLib.buildDepsOnly (commonArgs
        // {
          src = craneLib.cleanCargoSource ./.;
        });
    in {
      # Main package
      packages.default = craneLib.buildPackage (commonArgs
        // {
          inherit cargoArtifacts;
          cargoExtraArgs = "--locked";
          doCheck = false; # Tests run separately
        });

      # Clippy check
      packages.clippy = craneLib.cargoClippy (commonArgs
        // {
          inherit cargoArtifacts;
          cargoClippyExtraArgs = "--all-targets -- -D warnings";
        });

      # Tests
      packages.tests = craneLib.cargoTest (commonArgs
        // {
          inherit cargoArtifacts;
        });

      # Format check
      packages.fmt = craneLib.cargoFmt {
        inherit src;
      };

      # Checks for `nix flake check`
      checks = {
        inherit (self.packages.${system}) default clippy fmt tests;
      };

      # Development shell
      devShells.default = craneLib.devShell {
        checks = self.checks.${system};
        inputsFrom = [self.packages.${system}.default];
        packages = with pkgs; [
          cargo-watch
          cargo-audit
          cargo-fuzz
          rust-analyzer
        ];

        RUST_LOG = "debug";
      };
    });
}
