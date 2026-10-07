# laya (https://github.com/NandhaKishorM/laya): the `laya` CLI and the
# `laya-mcp-server` MCP stdio server.
#
# The laya library itself is built from upstream's own nix/package.nix, so it
# tracks the `laya` flake input and `nix flake update` picks up new releases
# with no hashes to maintain.
#
# Upstream's flake does not ship the `laya[mcp]` extra, which needs mcp>=2.2.0
# (nixpkgs only has 1.x). We build mcp + mcp-types 2.x privately from the
# `mcp-python-sdk` flake input, following numtide's prime-agent approach, and
# reuse nixpkgs' httpx2. The SDK input is pinned to a tag because the version
# string must be known without .git (uv-dynamic-versioning); to bump, change
# the tag in flake.nix and `mcpVersion` below together.
{
  lib,
  stdenv,
  python3,
  symlinkJoin,
  writeShellScriptBin,
  layaSrc,
  mcpSrc,
}: let
  mcpVersion = "2.2.0";

  python = python3.override (pythonArgs: {
    self = python;
    packageOverrides = lib.composeExtensions (pythonArgs.packageOverrides or (_: _: {})) (
      pyFinal: pyPrev: {
        mcp-types = pyFinal.buildPythonPackage {
          pname = "mcp-types";
          version = mcpVersion;
          src = "${mcpSrc}/src/mcp-types";
          pyproject = true;
          build-system = with pyFinal; [hatchling uv-dynamic-versioning];
          dependencies = with pyFinal; [pydantic typing-extensions];
          pythonImportsCheck = ["mcp_types"];
        };

        mcp = pyFinal.buildPythonPackage {
          pname = "mcp";
          version = mcpVersion;
          src = mcpSrc;
          pyproject = true;
          build-system = with pyFinal; [hatchling uv-dynamic-versioning];
          dependencies = with pyFinal;
            [
              anyio
              httpx2
              jsonschema
              mcp-types
              opentelemetry-api
              pydantic
              pyjwt
              python-multipart
              sse-starlette
              starlette
              typing-extensions
              typing-inspection
              uvicorn
            ]
            ++ pyFinal.pyjwt.optional-dependencies.crypto;
          # Test suite needs network/extra tooling; the import check is enough here.
          doCheck = false;
          pythonImportsCheck = ["mcp" "mcp.server.mcpserver"];
        };
      }
    );
  });

  # Upstream asks for torch-bin (unfree: bundles MKL/CUDA). Swap in the free,
  # Hydra-cached source build so consumers don't need allowUnfree.
  laya =
    (python.pkgs.callPackage "${layaSrc}/nix/package.nix" {
      python3 = python;
      python3Packages = python.pkgs // {torch-bin = python.pkgs.torch;};
    }).laya;

  pyEnv = python.withPackages (ps: [laya ps.mcp]);

  # -P: don't prepend cwd to sys.path, so a project checkout containing a
  # `laya/` dir can't shadow the packaged module.
  mcpServer = writeShellScriptBin "laya-mcp-server" ''
    exec ${pyEnv}/bin/python -P -m laya.mcp.server "$@"
  '';

  # On macOS default to CPU: for one-shot runs MPS init costs more than it
  # saves (~3.5s vs ~4s warm). An explicit --device wins.
  cli = writeShellScriptBin "laya" (''
      device=()
    ''
    + lib.optionalString stdenv.hostPlatform.isDarwin ''
      case " $* " in
        *" --device "* | *" --device="*) ;;
        *) device=(--device cpu) ;;
      esac
    ''
    + ''
      exec ${pyEnv}/bin/python -P -m laya.cli "''${device[@]}" "$@"
    '');
in
  symlinkJoin {
    name = "laya-${laya.version}";
    paths = [mcpServer cli];
    meta.mainProgram = "laya";
  }
