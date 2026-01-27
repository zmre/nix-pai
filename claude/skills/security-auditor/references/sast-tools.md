# Static Analysis (SAST) Tools Reference

This reference covers static analysis security testing tools organized by language.

---

## Multi-Language Tools

### Semgrep

Semgrep is the recommended multi-language SAST tool. It supports pattern matching across many languages.

**Installation:**
```bash
nix shell nixpkgs#semgrep
```

**Basic Usage:**
```bash
# Auto-detect language and run security rules
nix shell nixpkgs#semgrep -c semgrep scan --config=auto .

# Run OWASP Top 10 rules
nix shell nixpkgs#semgrep -c semgrep scan --config=p/owasp-top-ten .

# Run comprehensive security audit
nix shell nixpkgs#semgrep -c semgrep scan --config=p/security-audit .

# Run language-specific rules
nix shell nixpkgs#semgrep -c semgrep scan --config=p/rust .
nix shell nixpkgs#semgrep -c semgrep scan --config=p/typescript .
nix shell nixpkgs#semgrep -c semgrep scan --config=p/python .
```

**Available Rulesets:**
- `auto` - Automatic language detection + recommended rules
- `p/security-audit` - Comprehensive security checks
- `p/owasp-top-ten` - OWASP Top 10 vulnerabilities
- `p/secrets` - Secret detection
- `p/sql-injection` - SQL injection patterns
- `p/xss` - Cross-site scripting
- `p/ci` - CI-friendly rules (lower noise)

**Output Formats:**
```bash
# JSON output for processing
nix shell nixpkgs#semgrep -c semgrep scan --config=auto --json -o semgrep-results.json .

# SARIF for GitHub integration
nix shell nixpkgs#semgrep -c semgrep scan --config=auto --sarif -o semgrep.sarif .

# JUnit XML for CI
nix shell nixpkgs#semgrep -c semgrep scan --config=auto --junit-xml -o semgrep-junit.xml .
```

**Custom Rules:**
```yaml
# .semgrep.yml
rules:
  - id: hardcoded-api-key
    patterns:
      - pattern-regex: 'api[_-]?key\s*=\s*["\'][a-zA-Z0-9]{20,}["\']'
    message: Hardcoded API key detected
    languages: [rust, python, javascript, typescript]
    severity: ERROR

  - id: no-shell-interpolation
    patterns:
      - pattern: |
          Command::new("sh").arg("-c").arg($INTERPOLATED)
    message: Potential command injection via shell interpolation
    languages: [rust]
    severity: ERROR
```

---

## Rust Tools

### Clippy

Rust's built-in linter with security-relevant checks.

**Usage:**
```bash
# Basic run
nix develop -c cargo clippy

# With all warnings
nix develop -c cargo clippy -- -D warnings

# Pedantic lints (more thorough)
nix develop -c cargo clippy -- -D warnings -W clippy::pedantic

# Security-focused lints
nix develop -c cargo clippy -- \
    -D clippy::unwrap_used \
    -D clippy::expect_used \
    -D clippy::panic \
    -D clippy::todo \
    -D clippy::unimplemented
```

**Important Security Lints:**
- `clippy::unwrap_used` - Panic on None/Err
- `clippy::expect_used` - Similar to unwrap
- `clippy::indexing_slicing` - Potential panic on out-of-bounds
- `clippy::arithmetic_side_effects` - Integer overflow
- `clippy::cast_possible_truncation` - Data loss in casts

**Configuration (clippy.toml):**
```toml
# Deny unwrap in production code
warn-on-all-wildcard-imports = true
cognitive-complexity-threshold = 25
```

### cargo-audit

Check dependencies for known vulnerabilities.

```bash
nix shell nixpkgs#cargo-audit -c cargo audit
```

### cargo-deny

More comprehensive dependency checking.

```bash
nix shell nixpkgs#cargo-deny -c cargo deny check
```

**Configuration (deny.toml):**
```toml
[advisories]
vulnerability = "deny"
unmaintained = "warn"

[licenses]
unlicensed = "deny"
allow = ["MIT", "Apache-2.0", "ISC"]

[bans]
multiple-versions = "warn"
deny = [
    { name = "openssl" },  # Prefer rustls
]
```

### Unsafe Code Detection

```bash
# Find all unsafe blocks
grep -rn "unsafe" src/

# Use cargo-geiger
nix shell nixpkgs#cargo-geiger -c cargo geiger
```

---

## JavaScript/TypeScript Tools

### ESLint with Security Plugin

**Setup:**
```bash
npm install --save-dev eslint eslint-plugin-security
```

**Configuration (.eslintrc.json):**
```json
{
  "plugins": ["security"],
  "extends": ["plugin:security/recommended"],
  "rules": {
    "security/detect-object-injection": "error",
    "security/detect-non-literal-fs-filename": "error",
    "security/detect-non-literal-require": "error",
    "security/detect-possible-timing-attacks": "warn",
    "security/detect-eval-with-expression": "error",
    "security/detect-child-process": "error"
  }
}
```

**Usage:**
```bash
nix shell nixpkgs#nodejs -c npx eslint --ext .js,.ts,.jsx,.tsx .
```

### TypeScript Compiler Checks

**Strict Configuration (tsconfig.json):**
```json
{
  "compilerOptions": {
    "strict": true,
    "noImplicitAny": true,
    "strictNullChecks": true,
    "noUncheckedIndexedAccess": true,
    "exactOptionalPropertyTypes": true
  }
}
```

