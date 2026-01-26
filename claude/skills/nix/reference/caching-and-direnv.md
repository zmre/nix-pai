# Caching and Direnv Setup

Configure binary caching and automatic shell activation.

---

## Direnv Integration

### Basic Setup

1. Install direnv (should be in your system config)

2. Create `.envrc` in project root:
   ```bash
   use flake . --accept-flake-config
   ```

3. Allow the directory:
   ```bash
   direnv allow
   ```

### With Unfree Packages

If using unfree packages without `nixpkgs-unfree`:
```bash
export NIXPKGS_ALLOW_UNFREE=1
use flake . --accept-flake-config --impure
```

### Recommended `.envrc` Template

```bash
# Load flake dev shell with auto-accepted config
use flake . --accept-flake-config

# Optional: Project-specific environment
# export PROJECT_ENV="development"

# Optional: Override PATH additions
# PATH_add ./scripts
```

---

## nixConfig Block

Add cache configuration directly in flake.nix:

```nix
{
  nixConfig = {
    extra-substituters = [
      "https://cache.nixos.org"
      "https://nix-community.cachix.org"
      "https://your-cache.cachix.org"
    ];
    extra-trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "your-cache.cachix.org-1:YourPublicKeyHere="
    ];
  };

  # ... rest of flake
}
```

### Accepting nixConfig

Users must accept flake config for substituters to work:

| Method | Usage |
|--------|-------|
| Direnv | `use flake . --accept-flake-config` in `.envrc` |
| Manual CLI | `nix develop --accept-flake-config` |
| Environment | `NIX_CONFIG="accept-flake-config = true"` |
| System config | `nix.settings.accept-flake-config = true` |

---

## Cachix Setup

### Create a Cache

1. Sign up at [cachix.org](https://cachix.org)
2. Create a new binary cache
3. Note your cache name and get auth token

### Get Your Public Key

```bash
cachix use your-cache-name
# This prints the public key to add to nixConfig
```

### Push Builds to Cache

```bash
# Build and push
nix build --json | jq -r '.[].outputs | to_entries[].value' | cachix push your-cache

# Or build with automatic pushing
cachix watch-exec your-cache -- nix build
```

### Generate Auth Token

1. Go to cachix.org → Settings → Auth Tokens
2. Create token with write access
3. For CI: Add as `CACHIX_AUTH_TOKEN` secret

---

## GitHub Actions Integration

### Basic CI Cache Setup

```yaml
- uses: DeterminateSystems/nix-installer-action@v17
- uses: DeterminateSystems/magic-nix-cache-action@v9
```

`magic-nix-cache-action` provides free CI caching without Cachix.

### With Cachix (Persistent Cache)

```yaml
- uses: DeterminateSystems/nix-installer-action@v17
- uses: DeterminateSystems/magic-nix-cache-action@v9
- uses: cachix/cachix-action@v16
  with:
    name: your-cache-name
    authToken: ${{ secrets.CACHIX_AUTH_TOKEN }}
    extraPullNames: nix-community
```

### Push After Successful Build

```yaml
- name: Build
  run: nix build

- name: Push to Cachix
  if: github.event_name == 'push' && github.ref == 'refs/heads/main'
  run: |
    nix build --json | jq -r '.[].outputs | to_entries[].value' | cachix push your-cache
```

---

## System-Level Cache Configuration

### NixOS / nix-darwin

```nix
nix.settings = {
  substituters = [
    "https://cache.nixos.org"
    "https://nix-community.cachix.org"
    "https://your-cache.cachix.org"
  ];
  trusted-public-keys = [
    "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
    "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    "your-cache.cachix.org-1:..."
  ];

  # Auto-accept flake configs
  accept-flake-config = true;
};
```

### home-manager

```nix
nix = {
  settings = {
    substituters = [ ... ];
    trusted-public-keys = [ ... ];
  };
};
```

---

## Debugging Cache Issues

### Check if Cache is Being Used

```bash
# See where packages come from
nix build --print-build-logs -v 2>&1 | grep -E "(copying|building)"

# Force no cache (rebuild from source)
nix build --no-substitute
```

### Verify Cache Signature

```bash
# Check if you can fetch from cache
curl -sI https://your-cache.cachix.org/nix-cache-info
```

### Common Issues

| Issue | Solution |
|-------|----------|
| "signature not trusted" | Add public key to `trusted-public-keys` |
| "cannot connect" | Check network, verify cache URL |
| "hash mismatch" | Cache is stale, push fresh build |
| Config not accepted | Use `--accept-flake-config` or system setting |

---

## Cache Priority

Substituters are tried in order. Put faster/local caches first:

```nix
extra-substituters = [
  "https://your-cache.cachix.org"     # Your cache (likely has your packages)
  "https://nix-community.cachix.org"  # Community packages
  "https://cache.nixos.org"           # Official (fallback)
];
```
