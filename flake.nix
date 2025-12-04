{
  description = "Template Module for Personal AI Assistant (PAI) - An advanced AI-powered development environment using Claude Code";

  nixConfig = {
    allowUnfree = true;
    extra-substituters = ["https://numtide.cachix.org"];
    extra-trusted-public-keys = ["numtide.cachix.org-1:2ps1kLBUWjxIneOy1Ik6cQjb41X0iXVXeHigGmycPPE="];
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    # for some things not available in nixpkgs, but also it stays up-to-date more
    nix-ai-tools.url = "github:numtide/nix-ai-tools";
    fabric.url = "github:danielmiessler/fabric";
    fabric.flake = false;
  };

  outputs = inputs @ {flake-parts, ...}:
    flake-parts.lib.mkFlake {inherit inputs;} ({...}: let
      paiModule = ./modules/pai.nix;
    in {
      systems = ["x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin"];

      #debug = true;

      imports = [
        flake-parts.flakeModules.flakeModules
        ./modules/pai.nix
      ];

      flake.flakeModules.default = paiModule;

      # TODO: provide optional default config so it can be tested without
      # customizing and building another flake first
      perSystem = {config, ...}: {
        # imports = [./modules/options.nix];
        packages.default = config.packages.pai;
        apps.default = {
          type = "app";
          program = "${config.packages.pai}/bin/${config.pai.commandName}";
          meta = {
            description = "Personal AI Infrastructure (PAI) - Default ${config.pai.assistantName}";
          };
        };
        apps.priv = {
          type = "app";
          program = "${config.packages.pai}/bin/${config.pai.commandName}-priv";
          meta = {
            description = "Personal AI Infrastructure (PAI) - Private/Local ${config.pai.assistantName} using OpenCode";
          };
        };
      };
    });
}
