# GitHub Actions CI with Nix Caching

Optimize CI builds with Determinate Systems actions and Cachix binary caching.

---

## Core Actions Setup

```yaml
- uses: DeterminateSystems/nix-installer-action@v17
- uses: DeterminateSystems/magic-nix-cache-action@v9
- uses: cachix/cachix-action@v16
  with:
    name: your-cache-name
    authToken: ${{ secrets.CACHIX_AUTH_TOKEN }}
    extraPullNames: nix-community
```

- **magic-nix-cache**: Zero-config Nix store caching between runs
- **cachix-action**: Persistent team-wide binary caching

---

## Setting Up Cachix

1. Sign up at [cachix.org](https://cachix.org)
2. Create cache: Settings > Binary Caches > New
3. Generate auth token: Settings > API Tokens (push permissions)
4. Add to GitHub: Settings > Secrets > Actions > `CACHIX_AUTH_TOKEN`

### Add to flake.nix

```nix
{
  nixConfig = {
    extra-substituters = [
      "https://cache.nixos.org"
      "https://nix-community.cachix.org"
      "https://your-cache-name.cachix.org"
    ];
    extra-trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "your-cache-name.cachix.org-1:YOUR_PUBLIC_KEY_HERE="
    ];
  };
}
```

---

## Multi-Platform Workflow

```yaml
name: CI
on:
  push:
    branches: [main]
  pull_request:

jobs:
  build:
    strategy:
      matrix:
        os: [ubuntu-latest, macos-latest]
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@v4
      - uses: DeterminateSystems/nix-installer-action@v17
      - uses: DeterminateSystems/magic-nix-cache-action@v9
      - uses: cachix/cachix-action@v16
        with:
          name: your-cache-name
          authToken: ${{ secrets.CACHIX_AUTH_TOKEN }}
          extraPullNames: nix-community

      - run: nix flake check --accept-flake-config
      - run: nix build --accept-flake-config

      - name: Push to Cachix
        if: github.ref == 'refs/heads/main'
        run: |
          nix build --json | jq -r '.[].outputs | to_entries[].value' | \
            cachix push your-cache-name
```

---

## Job Dependency Graph

For large projects: format-check -> build-deps -> parallel (lint, test, build).

```yaml
jobs:
  format-check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: DeterminateSystems/nix-installer-action@v17
      - uses: DeterminateSystems/magic-nix-cache-action@v9
      - run: nix build .#fmt --accept-flake-config

  build-deps:
    needs: format-check
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: DeterminateSystems/nix-installer-action@v17
      - uses: DeterminateSystems/magic-nix-cache-action@v9
      - uses: cachix/cachix-action@v16
        with:
          name: your-cache-name
          authToken: ${{ secrets.CACHIX_AUTH_TOKEN }}
      - run: nix build .#cargoArtifacts --accept-flake-config
      - uses: actions/upload-artifact@v4
        with:
          name: cargo-artifacts
          path: result

  lint:
    needs: build-deps
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: DeterminateSystems/nix-installer-action@v17
      - uses: DeterminateSystems/magic-nix-cache-action@v9
      - uses: cachix/cachix-action@v16
        with:
          name: your-cache-name
      - run: nix build .#clippy --accept-flake-config

  test:
    needs: build-deps
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: DeterminateSystems/nix-installer-action@v17
      - uses: DeterminateSystems/magic-nix-cache-action@v9
      - uses: cachix/cachix-action@v16
        with:
          name: your-cache-name
      - run: nix build .#tests --accept-flake-config

  build:
    needs: build-deps
    strategy:
      matrix:
        os: [ubuntu-latest, macos-latest]
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@v4
      - uses: DeterminateSystems/nix-installer-action@v17
      - uses: DeterminateSystems/magic-nix-cache-action@v9
      - uses: cachix/cachix-action@v16
        with:
          name: your-cache-name
          authToken: ${{ secrets.CACHIX_AUTH_TOKEN }}
      - run: nix build --accept-flake-config
      - if: github.ref == 'refs/heads/main'
        run: nix build --json | jq -r '.[].outputs | to_entries[].value' | cachix push your-cache-name
```

---

## Key Patterns

| Pattern | Purpose |
|---------|---------|
| `nix flake check` | Runs all `checks` in flake (fmt, clippy, tests, build) |
| `--accept-flake-config` | Honor `nixConfig` substituters |
| `if: github.ref == 'refs/heads/main'` | Only push cache on main branch |
| `extraPullNames: nix-community` | Pull from community caches |
| `needs: build-deps` | Job dependency for parallel execution |

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Cache not used | Verify `extra-substituters` matches Cachix URL |
| Auth token errors | Check CACHIX_AUTH_TOKEN secret |
| Slow builds | Add `extraPullNames: nix-community` |
| macOS builds fail | Check Darwin-specific deps in flake |
