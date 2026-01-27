# Security Auditor - Comprehensive Methodology

This document provides the complete methodology for conducting security audits on software repositories. Follow this guide when performing any security assessment.

## Pre-Audit Checklist

Before starting an audit:

- [ ] Confirm scope with user (full audit vs. specific focus)
- [ ] Identify all languages and frameworks in use
- [ ] Check for existing security documentation
- [ ] Note any compliance requirements (SOC2, HIPAA, etc.)
- [ ] Verify access to all relevant code and dependencies

## Phase 1: Reconnaissance

### Project Structure Analysis

```bash
# List all file types
find . -type f -name "*.*" | sed 's/.*\.//' | sort | uniq -c | sort -rn

# Check for configuration files
ls -la *.toml *.json *.yaml *.yml .env* 2>/dev/null
```

### Language Detection Matrix

| File Present | Primary Language | Secondary Checks |
|--------------|------------------|------------------|
| `Cargo.toml` | Rust | Check for `unsafe` blocks |
| `package.json` + `bun.lockb` | TypeScript/JS (Bun) | Check for npm audit compatibility |
| `package.json` + `package-lock.json` | TypeScript/JS (npm) | Check for outdated dependencies |
| `pyproject.toml` | Python | Check for type hints usage |
| `requirements.txt` | Python (legacy) | Recommend migration to pyproject.toml |
| `go.mod` | Go | Check for go.sum presence |
| `build.sbt` | Scala | Check for security plugins |

### Framework Detection

Identify frameworks to focus security review:

**Web Frameworks:**
- Rust: Actix-web, Axum, Rocket, Warp
- TypeScript: Express, Fastify, Nest.js, Hono
- Python: FastAPI, Flask, Django

**Crypto Libraries:**
- Rust: ring, RustCrypto, sodiumoxide
- TypeScript: crypto, node-forge, jose
- Python: cryptography, pynacl

## Phase 2: Dependency Auditing

### Rust Dependencies

```bash
# Primary audit
nix shell nixpkgs#cargo-audit -c cargo audit

# Check for outdated dependencies
nix shell nixpkgs#cargo-outdated -c cargo outdated

# Generate dependency tree
cargo tree --duplicates
```

**Interpreting Results:**
- RUSTSEC advisories are authoritative
- Severity levels: Critical > High > Medium > Low
- Check if vulnerable code path is actually used

### TypeScript/JavaScript Dependencies

```bash
# For Bun projects
nix shell nixpkgs#bun -c bun audit

# For npm projects
nix shell nixpkgs#nodejs -c npm audit

# For deep analysis
nix shell nixpkgs#nodejs -c npx better-npm-audit audit
```

**Common Issues:**
- Prototype pollution
- Regular expression denial of service (ReDoS)
- Arbitrary code execution in build scripts

### Python Dependencies

```bash
# Primary audit
nix shell nixpkgs#python3Packages.pip-audit -c pip-audit

# Check for known vulnerabilities
nix shell nixpkgs#safety -c safety check
```

**Python-Specific Concerns:**
- Pickle deserialization vulnerabilities
- YAML load without SafeLoader
- exec/eval usage

## Phase 3: Static Analysis (SAST)

### Multi-Language Analysis with Semgrep

```bash
# Run with auto-detection
nix shell nixpkgs#semgrep -c semgrep scan --config=auto .

# Run with specific rulesets
nix shell nixpkgs#semgrep -c semgrep scan --config=p/security-audit .
nix shell nixpkgs#semgrep -c semgrep scan --config=p/owasp-top-ten .

# For CI integration
nix shell nixpkgs#semgrep -c semgrep scan --config=auto --json > semgrep-results.json
```

### Language-Specific SAST

**Rust:**
```bash
# Clippy with all lints
nix develop -c cargo clippy -- -D warnings -W clippy::all -W clippy::pedantic

# Check for unsafe usage
grep -rn "unsafe" src/
```

**Python:**
```bash
# Bandit security linter
nix shell nixpkgs#bandit -c bandit -r . -f json -o bandit-results.json

# With severity filter
nix shell nixpkgs#bandit -c bandit -r . -ll  # Only high severity
```

