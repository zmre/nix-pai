# Common Nix Patterns

Quick reference for frequently used Nix patterns.

---

## The `follows` Pattern

Prevent duplicate nixpkgs instances by making inputs follow your nixpkgs:

```nix
inputs = {
  nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  some-flake = {
    url = "github:example/some-flake";
    inputs.nixpkgs.follows = "nixpkgs";  # Use our nixpkgs
  };

  another-flake = {
    url = "github:example/another";
    inputs.nixpkgs.follows = "nixpkgs";
    inputs.flake-utils.follows = "flake-utils";  # Chain follows
  };
};
```

**Why?** Without `follows`, each input brings its own nixpkgs, causing:
- Slower evaluation
- Larger closures
- Potential version conflicts

---

## Overlay Composition

Combine multiple overlays in order:

```nix
let
  pkgs = import nixpkgs {
    inherit system;
    overlays = [
      rust-overlay.overlays.default
      (final: prev: {
        # Your custom overlay
        myTool = prev.callPackage ./my-tool.nix {};
      })
    ];
  };
in ...
```

With `lib.composeManyExtensions`:
```nix
pythonSet.overrideScope (
  lib.composeManyExtensions [
    overlay1
    overlay2
    (final: prev: { /* custom */ })
  ]
)
```

---

## Platform Conditionals

### `lib.optionals` for Lists

```nix
buildInputs = with pkgs; [
  common-dep
] ++ lib.optionals stdenv.isDarwin [
  darwin.apple_sdk.frameworks.Security
  libiconv
] ++ lib.optionals stdenv.isLinux [
  gtk3
  webkitgtk
];
```

### `lib.optionalAttrs` for Attribute Sets

```nix
packages = {
  default = myPackage;
} // lib.optionalAttrs pkgs.stdenv.isDarwin {
  macApp = macOSAppBundle;
};
```

### `lib.optionalString` for Strings

```nix
BINDGEN_EXTRA_CLANG_ARGS = lib.optionalString stdenv.isLinux
  "-isystem ${stdenv.cc.libc.dev}/include";
```

---

## makeWrapper / wrapProgram

Inject runtime dependencies into executables:

```nix
{ lib, stdenv, makeWrapper, myApp, runtimeDeps }:

stdenv.mkDerivation {
  pname = "my-wrapped-app";
  # ...

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    mkdir -p $out/bin
    cp ${myApp}/bin/app $out/bin/

    wrapProgram $out/bin/app \
      --prefix PATH : ${lib.makeBinPath runtimeDeps} \
      --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [ somLib ]} \
      --set MY_ENV_VAR "value" \
      --add-flags "--default-flag"
  '';
}
```

Common wrapProgram flags:
- `--prefix VAR : value` - Prepend to variable
- `--suffix VAR : value` - Append to variable
- `--set VAR value` - Set variable
- `--unset VAR` - Remove variable
- `--add-flags "..."` - Add default arguments

---

## substituteAll / substituteInPlace

Replace placeholders in files:

```nix
# substituteAll - creates new file with substitutions
configFile = substituteAll {
  src = ./config.template;
  inherit version;
  binPath = "${myBin}/bin";
};

# substituteInPlace - modifies file in place (in phases)
postPatch = ''
  substituteInPlace src/config.py \
    --replace-fail '/usr/bin/tool' '${tool}/bin/tool' \
    --replace-fail '@VERSION@' '${version}'
'';
```

---

## Reading Files at Eval Time

```nix
# Read and parse TOML
cargoToml = builtins.fromTOML (builtins.readFile ./Cargo.toml);
version = cargoToml.package.version;

# Read and parse JSON
packageJson = builtins.fromJSON (builtins.readFile ./package.json);

# Check if file exists
hasLockfile = builtins.pathExists ./Cargo.lock;
```

---

## Source Filtering

Filter source to avoid unnecessary rebuilds:

```nix
# With crane (for Rust)
src = pkgs.lib.cleanSourceWith {
  src = ./.;
  filter = path: type:
    (craneLib.filterCargoSources path type)
    || (builtins.match ".*\\.md$" path != null)
    || (builtins.match ".*assets.*" path != null);
};

# With lib.fileset (general purpose)
src = lib.fileset.toSource {
  root = ./.;
  fileset = lib.fileset.unions [
    ./src
    ./Cargo.toml
    ./Cargo.lock
  ];
};

# Simple cleanSource (removes .git, etc.)
src = lib.cleanSource ./.;
```

---

## writeShellApplication

Create a shell script as a package:

```nix
packages.my-script = pkgs.writeShellApplication {
  name = "my-script";
  runtimeInputs = [ pkgs.jq pkgs.curl ];
  text = ''
    # Script content here
    # runtimeInputs are automatically in PATH
    curl -s "$1" | jq '.data'
  '';
};
```

Benefits over `writeShellScriptBin`:
- Automatic shellcheck
- `set -euo pipefail` by default
- Runtime inputs in PATH

---

## runCommand / runCommandLocal

Quick derivations for simple tasks:

```nix
# runCommand - may use substitutes
checksums = pkgs.runCommand "checksums" {} ''
  mkdir -p $out
  cd ${myPackage}
  sha256sum bin/* > $out/SHA256SUMS
'';

# runCommandLocal - always builds locally
localTest = pkgs.runCommandLocal "test" {
  nativeBuildInputs = [ pkgs.myTool ];
} ''
  myTool check ${src}
  touch $out
'';
```
