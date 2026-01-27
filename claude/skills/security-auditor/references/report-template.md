# Security Audit Report Template

Use this template to generate comprehensive security audit reports.

---

## Report Header

```markdown
# Security Audit Report

**Project:** [Project Name]
**Repository:** [URL or path]
**Audit Date:** YYYY-MM-DD
**Auditor:** [Name/System]
**Scope:** [Full audit / Dependency audit / Code review / etc.]

---
```

---

## Executive Summary Section

```markdown
## Executive Summary

### Overall Risk Assessment

| Risk Level | Description |
|------------|-------------|
| **[CRITICAL/HIGH/MEDIUM/LOW]** | [One sentence summary of security posture] |

### Key Statistics

| Category | Count |
|----------|-------|
| Critical Findings | X |
| High Findings | X |
| Medium Findings | X |
| Low Findings | X |
| Informational | X |
| **Total** | **X** |

### Top Priorities

1. **[Finding Title]** - [Brief description and impact]
2. **[Finding Title]** - [Brief description and impact]
3. **[Finding Title]** - [Brief description and impact]

### Scope Covered

- [x] Dependency vulnerability audit
- [x] Static analysis (SAST)
- [x] Secrets scanning
- [x] Code review for OWASP Top 10
- [ ] Fuzzing (if applicable)
- [ ] Property-based testing

---
```

---

## Findings Summary Table

```markdown
## Findings Summary

| ID | Severity | Title | Location | Status |
|----|----------|-------|----------|--------|
| SEC-001 | Critical | SQL Injection in user search | `src/api/users.rs:45` | Open |
| SEC-002 | High | Hardcoded API key | `src/config.rs:12` | Open |
| SEC-003 | Medium | Missing rate limiting on login | `src/auth/login.rs:30` | Open |
| SEC-004 | Low | Debug logging includes email | `src/handlers/user.rs:88` | Open |
| SEC-005 | Info | Consider adding CSP header | `src/middleware/headers.rs` | Open |

---
```

---

## Detailed Findings Section

```markdown
## Detailed Findings

### SEC-001: SQL Injection in User Search

**Severity:** Critical
**CVSS Score:** 9.8 (if calculated)
**CWE:** CWE-89 (SQL Injection)
**Location:** `src/api/users.rs:45`

#### Description

The user search endpoint constructs SQL queries using string concatenation with user-provided input, allowing SQL injection attacks.

#### Vulnerable Code

```rust
// src/api/users.rs:45
let query = format!("SELECT * FROM users WHERE name LIKE '%{}%'", search_term);
let results = sqlx::query(&query).fetch_all(&pool).await?;
```

#### Impact

An attacker can:
- Extract all data from the database
- Modify or delete data
- Potentially execute system commands (depending on database configuration)

#### Proof of Concept

```
GET /api/users?search=' OR '1'='1' --
```

This returns all users in the database.

#### Remediation

Use parameterized queries:

```rust
// Secure version
let results = sqlx::query("SELECT * FROM users WHERE name LIKE $1")
    .bind(format!("%{}%", search_term))
    .fetch_all(&pool)
    .await?;
```

#### References

- [OWASP SQL Injection](https://owasp.org/www-community/attacks/SQL_Injection)
- [CWE-89](https://cwe.mitre.org/data/definitions/89.html)

---

### SEC-002: Hardcoded API Key

**Severity:** High
**CWE:** CWE-798 (Use of Hard-coded Credentials)
**Location:** `src/config.rs:12`

#### Description

An API key is hardcoded directly in the source code, which will be exposed in version control and build artifacts.

#### Vulnerable Code

```rust
// src/config.rs:12
const STRIPE_API_KEY: &str = "sk_live_abc123xyz789...";
```

#### Impact

- API key exposed to anyone with repository access
- Key persists in git history even if removed
- Credentials cannot be rotated without code change

#### Remediation

1. Immediately rotate the exposed API key
2. Load from environment variable:

```rust
let stripe_key = std::env::var("STRIPE_API_KEY")
    .expect("STRIPE_API_KEY must be set");