**JavaScript/TypeScript:**
```bash
# ESLint with security plugin
nix shell nixpkgs#nodejs -c npx eslint --ext .js,.ts . --plugin security

# For React projects
nix shell nixpkgs#nodejs -c npx eslint --ext .jsx,.tsx . --plugin react-hooks
```

**Shell Scripts:**
```bash
# ShellCheck for bash scripts
nix shell nixpkgs#shellcheck -c shellcheck *.sh scripts/*.sh
```

## Phase 4: Secrets Scanning

### Gitleaks Scanning

```bash
# Scan current state
nix shell nixpkgs#gitleaks -c gitleaks detect --source .

# Scan git history
nix shell nixpkgs#gitleaks -c gitleaks detect --source . --log-opts="--all"

# Generate report
nix shell nixpkgs#gitleaks -c gitleaks detect --source . --report-format json --report-path gitleaks-report.json
```

### .gitignore Verification

Ensure these patterns are present:

```gitignore
# Secrets
.env
.env.*
*.pem
*.key
*.p12
*.pfx
credentials.json
secrets.json
**/secret*
**/*secret*

# IDE and local
.idea/
.vscode/settings.json
*.local

# Build artifacts that may contain secrets
dist/
build/
target/
```

### Manual Secret Patterns

Search for hardcoded secrets:

```bash
# API keys
grep -rn "api[_-]key\|apikey" --include="*.{rs,ts,js,py}" .

# Passwords
grep -rn "password\|passwd\|secret" --include="*.{rs,ts,js,py}" .

# AWS credentials
grep -rn "AKIA\|aws_access_key" .

# Private keys
grep -rn "BEGIN.*PRIVATE KEY" .
```

## Phase 5: Code Review for Vulnerability Patterns

### OWASP Top 10 Checklist

#### A01: Broken Access Control
- [ ] Authorization checks on all endpoints
- [ ] Role-based access control implementation
- [ ] Resource ownership verification
- [ ] JWT/session validation

#### A02: Cryptographic Failures
- [ ] No hardcoded secrets
- [ ] Strong algorithms (AES-256, RSA-2048+, Ed25519)
- [ ] Secure random number generation
- [ ] Proper key management

#### A03: Injection
- [ ] SQL queries use parameterized statements
- [ ] Command execution sanitizes input
- [ ] Template rendering escapes output
- [ ] LDAP queries sanitize input

#### A04: Insecure Design
- [ ] Rate limiting on sensitive endpoints
- [ ] Input validation at boundaries
- [ ] Fail-secure defaults

#### A05: Security Misconfiguration
- [ ] Debug mode disabled in production configs
- [ ] Secure headers configured
- [ ] Unnecessary features disabled

#### A06: Vulnerable Components
- [ ] Dependencies audited (Phase 2)
- [ ] Components up to date
- [ ] Unused dependencies removed

#### A07: Authentication Failures
- [ ] Password hashing uses bcrypt/argon2
- [ ] MFA available for sensitive actions
- [ ] Session management secure

#### A08: Software and Data Integrity
- [ ] Signed commits/tags
- [ ] Dependency lock files committed
- [ ] CI/CD pipeline secured

#### A09: Security Logging
- [ ] Authentication events logged
- [ ] Authorization failures logged
- [ ] No sensitive data in logs

#### A10: Server-Side Request Forgery (SSRF)
- [ ] URL validation for user-provided URLs
- [ ] Allowlist for external requests
- [ ] No internal network access from user input

## Phase 6: Fuzzing

### Rust Fuzzing with cargo-fuzz

```bash
# Initialize fuzzing infrastructure
nix shell nixpkgs#cargo-fuzz -c cargo fuzz init

# List existing fuzz targets
nix shell nixpkgs#cargo-fuzz -c cargo fuzz list

# Create new fuzz target
nix shell nixpkgs#cargo-fuzz -c cargo fuzz add target_name
```

**Writing Effective Fuzz Targets:**

