# TypeScript/Node.js Project Flakes

**Package Manager: Always use bun** (not npm/yarn/pnpm).

---

## Basic Dev Shell

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let pkgs = nixpkgs.legacyPackages.${system}; in {
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [ nodejs_22 bun typescript ];
          shellHook = ''export NODE_ENV=development'';
        };
      });
}
```

Run commands: `nix develop -c bun run build`

---

## buildNpmPackage (Distributable Packages)

Use when you need a packaged output, not just development.

```nix
packages.default = pkgs.buildNpmPackage {
  pname = "my-app";
  version = "1.0.0";
  src = ./.;
  npmDepsHash = "";  # Build first, Nix shows the hash

  nativeBuildInputs = with pkgs; [ nodejs_22 bun typescript ];

  buildPhase = ''
    export NODE_ENV=production
    bun run build
  '';

  installPhase = ''
    mkdir -p $out/lib
    cp -r dist/* $out/lib/
  '';
};
```

### Getting npmDepsHash

```bash
nix build 2>&1 | grep "got:"
# Copy the sha256-... hash into npmDepsHash
```

---

## When to Use Each

| Scenario | Use |
|----------|-----|
| Local development | Dev shell |
| CLI tool / distributable | buildNpmPackage |
| Part of larger Nix system | buildNpmPackage |

---

## Environment Variables

```nix
shellHook = ''
  export NODE_ENV=development
  export NODE_OPTIONS="--max-old-space-size=4096"
'';
```

---

## Native Dependencies

```nix
buildNpmPackage {
  nativeBuildInputs = with pkgs; [
    nodejs_22 bun python3 pkg-config  # python3 for node-gyp
  ];
  buildInputs = with pkgs; [
    vips   # for sharp
    sqlite # for better-sqlite3
  ];
}
```

---

## CLI with Wrapper

```nix
installPhase = ''
  mkdir -p $out/bin $out/lib
  cp -r dist/* $out/lib/
  makeWrapper ${pkgs.nodejs_22}/bin/node $out/bin/my-cli \
    --add-flags "$out/lib/index.js"
'';
```

Add `makeWrapper` to `nativeBuildInputs`.

---

## Common Issues

| Problem | Fix |
|---------|-----|
| Hash mismatch | Set `npmDepsHash = "";` and rebuild |
| Cannot find module | Ensure lockfile exists |
| bun.lockb issues | Generate package-lock.json or use fakeHash |
