{
  description = "Template Module for Personal AI Assistant (PAI) - An advanced AI-powered development environment using Claude Code";

  nixConfig = {
    allowUnfree = true;
    extra-substituters = [
      "https://cache.nixos.org"
      "https://nix-community.cachix.org"
      "https://zmre.cachix.org"
      "https://cache.numtide.com"
    ];
    extra-trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "zmre.cachix.org-1:WIE1U2a16UyaUVr+Wind0JM6pEXBe43PQezdPKoDWLE="
      "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
    ];
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    # for some things not available in nixpkgs, but also it stays up-to-date more
    llm-agents.url = "github:numtide/llm-agents.nix";
    # do not have llm-agents follow nixpkgs
    # fabric patterns source
    fabric = {
      url = "github:danielmiessler/fabric";
      flake = false;
    };
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
        apps.sandbox-yolo = {
          type = "app";
          program = "${config.packages.pai}/bin/${config.pai.commandName}-sandbox-yolo";
          meta = {
            description = "Personal AI Infrastructure (PAI) - Sandboxed YOLO mode for ${config.pai.assistantName}";
          };
        };
      };
    });
}