```rust
// fuzz/fuzz_targets/parse_input.rs
#![no_main]
use libfuzzer_sys::fuzz_target;
use my_crate::parse_input;

fuzz_target!(|data: &[u8]| {
    if let Ok(s) = std::str::from_utf8(data) {
        let _ = parse_input(s);
    }
});
```

**Running Fuzzing:**

```bash
# Run with time limit (2 minutes)
nix shell nixpkgs#cargo-fuzz -c cargo fuzz run target_name -- -max_total_time=120

# Run with memory limit
nix shell nixpkgs#cargo-fuzz -c cargo fuzz run target_name -- -rss_limit_mb=2048

# Run in CI (quick check)
nix shell nixpkgs#cargo-fuzz -c cargo fuzz run target_name -- -max_total_time=30
```

**Analyzing Crashes:**

```bash
# List crash artifacts
ls fuzz/artifacts/target_name/

# Minimize crash case
nix shell nixpkgs#cargo-fuzz -c cargo fuzz tmin target_name fuzz/artifacts/target_name/crash-xxx
```

### Python Fuzzing with Atheris

```python
#!/usr/bin/env python3
import atheris
import sys

with atheris.instrument_imports():
    from my_module import parse_input

def test_one_input(data):
    try:
        fdp = atheris.FuzzedDataProvider(data)
        input_str = fdp.ConsumeUnicodeNoSurrogates(100)
        parse_input(input_str)
    except ValueError:
        pass  # Expected for invalid input

if __name__ == "__main__":
    atheris.Setup(sys.argv, test_one_input)
    atheris.Fuzz()
```

Run with:
```bash
nix shell nixpkgs#python3Packages.atheris -c python fuzz_target.py -max_total_time=120
```

## Phase 7: Property-Based Testing

### Rust with proptest

Add to `Cargo.toml`:
```toml
[dev-dependencies]
proptest = "1.4"
```

**Security Test Patterns:**

```rust
use proptest::prelude::*;

proptest! {
    // No path traversal
    #[test]
    fn no_path_traversal(s in ".*") {
        let result = sanitize_path(&s);
        assert!(!result.contains(".."));
        assert!(!result.starts_with('/'));
    }

    // SQL injection prevention
    #[test]
    fn sql_injection_safe(s in ".*") {
        let query = build_query(&s);
        assert!(!query.contains("--"));
        assert!(!query.contains(";"));
    }

    // XSS prevention
    #[test]
    fn xss_safe(s in ".*") {
        let output = render_user_input(&s);
        assert!(!output.contains("<script"));
        assert!(!output.contains("javascript:"));
    }

    // Command injection prevention
    #[test]
    fn command_injection_safe(s in "[a-zA-Z0-9_-]*") {
        let cmd = build_command(&s);
        assert!(!cmd.contains('|'));
        assert!(!cmd.contains(';'));
        assert!(!cmd.contains('`'));
    }
}
```

### TypeScript with fast-check

```typescript
import fc from 'fast-check';

describe('Security Properties', () => {
  it('prevents path traversal', () => {
    fc.assert(
      fc.property(fc.string(), (input) => {
        const result = sanitizePath(input);
        expect(result).not.toContain('..');
        expect(result).not.toMatch(/^[/\\]/);
      })
    );
  });

  it('escapes HTML entities', () => {
    fc.assert(
      fc.property(fc.string(), (input) => {
        const output = escapeHtml(input);
        expect(output).not.toContain('<');
        expect(output).not.toContain('>');
      })
    );
  });

  it('handles unicode safely', () => {
    fc.assert(
      fc.property(fc.fullUnicodeString(), (input) => {
        const result = processInput(input);
        // Should not throw
        expect(typeof result).toBe('string');
      })
    );
  });
});
```

### Python with hypothesis

```python
from hypothesis import given, strategies as st
import pytest

class TestSecurityProperties:
    @given(st.text())
    def test_no_path_traversal(self, s):
        result = sanitize_path(s)
        assert '..' not in result
        assert not result.startswith('/')

    @given(st.text())
    def test_sql_safe(self, s):
        query = build_query(s)
        assert '--' not in query
        assert ';' not in query
        assert "'" not in query or query.count("'") % 2 == 0

    @given(st.text())
    def test_html_escaped(self, s):
        output = escape_html(s)
        assert '<' not in output
        assert '>' not in output

    @given(st.binary())
    def test_handles_binary(self, data):
        # Should not crash on arbitrary binary
        try:
            process_input(data)
        except ValueError:
            pass  # Expected for invalid input
