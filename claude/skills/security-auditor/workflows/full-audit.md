# Full Security Audit Workflow

This workflow provides a step-by-step checklist for conducting a comprehensive security audit.

## Pre-Audit Setup

### 1. Confirm Scope

```
Questions to ask:
- Full audit or specific focus area?
- Any compliance requirements (SOC2, HIPAA, PCI-DSS)?
- Known sensitive areas or recent changes?
- Timeline and priority level?
```

### 2. Environment Preparation

```bash
# Navigate to project root
cd /path/to/project

# Verify git status
git status
git remote -v

# Check project structure
ls -la
```

### 3. Identify Languages and Frameworks

```bash
# Quick detection
[ -f Cargo.toml ] && echo "Rust project detected"
[ -f package.json ] && echo "JavaScript/TypeScript project detected"
[ -f pyproject.toml ] && echo "Python project detected"
[ -f go.mod ] && echo "Go project detected"
[ -f build.sbt ] && echo "Scala project detected"

# Count files by type
find . -type f -name "*.*" | sed 's/.*\.//' | sort | uniq -c | sort -rn | head -20
```

---

## Phase 1: Automated Scanning

### 1.1 Dependency Audit

**Rust:**
```bash
nix shell nixpkgs#cargo-audit -c cargo audit
```

**TypeScript/JavaScript (Bun):**
```bash
nix shell nixpkgs#bun -c bun audit
```

**TypeScript/JavaScript (npm):**
```bash
nix shell nixpkgs#nodejs -c npm audit
```

**Python:**
```bash
nix shell nixpkgs#python3Packages.pip-audit -c pip-audit
```

**Record findings:**
- [ ] Note all Critical/High vulnerabilities
- [ ] Check if vulnerable code paths are used
- [ ] Document remediation steps

### 1.2 Static Analysis (SAST)

**Semgrep (all languages):**
```bash
nix shell nixpkgs#semgrep -c semgrep scan --config=auto .
nix shell nixpkgs#semgrep -c semgrep scan --config=p/security-audit .
```

**Rust-specific:**
```bash
nix develop -c cargo clippy -- -D warnings -W clippy::all
```

**Python-specific:**
```bash
nix shell nixpkgs#bandit -c bandit -r . -ll
```

**Shell scripts:**
```bash
nix shell nixpkgs#shellcheck -c shellcheck *.sh scripts/*.sh 2>/dev/null
```

**Record findings:**
- [ ] Categorize by severity
- [ ] Note false positives for exclusion
- [ ] Document code locations

### 1.3 Secrets Scanning

```bash
# Current state
nix shell nixpkgs#gitleaks -c gitleaks detect --source .

# Full git history
nix shell nixpkgs#gitleaks -c gitleaks detect --source . --log-opts="--all"
```

**Verify .gitignore:**
- [ ] `.env` and `.env.*` patterns present
- [ ] `*.pem`, `*.key` patterns present
- [ ] IDE settings excluded
- [ ] No secrets in committed history

---

## Phase 2: Manual Code Review

### 2.1 Authentication & Authorization

Review checklist:
- [ ] All endpoints require authentication where needed
- [ ] Authorization checks verify resource ownership
- [ ] Session management is secure
- [ ] Password hashing uses strong algorithms (argon2, bcrypt)
- [ ] JWT tokens validated properly (signature, expiration, audience)

**Search patterns:**
```bash
grep -rn "authenticate\|authorize\|login\|session" --include="*.{rs,ts,js,py}"
grep -rn "jwt\|token\|bearer" --include="*.{rs,ts,js,py}"
```

### 2.2 Input Validation

Review checklist:
- [ ] All user input validated at boundaries
- [ ] SQL queries use parameterized statements
- [ ] Command execution sanitizes input
- [ ] File paths validated against traversal
- [ ] URL inputs validated for SSRF

**Search patterns:**
```bash
grep -rn "execute\|query\|command\|spawn\|exec" --include="*.{rs,ts,js,py}"
grep -rn "path\|file\|read\|write" --include="*.{rs,ts,js,py}"
```

### 2.3 Cryptography

Review checklist:
- [ ] No hardcoded secrets or keys
- [ ] Strong algorithms used (AES-256, RSA-2048+, Ed25519)
- [ ] Secure random generation for tokens/keys
- [ ] No deprecated algorithms (MD5, SHA1 for security, DES)

**Search patterns:**
```bash
grep -rn "encrypt\|decrypt\|hash\|sign\|verify" --include="*.{rs,ts,js,py}"
grep -rn "random\|uuid\|token" --include="*.{rs,ts,js,py}"
```

### 2.4 Data Handling

Review checklist:
- [ ] Sensitive data not logged
- [ ] PII properly protected
- [ ] Data sanitized before display (XSS prevention)
- [ ] Proper error messages (no stack traces to users)