### npm audit

```bash
nix shell nixpkgs#nodejs -c npm audit
```

---

## Python Tools

### Bandit

Python-specific security linter.

**Usage:**
```bash
# Basic scan
nix shell nixpkgs#bandit -c bandit -r .

# With severity filter
nix shell nixpkgs#bandit -c bandit -r . -ll  # Only high severity

# JSON output
nix shell nixpkgs#bandit -c bandit -r . -f json -o bandit.json

# Skip specific tests
nix shell nixpkgs#bandit -c bandit -r . --skip B101,B102
```

**Common Issue Codes:**
- B101: assert used (assertions disabled in production)
- B102: exec_used
- B103: set_bad_file_permissions
- B104: hardcoded_bind_all_interfaces
- B105: hardcoded_password_string
- B106: hardcoded_password_funcarg
- B107: hardcoded_password_default
- B108: hardcoded_tmp_directory
- B110: try_except_pass
- B112: try_except_continue
- B201: flask_debug_true
- B301: pickle
- B303: md5/sha1
- B307: eval
- B310: urllib_urlopen
- B311: random (not cryptographic)
- B320: xml parsing
- B324: hashlib weak algorithms
- B501: request_with_no_cert_validation
- B506: yaml_load

**Configuration (.bandit.yaml):**
```yaml
skips: ['B101']  # Skip assert warnings in tests
exclude_dirs: ['tests', 'venv']
```

### Safety

Check dependencies against known vulnerabilities.

```bash
nix shell nixpkgs#safety -c safety check
nix shell nixpkgs#safety -c safety check -r requirements.txt
```

### pip-audit

Modern dependency auditing.

```bash
nix shell nixpkgs#python3Packages.pip-audit -c pip-audit
```

### mypy (Type Checking)

Type checking can catch security issues.

```bash
nix shell nixpkgs#mypy -c mypy --strict .
```

---

## Shell Script Tools

### ShellCheck

Lint shell scripts for common issues.

```bash
# Scan all shell scripts
nix shell nixpkgs#shellcheck -c shellcheck *.sh

# Scan recursively
nix shell nixpkgs#shellcheck -c find . -name "*.sh" -exec shellcheck {} +

# With severity filter
nix shell nixpkgs#shellcheck -c shellcheck -S warning *.sh
```

**Security-Relevant Checks:**
- SC2046: Quote to prevent word splitting
- SC2086: Double quote to prevent globbing
- SC2091: Quote to prevent command injection
- SC2116: Useless echo in command substitution
- SC2155: Declare and assign separately

---

## Go Tools

### gosec

Security-focused linter for Go.

```bash
nix shell nixpkgs#gosec -c gosec ./...
```

### go vet

Built-in static analysis.

```bash
nix shell nixpkgs#go -c go vet ./...
```

### staticcheck

Comprehensive static analysis.

```bash
nix shell nixpkgs#go -c staticcheck ./...
```

---

## CI/CD Integration

### GitHub Actions

```yaml
name: SAST
on: [push, pull_request]

jobs:
  security:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: cachix/install-nix-action@v24

      - name: Semgrep
        run: |
          nix shell nixpkgs#semgrep -c semgrep scan --config=auto --sarif -o semgrep.sarif .
        continue-on-error: true

      - name: Upload SARIF
        uses: github/codeql-action/upload-sarif@v2
        with:
          sarif_file: semgrep.sarif

      - name: Rust (Clippy)
        if: hashFiles('Cargo.toml') != ''
        run: nix develop -c cargo clippy -- -D warnings

      - name: Python (Bandit)
        if: hashFiles('pyproject.toml') != ''
        run: nix shell nixpkgs#bandit -c bandit -r . -ll

      - name: Shell (ShellCheck)
        run: nix shell nixpkgs#shellcheck -c find . -name "*.sh" -exec shellcheck {} +
```

### Pre-commit Hook

```yaml
# .pre-commit-config.yaml
repos:
  - repo: https://github.com/semgrep/semgrep
    rev: v1.45.0
    hooks:
      - id: semgrep
        args: ['--config', 'auto']

  - repo: https://github.com/PyCQA/bandit
    rev: 1.7.5
    hooks:
      - id: bandit
        args: ['-ll']

  - repo: https://github.com/koalaman/shellcheck-precommit
    rev: v0.9.0
    hooks:
      - id: shellcheck
```

---

## Quick Reference

| Language | Tool | Nix Command |
|----------|------|-------------|
| All | Semgrep | `nix shell nixpkgs#semgrep -c semgrep scan --config=auto .` |
| Rust | Clippy | `nix develop -c cargo clippy -- -D warnings` |
| Rust | cargo-audit | `nix shell nixpkgs#cargo-audit -c cargo audit` |
| Python | Bandit | `nix shell nixpkgs#bandit -c bandit -r .` |
| Python | pip-audit | `nix shell nixpkgs#python3Packages.pip-audit -c pip-audit` |
| JS/TS | ESLint | `nix shell nixpkgs#nodejs -c npx eslint .` |
| JS/TS | npm audit | `nix shell nixpkgs#nodejs -c npm audit` |
| Shell | ShellCheck | `nix shell nixpkgs#shellcheck -c shellcheck *.sh` |
| Go | gosec | `nix shell nixpkgs#gosec -c gosec ./...` |
