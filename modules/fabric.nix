{
  pkgs,
  lib,
  secretLookup,
  perSystemConfig,
}: let
  # Fabric API keys that need secret lookup
  fabricSecrets = {
    ANTHROPIC_API_KEY = "anthropickey";
    OPENAI_API_KEY = "openaikey";
    GEMINI_API_KEY = "geminikey";
  };

  # Fabric static configuration via environment variables
  fabricEnvVars = {
    # Default vendor and model
    DEFAULT_VENDOR = "Anthropic";
    DEFAULT_MODEL = "claude-sonnet-4-5-20250929";

    # Patterns configuration - point to nix store
    CUSTOM_PATTERNS_DIRECTORY = "${pkgs.fabric-ai.src}/data/patterns";
    PATTERNS_LOADER_GIT_REPO_URL = "https://github.com/danielmiessler/fabric.git";
    PATTERNS_LOADER_GIT_REPO_PATTERNS_FOLDER = "patterns";

    # Ollama configuration (for local models)
    OLLAMA_HOST = perSystemConfig.pai.ollamaServer;
    OLLAMA_API_URL = "${perSystemConfig.pai.ollamaServer}";
  };

  buildInputs = [pkgs.fabric-ai pkgs.yt-dlp] ++ pkgs.lib.optionals pkgs.stdenv.isLinux [pkgs.libsecret];

  # Build wrapped fabric executable
  mkFabricWrapper = pkgs.stdenvNoCC.mkDerivation {
    name = "fabric-wrapped";
    pname = "fabric-wrapped";

    # We need yt-dlp for fetching transcripts
    buildInputs = buildInputs;
    nativeBuildInputs = [pkgs.makeWrapper];

    dontUnpack = true;
    dontBuild = true;

    installPhase = ''
      mkdir -p $out/bin

      makeWrapper ${pkgs.fabric-ai}/bin/fabric $out/bin/fabric \
        --run 'mkdir -p ~/.config/fabric' \
        --run 'touch ~/.config/fabric/.env' \
        --prefix PATH : ${pkgs.lib.makeBinPath buildInputs} \
        ${lib.concatStringsSep " \\\n        " (
        lib.mapAttrsToList (key: value: "--run 'export ${key}=\${${key}:=\"${secretLookup value}\"}'") fabricSecrets
      )} \
        ${lib.concatStringsSep " \\\n        " (
        lib.mapAttrsToList (key: value: "--set-default ${key} '${value}'") fabricEnvVars
      )}
    '';

    meta = {
      description = "Wrapped fabric CLI with nix-pai configuration";
      mainProgram = "fabric";
    };
  };
in {
  package = mkFabricWrapper;
}