```

## Phase 8: Report Generation

### Report File Naming

Format: `YYYY-MM-DD-SECURITY-AUDIT.md`

Example: `2024-01-15-SECURITY-AUDIT.md`

### Report Structure

See [references/report-template.md](./references/report-template.md) for the full template.

### Severity Definitions

| Severity | CVSS Score | Response Time | Description |
|----------|------------|---------------|-------------|
| Critical | 9.0-10.0 | Immediate | Active exploitation possible |
| High | 7.0-8.9 | 24-48 hours | Significant impact likely |
| Medium | 4.0-6.9 | 1-2 weeks | Moderate impact |
| Low | 0.1-3.9 | Next release | Minor impact |
| Info | 0.0 | Best effort | Hardening recommendation |

### Writing Effective Findings

Each finding should include:

1. **Title**: Clear, specific description
2. **Severity**: Critical/High/Medium/Low/Info
3. **Location**: File path and line number
4. **Description**: What the issue is
5. **Impact**: What could happen if exploited
6. **Reproduction**: Steps to reproduce or trigger
7. **Remediation**: Specific fix instructions
8. **References**: CWE, CVE, OWASP references

## Integration with IronCore Standards

When auditing IronCore projects:

1. **Load Language Skills First**
   - Rust: Read `/nix/store/.../ironcore-rust-language/SKILL.md`
   - TypeScript: Read `/nix/store/.../ironcore-typescript-javascript/SKILL.md`

2. **Follow IronCore Coding Standards**
   - Check for compliance with IronCore patterns
   - Verify error handling matches standards
   - Confirm logging practices

3. **IronCore-Specific Security Checks**
   - Verify encryption at rest implementation
   - Check key management practices
   - Validate BYOK/HYOK implementations

## CI/CD Integration Recommendations

### GitHub Actions Example

```yaml
name: Security Audit
on:
  pull_request:
  schedule:
    - cron: '0 0 * * 0'  # Weekly

jobs:
  audit:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install Nix
        uses: cachix/install-nix-action@v24

      - name: Dependency Audit
        run: |
          nix shell nixpkgs#cargo-audit -c cargo audit
          nix shell nixpkgs#semgrep -c semgrep scan --config=auto .

      - name: Secrets Scan
        run: nix shell nixpkgs#gitleaks -c gitleaks detect --source .

      - name: Fuzz Test (Quick)
        run: |
          nix shell nixpkgs#cargo-fuzz -c cargo fuzz run parse_input -- -max_total_time=30
```

## Post-Audit Actions

After completing the audit:

1. **Deliver Report**
   - Save as `YYYY-MM-DD-SECURITY-AUDIT.md`
   - Summarize key findings for user

2. **Create Issues**
   - Offer to create GitHub issues for each finding
   - Use appropriate labels (security, priority)

3. **Recommend Follow-up**
   - Suggest timeline for re-audit
   - Recommend monitoring for new CVEs

4. **Document Exceptions**
   - Note any accepted risks
   - Document compensating controls

## Quick Command Reference

```bash
# Full audit workflow
nix shell nixpkgs#cargo-audit -c cargo audit
nix shell nixpkgs#semgrep -c semgrep scan --config=auto .
nix shell nixpkgs#gitleaks -c gitleaks detect --source .
nix shell nixpkgs#bandit -c bandit -r . 2>/dev/null || true
nix shell nixpkgs#shellcheck -c shellcheck *.sh 2>/dev/null || true

# Fuzzing quick start
nix shell nixpkgs#cargo-fuzz -c cargo fuzz init
nix shell nixpkgs#cargo-fuzz -c cargo fuzz run <target> -- -max_total_time=120

# Property testing
cargo test --features proptest  # Rust
npx jest --testPathPattern=security  # TypeScript
pytest tests/test_security.py  # Python
```
