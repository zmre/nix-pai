# Nix Build Troubleshooting Guide

Systematic approaches to diagnosing and fixing common Nix build issues.

---

## 1. Build Failures

### Reading Error Messages

```bash
nix build --print-build-logs              # Verbose output
nix build --show-trace                    # Full stack trace
nix build --show-trace --print-build-logs # Both
```

### Viewing Build Logs

```bash
nix log /nix/store/abc123-package-1.0.drv  # Log for specific derivation
nix log .#myPackage                        # Log for flake output
```

### Debugging Build Phases

```bash
nix develop .#myPackage  # Enter shell at failure point
# Then manually run phases:
unpackPhase && cd $sourceRoot && patchPhase && configurePhase && buildPhase
```

---

## 2. Missing Libraries

### Diagnosing Missing Dynamic Libraries

```bash
ldd ./result/bin/myprogram | grep "not found"  # Linux
otool -L ./result/bin/myprogram                 # macOS
```

### Finding Library Sources

```bash
nix search nixpkgs libssl                # Search nixpkgs
nix-locate --top-level libssl.so         # File-level search (needs nix-index)
```

### Inspecting Store Path Dependencies

```bash
nix-store -q --references /nix/store/abc123-pkg  # Direct deps
nix-store -q --tree /nix/store/abc123-pkg        # Full tree
```

### Fix: Add Runtime Dependencies

```nix
stdenv.mkDerivation {
  buildInputs = [ openssl zlib ];
  postFixup = ''
    patchelf --set-rpath "${lib.makeLibraryPath [ openssl zlib ]}" $out/bin/prog
  '';
}
```

---

## 3. Evaluation Errors

### Debugging Evaluation

```bash
nix eval .#packages.x86_64-linux.default           # Evaluate expression
nix eval --show-trace .#devShells.x86_64-darwin.default  # With trace
nix eval --expr 'builtins.attrNames (import ./. {})'     # List attributes
```

### Common Evaluation Errors

- **"infinite recursion"** - Circular imports. Use `--show-trace` to locate.
- **"attribute 'foo' missing"** - Check typos, use `builtins.hasAttr`.
- **"unexpected argument"** - Function signature mismatch.

---

## 4. Dependency Conflicts

### Using nix why-depends

```bash
nix why-depends .#myPackage nixpkgs#openssl       # Why A depends on B
nix why-depends --all .#myPackage nixpkgs#glibc   # Full path
```

### Finding Duplicates

```bash
nix-store -qR ./result | grep -E "openssl|ssl" | sort
```

### Fixing Version Conflicts

```nix
myPackage.override { openssl = pkgs.openssl_1_1; }  # Override specific
nixpkgs.overlays = [ (final: prev: { openssl = prev.openssl_3_0; }) ];  # Pin global
```

---

## 5. Cache Issues

### Bypassing Cache

```bash
nix build --no-substitute  # Skip binary cache
nix build --rebuild        # Force rebuild
```

### Cache Debugging

```bash
nix path-info --sigs /nix/store/abc123-pkg                          # Check sigs
nix store ls --store https://cache.nixos.org /nix/store/abc123-pkg  # Query cache
```

### Fixing Signature Errors

```nix
nixConfig = {
  extra-trusted-public-keys = [ "mycache.cachix.org-1:KEYHERE" ];
};
```

---

## 6. IFD (Import From Derivation) Issues

IFD occurs when evaluation depends on build output, blocked in pure flakes.

```nix
# Bad: reads derivation output during eval
version = builtins.readFile (pkgs.writeText "v" "1.0");

# Good: use string directly
version = "1.0";
```

```bash
nix eval --impure .#myPackage  # Allow IFD temporarily
```

---

## 7. Common Error Messages

### "hash mismatch"

Update hash to the "got" value. Use `lib.fakeHash` during dev:
```nix
src = fetchurl { url = "..."; hash = lib.fakeHash; };
```

### "file not found" in build

Sandbox has no network. Declare sources as inputs:
```nix
cp ${fetchurl { url = "..."; hash = "..."; }} file.txt
```

### "permission denied"

```bash
nix build --option sandbox relaxed  # Debugging only
```

### "cannot build on darwin"

```nix
meta.platforms = lib.platforms.linux;
buildInputs = lib.optionals stdenv.isDarwin [ darwin.apple_sdk.frameworks.Security ];
```

### "derivation has no outputs"

Must create `$out`:
```nix
installPhase = ''
  mkdir -p $out/bin
  cp myprogram $out/bin/
'';
```

### "cannot coerce a set to a string"

```nix
"${pkgs}"        # Wrong: set
"${pkgs.hello}"  # Right: derivation coerces to path
```

---

## Quick Diagnostic Checklist

1. Read the **full** error message
2. Use `--show-trace` to find origin
3. Check build logs with `nix log`
4. Verify sources and hashes
5. Test components separately
6. Check darwin vs linux differences
7. Search Discourse/GitHub for error text

```bash
nix build --show-trace 2>&1 | head -100  # Quick diagnostic
```
