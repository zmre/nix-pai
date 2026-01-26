# Nix Gotchas

Common pitfalls and how to avoid them.

---

## `config.allowUnfree` Doesn't Work with `nix develop`

**Problem:** Setting `config.allowUnfree = true` in flake.nix doesn't allow unfree packages in dev shells.

```nix
# This does NOT work for nix develop
pkgs = import nixpkgs {
  inherit system;
  config.allowUnfree = true;  # Ignored by nix develop!
};
```

**Solution:** Use `numtide/nixpkgs-unfree` input:

```nix
inputs.nixpkgs-unfree = {
  url = "github:numtide/nixpkgs-unfree";
  inputs.nixpkgs.follows = "nixpkgs";
};

# Use nixpkgs-unfree.legacyPackages for unfree packages
```

Or for quick testing: `NIXPKGS_ALLOW_UNFREE=1 nix develop --impure`

---

## Files Must Be Git-Tracked for Flakes

**Problem:** Flakes can only access files tracked by Git. New files are invisible.

```bash
# This fails if newfile.nix isn't git tracked
nix build  # error: path '/path/to/newfile.nix' is not in the Git repository
```

**Solutions:**

1. Add files to Git (even unstaged):
   ```bash
   git add newfile.nix  # Staged or unstaged, just tracked
   ```

2. Use `path:` prefix to bypass (includes all files):
   ```bash
   nix build path:.
   nix develop path:.
   ```

---

## `nativeBuildInputs` vs `buildInputs`

**Problem:** Putting runtime libraries in `nativeBuildInputs` or build tools in `buildInputs` causes failures.

| Attribute | Purpose | Examples |
|-----------|---------|----------|
| `nativeBuildInputs` | Build-time tools (run on build machine) | `pkg-config`, `cmake`, `autoPatchelfHook`, `makeWrapper` |
| `buildInputs` | Runtime libraries (linked into binary) | `openssl`, `gtk3`, `zlib`, `ffmpeg` |

**Cross-compilation matters:** In cross-compilation, `nativeBuildInputs` run on the build host, `buildInputs` are for the target.

```nix
mkDerivation {
  nativeBuildInputs = [ pkg-config cmake ];  # Build tools
  buildInputs = [ openssl zlib ];            # Libraries to link
}
```

---

## IFD (Import From Derivation)

**Problem:** IFD blocks evaluation until a build completes, breaking lazy evaluation.

```nix
# This is IFD - evaluating requires building the derivation first
version = builtins.readFile (pkgs.runCommand "version" {} ''
  echo "1.0.0" > $out
'');
```

**Why it's bad:**
- Breaks `nix flake check` in some cases
- Slows evaluation significantly
- Can't be evaluated without a builder

**Solutions:**
- Read version from source files: `builtins.fromTOML (builtins.readFile ./Cargo.toml)`
- Pass version as a flake input or argument
- Accept the IFD if truly necessary (some tools require it)

---

## Forgetting `strictDeps`

**Problem:** Without `strictDeps`, dependencies leak between build phases.

```nix
mkDerivation {
  strictDeps = true;  # Always set this!
  nativeBuildInputs = [ buildTool ];
  buildInputs = [ runtimeLib ];
}
```

**What `strictDeps` does:**
- Separates `PATH` for native vs host dependencies
- Required for correct cross-compilation
- Catches dependency misconfigurations

---

## Wrong Archive Extraction

**Problem:** Using wrong extraction command causes silent failures.

| Format | Correct nativeBuildInputs | Correct unpackPhase |
|--------|---------------------------|---------------------|
| `.deb` | `dpkg` | `ar x $src && tar xf data.tar.*` |
| `.rpm` | `rpm`, `cpio` | `rpm2cpio $src \| cpio -idmv` |
| `.tar.gz` | (none) | Automatic |
| `.zip` | `unzip` | `unzip $src` |

---

## Missing `inherit` in Let Bindings

**Problem:** Forgetting to inherit variables into nested scopes.

```nix
# Wrong - system not in scope
outputs = { nixpkgs, ... }:
  let
    pkgs = nixpkgs.legacyPackages.${system};  # Error: system undefined
  in ...

# Correct
outputs = { nixpkgs, ... }:
  flake-utils.lib.eachDefaultSystem (system:
    let
      pkgs = nixpkgs.legacyPackages.${system};  # system is in scope
    in ...
  );
```

---

## Cached Evaluation with Changed Inputs

**Problem:** Nix caches evaluation but flake inputs changed.

```bash
# Force re-evaluation
nix flake update
nix build --rebuild

# Or clear evaluation cache
rm -rf ~/.cache/nix/
```

---

## `nix develop` Shell Doesn't Have Package

**Problem:** Package is in `buildInputs` but not available in shell.

**Cause:** `mkShell` uses `buildInputs` for the shell environment, but some packages need to be in `packages` or `nativeBuildInputs`.

```nix
devShells.default = pkgs.mkShell {
  # These are available in the shell
  packages = [ pkgs.ripgrep ];  # or nativeBuildInputs

  # These provide libraries but may not add to PATH
  buildInputs = [ pkgs.openssl ];
};
```

---

## Flake Outputs Not Visible

**Problem:** `nix flake show` doesn't show your outputs.

**Common causes:**
1. Syntax error in flake.nix (check with `nix flake check`)
2. Output attribute is `null` due to failed conditional
3. Platform-specific output not available on current system

```bash
# Debug
nix flake check
nix eval .#packages --apply builtins.attrNames
```

---

## Shell Hook Not Running

**Problem:** `shellHook` in `mkShell` doesn't execute.

**Causes:**
1. Using `nix develop -c cmd` (runs command directly, no shell)
2. Shell hook has syntax error

```nix
devShells.default = pkgs.mkShell {
  shellHook = ''
    # Must be valid bash
    echo "Shell loaded"
    export MY_VAR="value"
  '';
};
```

Test interactively: `nix develop` (not `nix develop -c ...`)
