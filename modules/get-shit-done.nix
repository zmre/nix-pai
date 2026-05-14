{
  lib,
  buildNpmPackage,
  fetchNpmDeps,
  nodejs_22,
  makeWrapper,
  src,
  version ? "unstable",
}: let
  nodejs = nodejs_22;

  # The published package contains a sub-package at ./sdk that has its own
  # package-lock.json. buildNpmPackage only handles a single lockfile, so we
  # fetch the sdk's deps separately and feed them in as an offline npm cache.
  sdkDeps = fetchNpmDeps {
    name = "get-shit-done-sdk-deps";
    src = "${src}/sdk";
    hash = "sha256-J1q7AnLMYRoKFgijBopRwaRU5gHhzXp64UDR8feGd8Y=";
  };
in
  buildNpmPackage {
    pname = "get-shit-done-cc";
    inherit version src nodejs;

    npmDepsHash = "sha256-aJYBiY33C9puffkRFIwFDmL35V1oKZ4HmVJ9Hb9Tfgs=";

    nativeBuildInputs = [makeWrapper];

    # The root package.json has no `build` script. Drive the build manually so
    # we can run both `build:hooks` (in the root) and the sdk TypeScript build.
    dontNpmBuild = true;

    # Some hooks/scripts shell out to `git describe` for diagnostic output;
    # tolerate the absence of git history in the Nix sandbox.
    GIT_DIR = "/dev/null";

    preBuild = ''
      echo "[get-shit-done] building hooks (file copy only)"
      npm run build:hooks --ignore-scripts

      echo "[get-shit-done] building sdk (typescript)"
      pushd sdk >/dev/null
        # fetchNpmDeps gives us a read-only cacache directory in the Nix store;
        # npm needs a writable cache, so copy it into $TMPDIR first.
        cp -r --no-preserve=mode,ownership "${sdkDeps}" "$TMPDIR/sdk-npm-cache"
        npm_config_cache="$TMPDIR/sdk-npm-cache" \
        npm_config_offline=true \
        npm_config_audit=false \
        npm_config_fund=false \
          npm ci --ignore-scripts --include=dev
        # Fix shebangs for Nix sandbox (#!/usr/bin/env node → /nix/store/.../node)
        # Must patch all of node_modules since .bin/ contains symlinks
        patchShebangs node_modules
        npm run build
        # Drop devDeps now that compilation is done. Cuts ~30MB of typescript +
        # vitest from the closure that ships in /nix/store.
        npm prune --omit=dev
      popd >/dev/null
    '';

    # buildNpmPackage's installPhase copies the package directory into
    # $out/lib/node_modules/<pname> and links each package.json `bin` entry into
    # $out/bin. The shebangs are `#!/usr/bin/env node`, so wrap them to ensure
    # `node` is reachable without polluting the user's global PATH.
    postFixup = ''
      for bin in get-shit-done-cc gsd-sdk gsd-tools; do
        if [ -e "$out/bin/$bin" ]; then
          wrapProgram "$out/bin/$bin" \
            --prefix PATH : "${lib.makeBinPath [nodejs]}"
        fi
      done
    '';

    meta = with lib; {
      description = "Meta-prompting and context engineering for Claude Code, OpenCode, Gemini, and Codex";
      homepage = "https://github.com/gsd-build/get-shit-done";
      license = licenses.mit;
      mainProgram = "gsd-sdk";
      platforms = platforms.unix;
    };
  }