```

3. Add to `.gitignore`:
```
.env
*.env
```

4. Use secrets management (e.g., HashiCorp Vault, AWS Secrets Manager)

#### References

- [CWE-798](https://cwe.mitre.org/data/definitions/798.html)
- [OWASP Secrets Management](https://cheatsheetseries.owasp.org/cheatsheets/Secrets_Management_Cheat_Sheet.html)

---
```

---

## Automated Scan Results Section

```markdown
## Automated Scan Results

### Dependency Audit

**Tool:** cargo-audit
**Date:** YYYY-MM-DD

```
Crate:     regex
Version:   1.5.4
Title:     Potential denial of service in regex
Date:      2022-03-08
ID:        RUSTSEC-2022-0013
URL:       https://rustsec.org/advisories/RUSTSEC-2022-0013
Severity:  medium
Solution:  upgrade to >=1.5.5

warning: 1 allowed warning found
```

**Summary:** 1 medium-severity vulnerability found. Update recommended.

### Static Analysis (Semgrep)

**Tool:** Semgrep v1.45.0
**Config:** p/security-audit

| Rule | Severity | Count |
|------|----------|-------|
| sql-injection | High | 1 |
| hardcoded-secret | High | 1 |
| missing-csrf | Medium | 0 |

### Secrets Scan (Gitleaks)

**Tool:** Gitleaks v8.18.0

```
Finding:     Generic API Key
Secret:      sk_live_abc...
File:        src/config.rs
Line:        12
Commit:      a1b2c3d4
```

**Summary:** 1 secret detected. Requires immediate rotation.

---
```

---

## Recommendations Section

```markdown
## Recommendations

### Immediate Actions (24-48 hours)

1. **SEC-001:** Fix SQL injection vulnerability in user search
   - Estimated effort: 30 minutes
   - Risk if delayed: Critical - active exploitation possible

2. **SEC-002:** Rotate exposed Stripe API key
   - Estimated effort: 1 hour
   - Risk if delayed: High - credential compromise

### Short-term Actions (1-2 weeks)

3. **SEC-003:** Implement rate limiting on authentication endpoints
   - Estimated effort: 2-4 hours
   - Recommendation: Use actix-governor middleware

4. Update dependencies with known vulnerabilities:
   - `regex` to >=1.5.5
   - Run `cargo audit fix`

### Long-term Improvements

5. Implement security testing in CI/CD:
   - Add `cargo audit` to pipeline
   - Add Semgrep scanning
   - Add gitleaks pre-commit hook

6. Add property-based security tests using proptest

7. Set up fuzzing for input parsing functions

---
```

---

## Appendix Section

```markdown
## Appendix

### A. Tools Used

| Tool | Version | Purpose |
|------|---------|---------|
| cargo-audit | 0.18.0 | Rust dependency audit |
| Semgrep | 1.45.0 | Static analysis |
| Gitleaks | 8.18.0 | Secrets detection |
| ShellCheck | 0.9.0 | Shell script analysis |

### B. Files Reviewed

- `src/api/*.rs` - API handlers
- `src/auth/*.rs` - Authentication logic
- `src/config.rs` - Configuration
- `Cargo.toml` - Dependencies

### C. Out of Scope

- Infrastructure security (AWS, networking)
- Runtime penetration testing
- Social engineering assessment

### D. Methodology

This audit followed:
- OWASP Testing Guide v4.2
- OWASP Top 10 2021
- CWE/SANS Top 25

### E. Glossary

- **CVSS:** Common Vulnerability Scoring System
- **CWE:** Common Weakness Enumeration
- **SAST:** Static Application Security Testing
- **SSRF:** Server-Side Request Forgery

---

**End of Report**
```

---

## Quick Start

Copy the sections above into a new file named `YYYY-MM-DD-SECURITY-AUDIT.md` and fill in the details for your specific audit.

Minimum required sections:
1. Header
2. Executive Summary
3. Findings Summary Table
4. Detailed Findings (at least for Critical/High)
5. Recommendations
