# Package from Source Workflow

## Trigger
User says: "package from source", "build from source", "package not in nixpkgs", "create derivation"

## Builder Selection

| Source Type | Builder |
|-------------|---------|
| Rust (Cargo.toml) | buildRustPackage |
| Python (pyproject.toml) | buildPythonPackage |
| Node.js (package.json) | buildNpmPackage |
| Go (go.mod) | buildGoModule |
| C/C++/other | stdenv.mkDerivation |

**Always prefer language-specific builders** - they handle deps and caching automatically.

---

## stdenv.mkDerivation Basics

```nix
{ stdenv, fetchFromGitHub, cmake, ninja }:

stdenv.mkDerivation rec {
  pname = "my-package";
  version = "1.2.3";

  src = fetchFromGitHub {
    owner = "example"; repo = "my-package";
    rev = "v${version}";
    hash = "";  # Build first, Nix tells you the hash
  };

  nativeBuildInputs = [ cmake ninja ];  # Build-time tools
  buildInputs = [ ];                     # Libraries to link
  meta.description = "Package description";
}
```

---

## Source Fetching

### Preferred: Flake Inputs (no hardcoded hashes)
```nix
inputs.my-source = { url = "github:owner/repo"; flake = false; };
# Then use: src = my-source; (hash managed by flake.lock)
```

### Fallback: Fetchers
```nix
src = fetchFromGitHub { owner = "x"; repo = "y"; rev = "v${version}"; hash = ""; };
src = fetchurl { url = "https://example.com/v${version}.tar.gz"; hash = ""; };
```

---

## Build Phases

| Phase | Default |
|-------|---------|
| unpackPhase | Extract tar/zip |
| patchPhase | Apply `patches` list |
| configurePhase | Run `./configure` or cmake |
| buildPhase | Run `make` |
| installPhase | Run `make install` |

Override when needed:
```nix
configurePhase = "true";  # Skip
installPhase = ''
  runHook preInstall
  mkdir -p $out/bin && cp prog $out/bin/
  runHook postInstall
'';
```

---

## Build Systems

| System | nativeBuildInputs | Flags Attr |
|--------|-------------------|------------|
| CMake | `cmake ninja` | `cmakeFlags` |
| Autotools | `autoreconfHook pkg-config` | `configureFlags` |
| Meson | `meson ninja pkg-config` | `mesonFlags` |

---

## Patching Sources

```nix
patches = [ ./fix-build.patch ];

postPatch = ''
  substituteInPlace Makefile --replace "/usr/local" "$out"
'';
```

---

## nativeBuildInputs vs buildInputs

- **nativeBuildInputs**: Build-time tools (cmake, pkg-config, gcc)
- **buildInputs**: Linked libraries (openssl, zlib, sqlite)

---

## Language-Specific Examples

```nix
# Rust
rustPlatform.buildRustPackage {
  pname = "app"; version = "1.0"; cargoHash = "";
  src = fetchFromGitHub { /* ... */ };
  buildInputs = [ openssl ];
}

# Python
python3Packages.buildPythonPackage {
  pname = "pkg"; version = "1.0";
  src = fetchPypi { inherit pname version; hash = ""; };
  propagatedBuildInputs = with python3Packages; [ requests ];
}

# Node.js
buildNpmPackage { pname = "app"; version = "1.0"; npmDepsHash = ""; src = ./.; }
```

---

## Creating Overlays

```nix
overlays.default = final: prev: {
  my-pkg = final.callPackage ./pkgs/my-pkg.nix { };
};
# Use: import nixpkgs { overlays = [ self.overlays.default ]; }
```

---

## Debugging

```bash
nix build --print-build-logs  # Verbose output
nix develop -c bash           # Enter build env interactively
```
