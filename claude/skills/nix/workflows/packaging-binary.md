# Packaging Pre-Built Binaries in Nix

This workflow covers packaging binaries distributed as pre-compiled executables (not source code).

## Understanding the ELF Problem

Linux binaries hardcode paths like `/lib64/ld-linux-x86-64.so.2`. NixOS doesn't have these paths - everything is in `/nix/store`. The `autoPatchelfHook` automatically rewrites these paths.

---

## Archive Extraction Patterns

### Tarball (.tar.gz, .tar.xz, .tar.bz2)
Nix handles these automatically - no special extraction needed.

### Debian Package (.deb)
```nix
nativeBuildInputs = [ dpkg ];
unpackPhase = ''
  dpkg-deb -x $src .
'';
```

### RPM Package (.rpm)
```nix
nativeBuildInputs = [ rpm cpio ];
unpackPhase = ''
  rpm2cpio $src | cpio -idmv
'';
```

### Zip Archive (.zip)
```nix
nativeBuildInputs = [ unzip ];
# unpackPhase handles .zip automatically when unzip is in nativeBuildInputs
```

---

## Finding Missing Libraries

```bash
ldd ./binary-name | grep "not found"
```

### Quick Testing with steam-run
```bash
nix-shell -p steam-run
steam-run ./binary-name
```

---

## Library to Package Mapping

| Library | Nix Package |
|---------|-------------|
| `libc.so.6`, `libm.so.6`, `libpthread.so.0` | `glibc` (provided by stdenv) |
| `libstdc++.so.6`, `libgcc_s.so.1` | `stdenv.cc.cc.lib` |
| `libgtk-3.so.0` | `gtk3` |
| `libglib-2.0.so.0`, `libgio-2.0.so.0` | `glib` |
| `libX11.so.6` | `xorg.libX11` |
| `libXext.so.6` | `xorg.libXext` |
| `libxcb.so.1` | `xorg.libxcb` |
| `libcairo.so.2` | `cairo` |
| `libpango-1.0.so.0` | `pango` |
| `libfontconfig.so.1` | `fontconfig` |
| `libfreetype.so.6` | `freetype` |
| `libssl.so.3`, `libcrypto.so.3` | `openssl` |
| `libcurl.so.4` | `curl` |
| `libz.so.1` | `zlib` |
| `libasound.so.2` | `alsa-lib` |
| `libGL.so.1` | `libGL` |
| `libudev.so.1` | `systemd` (or `eudev`) |
| `libsecret-1.so.0` | `libsecret` |
| `libwebkit2gtk-4.0.so.37` | `webkitgtk` |

Find packages with: `nix-locate libname.so`

---

## nativeBuildInputs vs buildInputs (Critical!)

### nativeBuildInputs
Tools that run during **build** on the build machine:
```nix
nativeBuildInputs = [
  autoPatchelfHook  # patches binaries
  makeWrapper       # creates wrapper scripts
  dpkg              # extracts .deb files
];
```

### buildInputs
Libraries the **binary links against** at runtime:
```nix
buildInputs = [
  stdenv.cc.cc.lib  # libstdc++
  glib
  gtk3
];
```

**Why it matters**: `autoPatchelfHook` only searches `buildInputs` for libraries. Put extractors in `nativeBuildInputs`, libraries in `buildInputs`.

---

## Using autoPatchelfHook

```nix
{ stdenv, fetchurl, autoPatchelfHook, glib }:

stdenv.mkDerivation {
  pname = "my-binary";
  version = "1.0.0";
  src = fetchurl { ... };

  nativeBuildInputs = [ autoPatchelfHook ];
  buildInputs = [ stdenv.cc.cc.lib glib ];
  # autoPatchelfHook runs automatically in fixupPhase
}
```

It scans ELF binaries, finds required libs in `buildInputs`, and patches RPATH/interpreter.

---

## Using wrapProgram

For runtime environment (PATH, env vars, dlopen'd libs):

```nix
{ stdenv, makeWrapper, lib, coreutils, cacert, libGL }:

stdenv.mkDerivation {
  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    mkdir -p $out/bin
    cp binary $out/bin/
    wrapProgram $out/bin/binary \
      --prefix PATH : ${lib.makeBinPath [ coreutils ]} \
      --set SSL_CERT_FILE "${cacert}/etc/ssl/certs/ca-bundle.crt" \
      --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [ libGL ]}
  '';
}
```

| Flag | Purpose |
|------|---------|
| `--prefix VAR : value` | Prepend to variable |
| `--suffix VAR : value` | Append to variable |
| `--set VAR value` | Set/overwrite variable |

---

## Complete Example

```nix
{ lib, stdenv, fetchurl, autoPatchelfHook, makeWrapper, dpkg
, glib, gtk3, xorg, libsecret, nss, alsa-lib, mesa }:

stdenv.mkDerivation rec {
  pname = "example-tool";
  version = "2.5.0";

  src = fetchurl {
    url = "https://releases.example.com/${pname}-${version}-amd64.deb";
    sha256 = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
  };

  nativeBuildInputs = [ autoPatchelfHook makeWrapper dpkg ];

  buildInputs = [
    glib gtk3 xorg.libX11 xorg.libxcb
    libsecret nss alsa-lib mesa
  ];

  unpackPhase = ''
    dpkg-deb -x $src .
  '';

  dontBuild = true;
  dontConfigure = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    cp -r opt/${pname}/* $out/
    ln -s $out/${pname} $out/bin/${pname}
    wrapProgram $out/bin/${pname} \
      --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [ mesa ]}
    runHook postInstall
  '';

  meta = with lib; {
    description = "Example proprietary tool";
    license = licenses.unfree;
    platforms = [ "x86_64-linux" ];
  };
}
```

---

## Troubleshooting

### "cannot execute binary file"
Wrong architecture. Check: `file ./binary`

### "No such file or directory" (file exists)
Missing interpreter. Ensure `autoPatchelfHook` is in `nativeBuildInputs`.

### autoPatchelfHook can't find library
1. Verify library is in `buildInputs`
2. Check version (libssl.so.1.1 vs libssl.so.3)
3. Use `nix-locate libname.so` to find package

### Binary works in steam-run but not packaged
Some libraries are dlopen'd at runtime. Use `strace -e openat ./binary 2>&1 | grep "\.so"` to find them, then add via `wrapProgram --prefix LD_LIBRARY_PATH`.
