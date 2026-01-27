# Dependency Audit Workflow

This workflow covers language-specific dependency vulnerability scanning.

## Language Detection

### Automatic Detection Script

```bash
#!/bin/bash
# Detect project type and run appropriate audit

if [ -f "Cargo.toml" ]; then
    echo "=== Rust Project Detected ==="
    nix shell nixpkgs#cargo-audit -c cargo audit
fi

if [ -f "package.json" ]; then
    echo "=== JavaScript/TypeScript Project Detected ==="
    if [ -f "bun.lockb" ]; then
        echo "Using Bun..."
        nix shell nixpkgs#bun -c bun audit
    elif [ -f "package-lock.json" ]; then
        echo "Using npm..."
        nix shell nixpkgs#nodejs -c npm audit
    elif [ -f "yarn.lock" ]; then
        echo "Using yarn..."
        nix shell nixpkgs#yarn -c yarn audit
    else
        echo "No lockfile found, running npm audit..."
        nix shell nixpkgs#nodejs -c npm audit
    fi
fi

if [ -f "pyproject.toml" ] || [ -f "requirements.txt" ]; then
    echo "=== Python Project Detected ==="
    nix shell nixpkgs#python3Packages.pip-audit -c pip-audit
fi

if [ -f "go.mod" ]; then
    echo "=== Go Project Detected ==="
    nix shell nixpkgs#go -c go list -json -m all | \
        nix shell nixpkgs#nancy -c nancy sleuth
fi
```

---

## Rust Dependencies

### Primary Audit

```bash
nix shell nixpkgs#cargo-audit -c cargo audit
```

### Output Interpretation

**Example output:**
```
Crate:     smallvec
Version:   0.6.13
Title:     Buffer overflow in SmallVec::insert_many
Date:      2021-01-08
ID:        RUSTSEC-2021-0003
URL:       https://rustsec.org/advisories/RUSTSEC-2021-0003
Severity:  high
Solution:  upgrade to >=1.6.1
```

**Actions:**
1. Check if vulnerable code path is used in your project
2. Update dependency: `cargo update -p smallvec`
3. If breaking changes, pin to patched version in `Cargo.toml`

### Additional Rust Tools

```bash
# Check for outdated dependencies
nix shell nixpkgs#cargo-outdated -c cargo outdated

# View dependency tree
cargo tree

# Find duplicate dependencies
cargo tree --duplicates

# Check for yanked crates
nix shell nixpkgs#cargo-deny -c cargo deny check
```

### Cargo.toml Security Patterns

```toml
# Pin exact versions for security-critical deps
[dependencies]
ring = "=0.17.7"
rustls = "=0.22.2"

# Use version requirements that accept patches
openssl = "^0.10.60"  # Accepts 0.10.60, 0.10.61, etc.
```

---

## JavaScript/TypeScript Dependencies

### npm Audit

```bash
# Basic audit
nix shell nixpkgs#nodejs -c npm audit

# JSON output for parsing
nix shell nixpkgs#nodejs -c npm audit --json > npm-audit.json

# Fix automatically (use with caution)
nix shell nixpkgs#nodejs -c npm audit fix

# Force fix (may break things)
nix shell nixpkgs#nodejs -c npm audit fix --force
```

### Bun Audit

```bash
nix shell nixpkgs#bun -c bun audit
```

### Output Interpretation

**Example output:**
```
# npm audit report

lodash  <4.17.21
Severity: high
Prototype Pollution - https://github.com/advisories/GHSA-p6mc-m468-83gw
fix available via `npm audit fix`
node_modules/lodash

3 vulnerabilities (1 low, 1 moderate, 1 high)
```

**Severity Levels:**
- **Critical**: Immediate action required
- **High**: Fix within 24-48 hours
- **Moderate**: Fix within 1-2 weeks
- **Low**: Fix in next release

### Additional npm Tools

```bash
# Check for outdated packages
nix shell nixpkgs#nodejs -c npm outdated

# View dependency tree
nix shell nixpkgs#nodejs -c npm ls --all

# Better audit with more details
nix shell nixpkgs#nodejs -c npx better-npm-audit audit
```

### package.json Security Patterns

```json
{
  "dependencies": {
    "lodash": "^4.17.21"
  },
  "overrides": {
    "vulnerable-dep": "^2.0.0"
  },
  "resolutions": {
    "**/**/vulnerable-transitive-dep": "^1.2.3"
  }
}
```

---

## Python Dependencies

### pip-audit

```bash
# Basic audit
nix shell nixpkgs#python3Packages.pip-audit -c pip-audit

# From requirements file
nix shell nixpkgs#python3Packages.pip-audit -c pip-audit -r requirements.txt

# JSON output
nix shell nixpkgs#python3Packages.pip-audit -c pip-audit -f json > pip-audit.json

# Fix vulnerabilities
nix shell nixpkgs#python3Packages.pip-audit -c pip-audit --fix
```

