# Dependency Audit Tools Reference

Quick reference for dependency vulnerability scanning tools organized by language.

---

## Rust

### cargo-audit

Primary tool for Rust dependency auditing.

```bash
# Basic audit
nix shell nixpkgs#cargo-audit -c cargo audit

# JSON output
nix shell nixpkgs#cargo-audit -c cargo audit --json

# Deny warnings (fail on any vulnerability)
nix shell nixpkgs#cargo-audit -c cargo audit --deny warnings

# Fix vulnerabilities (update Cargo.lock)
nix shell nixpkgs#cargo-audit -c cargo audit fix
```

**Output Example:**
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

### cargo-deny

Comprehensive dependency policy enforcement.

```bash
nix shell nixpkgs#cargo-deny -c cargo deny check
```

### cargo-outdated

Find outdated dependencies.

```bash
nix shell nixpkgs#cargo-outdated -c cargo outdated
```

---

## JavaScript/TypeScript

### npm audit

For npm-managed projects.

```bash
# Basic audit
nix shell nixpkgs#nodejs -c npm audit

# JSON output
nix shell nixpkgs#nodejs -c npm audit --json

# Production only
nix shell nixpkgs#nodejs -c npm audit --omit=dev

# Auto-fix
nix shell nixpkgs#nodejs -c npm audit fix
```

### Bun audit

For Bun-managed projects.

```bash
nix shell nixpkgs#bun -c bun audit
```

### yarn audit

For Yarn projects.

```bash
nix shell nixpkgs#yarn -c yarn audit
```

### better-npm-audit

Enhanced npm audit with better output.

```bash
nix shell nixpkgs#nodejs -c npx better-npm-audit audit
```

---

## Python

### pip-audit

Modern Python dependency auditing.

```bash
# Audit installed packages
nix shell nixpkgs#python3Packages.pip-audit -c pip-audit

# From requirements file
nix shell nixpkgs#python3Packages.pip-audit -c pip-audit -r requirements.txt

# JSON output
nix shell nixpkgs#python3Packages.pip-audit -c pip-audit -f json

# Fix vulnerabilities
nix shell nixpkgs#python3Packages.pip-audit -c pip-audit --fix
```

### safety

Alternative vulnerability scanner.

```bash
# Basic check
nix shell nixpkgs#safety -c safety check

# From requirements
nix shell nixpkgs#safety -c safety check -r requirements.txt

# JSON output
nix shell nixpkgs#safety -c safety check --json
```

---

## Go

### govulncheck

Official Go vulnerability checker.

```bash
nix shell nixpkgs#govulncheck -c govulncheck ./...
```

### nancy

OSS Index vulnerability scanner.

```bash
nix shell nixpkgs#nancy -c nancy sleuth < go.sum
```

---

## Quick Reference Table

| Language | Tool | Nix Command |
|----------|------|-------------|
| Rust | cargo-audit | `nix shell nixpkgs#cargo-audit -c cargo audit` |
| JS (npm) | npm audit | `nix shell nixpkgs#nodejs -c npm audit` |
| JS (Bun) | bun audit | `nix shell nixpkgs#bun -c bun audit` |
| JS (Yarn) | yarn audit | `nix shell nixpkgs#yarn -c yarn audit` |
| Python | pip-audit | `nix shell nixpkgs#python3Packages.pip-audit -c pip-audit` |
| Python | safety | `nix shell nixpkgs#safety -c safety check` |
| Go | govulncheck | `nix shell nixpkgs#govulncheck -c govulncheck ./...` |

---

## Interpreting Severity

| Level | Description | Response Time |
|-------|-------------|---------------|
| Critical | Remote code execution, auth bypass | Immediate |
| High | Data exposure, significant impact | 24-48 hours |
| Moderate | Limited impact, requires conditions | 1-2 weeks |
| Low | Minor issues, defense in depth | Next release |

---

## Remediation Strategies

### Update Dependency

```bash
# Rust
cargo update -p vulnerable-crate

# npm
npm update vulnerable-package

# Python
pip install --upgrade vulnerable-package
```

### Pin Specific Version

**Rust (Cargo.toml):**
```toml
vulnerable-crate = "=1.2.3"  # Exact version
```

**npm (package.json):**
```json
{
  "overrides": {
    "vulnerable-package": "^2.0.0"
  }
}
```

**Python (pyproject.toml):**
```toml
[project]
dependencies = [
    "vulnerable-package>=2.0.0,<3.0.0"
]
```

### Accept Risk (Document)

If vulnerability doesn't apply:

```markdown
## Accepted: VULN-ID
- **Package**: name@version
- **Reason**: Code path not used in our application
- **Mitigations**: Input validation at API boundary
- **Review Date**: YYYY-MM-DD
```