**Search patterns:**
```bash
grep -rn "log\|print\|console" --include="*.{rs,ts,js,py}"
grep -rn "render\|display\|response" --include="*.{rs,ts,js,py}"
```

### 2.5 Configuration

Review checklist:
- [ ] Debug mode disabled in production configs
- [ ] Secure defaults for all settings
- [ ] Environment variables used for secrets
- [ ] CORS properly configured
- [ ] Security headers enabled

**Files to review:**
```bash
ls -la *.toml *.json *.yaml *.yml config/ .env.example 2>/dev/null
```

---

## Phase 3: Fuzzing (If Applicable)

### 3.1 Identify Fuzz Targets

Good targets for fuzzing:
- Input parsing functions
- Deserialization code
- Protocol handlers
- File format parsers
- URL/path processing

### 3.2 Set Up Fuzzing

**Rust:**
```bash
# Initialize if not present
nix shell nixpkgs#cargo-fuzz -c cargo fuzz init

# Create target for identified function
nix shell nixpkgs#cargo-fuzz -c cargo fuzz add parse_input
```

### 3.3 Run Fuzzing

```bash
# Run with 2-minute time limit
nix shell nixpkgs#cargo-fuzz -c cargo fuzz run parse_input -- -max_total_time=120

# Check for crashes
ls fuzz/artifacts/parse_input/
```

### 3.4 Analyze Results

- [ ] Document any crashes found
- [ ] Minimize crash cases
- [ ] Create reproducers for findings
- [ ] Recommend fuzzing integration in CI

---

## Phase 4: Property-Based Testing

### 4.1 Identify Security Properties

Common properties to test:
- No path traversal in sanitized paths
- No SQL injection in built queries
- No XSS in rendered output
- No command injection in built commands
- Handles malformed input gracefully

### 4.2 Add Security Tests

**Rust (proptest):**
```rust
proptest! {
    #[test]
    fn no_path_traversal(s in ".*") {
        let result = sanitize_path(&s);
        assert!(!result.contains(".."));
    }
}
```

**TypeScript (fast-check):**
```typescript
fc.assert(fc.property(fc.string(), (input) => {
  const result = sanitizePath(input);
  expect(result).not.toContain('..');
}));
```

**Python (hypothesis):**
```python
@given(st.text())
def test_no_path_traversal(self, s):
    result = sanitize_path(s)
    assert '..' not in result
```

### 4.3 Run Tests

```bash
# Rust
cargo test security

# TypeScript
npx jest --testPathPattern=security

# Python
pytest tests/test_security.py
```

---

## Phase 5: Report Generation

### 5.1 Compile Findings

Gather all findings from:
- [ ] Dependency audit results
- [ ] SAST scan results
- [ ] Secrets scan results
- [ ] Manual review findings
- [ ] Fuzzing results
- [ ] Property test results

### 5.2 Classify Findings

For each finding, determine:
- **Severity**: Critical / High / Medium / Low / Info
- **CVSS Score**: (if applicable)
- **CWE Reference**: (if applicable)
- **Remediation Priority**: Immediate / Short-term / Long-term

### 5.3 Generate Report

Create `YYYY-MM-DD-SECURITY-AUDIT.md` using the template from `references/report-template.md`.

**Required sections:**
1. Executive Summary
2. Scope and Methodology
3. Findings Summary Table
4. Detailed Findings
5. Automated Scan Results
6. Recommendations
7. Appendix

### 5.4 Deliver Report

- [ ] Save report to project root or docs/
- [ ] Summarize key findings verbally
- [ ] Offer to create GitHub issues
- [ ] Recommend follow-up timeline

---

## Post-Audit Checklist

- [ ] Report delivered and saved
- [ ] Critical findings highlighted
- [ ] Remediation guidance provided
- [ ] CI/CD recommendations documented
- [ ] Re-audit timeline suggested
- [ ] Any accepted risks documented

## Quick Audit Commands (Copy/Paste)

```bash
# Full automated scan suite
nix shell nixpkgs#cargo-audit -c cargo audit 2>/dev/null || echo "Not a Rust project"
nix shell nixpkgs#nodejs -c npm audit 2>/dev/null || echo "No npm lockfile"
nix shell nixpkgs#python3Packages.pip-audit -c pip-audit 2>/dev/null || echo "Not a Python project"
nix shell nixpkgs#semgrep -c semgrep scan --config=auto .
nix shell nixpkgs#gitleaks -c gitleaks detect --source .
nix shell nixpkgs#bandit -c bandit -r . 2>/dev/null || true
nix shell nixpkgs#shellcheck -c shellcheck *.sh 2>/dev/null || true

# Generate findings summary
echo "=== Audit Complete ==="
date +"%Y-%m-%d"
```