### Safety Check (Alternative)

```bash
nix shell nixpkgs#safety -c safety check
nix shell nixpkgs#safety -c safety check -r requirements.txt
```

### Output Interpretation

**Example output:**
```
Name       Version  ID             Fix Versions
---------- -------- -------------- ------------
requests   2.25.0   PYSEC-2021-59  >=2.25.1
pyyaml     5.3.1    PYSEC-2021-142 >=5.4
```

**Actions:**
1. Update in `pyproject.toml` or `requirements.txt`
2. Run `pip install -U package_name`
3. Verify tests pass with updated version

### Python Security Patterns

```toml
# pyproject.toml - pin security-critical deps
[project]
dependencies = [
    "cryptography>=41.0.0",
    "pyjwt>=2.8.0",
]

# Exclude known vulnerable versions
[tool.pip-audit]
exclude = ["package==1.2.3"]  # If accepted risk
```

---

## Go Dependencies

### Nancy (for Go)

```bash
# Scan go.sum
nix shell nixpkgs#nancy -c nancy sleuth < go.sum

# Or with go list
nix shell nixpkgs#go -c go list -json -m all | \
    nix shell nixpkgs#nancy -c nancy sleuth
```

### govulncheck

```bash
nix shell nixpkgs#govulncheck -c govulncheck ./...
```

### Output Interpretation

```
Vulnerability #1: GO-2023-1571
  A malicious HTTP redirect can cause ParseThrough to panic.
  More info: https://pkg.go.dev/vuln/GO-2023-1571
  Module: golang.org/x/net
    Found in: golang.org/x/net@v0.5.0
    Fixed in: golang.org/x/net@v0.7.0
```

---

## Handling Vulnerabilities

### Decision Framework

For each vulnerability:

1. **Is the vulnerable code path used?**
   - Check if you call the affected function
   - Review the advisory for exploitation requirements

2. **Is there a fix available?**
   - Direct update preferred
   - Override/resolution if transitive dependency

3. **What's the risk of updating?**
   - Check changelog for breaking changes
   - Run tests after update

4. **Can we mitigate without updating?**
   - Input validation at boundaries
   - Configuration changes
   - WAF rules

### Documentation Template

For each accepted vulnerability:

```markdown
## Accepted Vulnerability: VULN-ID

**Package**: package-name@version
**Severity**: Medium
**Date Accepted**: YYYY-MM-DD
**Accepted By**: [Name]

### Justification
- We do not use the affected code path
- Our input validation prevents exploitation
- Fix introduces breaking changes we cannot accommodate

### Mitigations
- Added input validation in `src/handlers.rs:45`
- Rate limiting prevents mass exploitation
- Monitoring added for suspicious patterns

### Review Date
Re-evaluate by: YYYY-MM-DD
```

---

## CI/CD Integration

### GitHub Actions

```yaml
name: Dependency Audit
on:
  push:
    paths:
      - 'Cargo.lock'
      - 'package-lock.json'
      - 'requirements.txt'
  schedule:
    - cron: '0 0 * * 1'  # Weekly Monday

jobs:
  audit:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: cachix/install-nix-action@v24

      - name: Rust Audit
        if: hashFiles('Cargo.toml') != ''
        run: nix shell nixpkgs#cargo-audit -c cargo audit

      - name: npm Audit
        if: hashFiles('package-lock.json') != ''
        run: nix shell nixpkgs#nodejs -c npm audit

      - name: Python Audit
        if: hashFiles('pyproject.toml') != '' || hashFiles('requirements.txt') != ''
        run: nix shell nixpkgs#python3Packages.pip-audit -c pip-audit
```

### Pre-commit Hook

```bash
#!/bin/bash
# .git/hooks/pre-commit

if [ -f Cargo.toml ]; then
    nix shell nixpkgs#cargo-audit -c cargo audit --deny warnings
fi
```

---

## Quick Reference

| Language | Detection | Audit Command |
|----------|-----------|---------------|
| Rust | `Cargo.toml` | `nix shell nixpkgs#cargo-audit -c cargo audit` |
| JS/TS (Bun) | `bun.lockb` | `nix shell nixpkgs#bun -c bun audit` |
| JS/TS (npm) | `package-lock.json` | `nix shell nixpkgs#nodejs -c npm audit` |
| Python | `pyproject.toml` | `nix shell nixpkgs#python3Packages.pip-audit -c pip-audit` |
| Go | `go.mod` | `nix shell nixpkgs#govulncheck -c govulncheck ./...` |
