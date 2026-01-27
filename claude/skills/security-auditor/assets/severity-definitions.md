# Severity Definitions

This document defines severity levels for security findings based on CVSS scoring and practical impact assessment.

---

## Severity Levels

### Critical (CVSS 9.0 - 10.0)

**Definition:** Vulnerabilities that can be exploited remotely without authentication and lead to complete system compromise.

**Characteristics:**
- Remote code execution
- Authentication bypass
- Complete data breach possible
- No user interaction required
- Easily exploitable

**Examples:**
- SQL injection allowing data extraction
- Unauthenticated API with admin access
- Hardcoded credentials for production systems
- Remote code execution via deserialization

**Response Time:** Immediate (within hours)

**Actions:**
- Stop deployment of affected code
- Apply emergency patch
- Notify stakeholders
- Activate incident response if exploited

---

### High (CVSS 7.0 - 8.9)

**Definition:** Vulnerabilities that have significant impact but may require specific conditions or limited authentication.

**Characteristics:**
- Significant data exposure
- Privilege escalation
- May require low-level authentication
- Limited user interaction
- Exploitation reasonably straightforward

**Examples:**
- IDOR allowing access to other users' data
- Stored XSS in admin panel
- Broken access control on sensitive endpoints
- Weak password hashing (MD5, SHA1)

**Response Time:** 24-48 hours

**Actions:**
- Prioritize fix in current sprint
- Review for active exploitation
- Consider temporary mitigations

---

### Medium (CVSS 4.0 - 6.9)

**Definition:** Vulnerabilities with moderate impact or requiring significant preconditions for exploitation.

**Characteristics:**
- Limited data exposure
- Requires specific conditions
- May need victim interaction
- Impact contained to subset of users

**Examples:**
- Reflected XSS requiring social engineering
- CSRF on non-critical actions
- Information disclosure (stack traces, version info)
- Missing rate limiting on non-auth endpoints

**Response Time:** 1-2 weeks

**Actions:**
- Schedule fix in upcoming sprint
- Document compensating controls
- Monitor for exploitation attempts

---

### Low (CVSS 0.1 - 3.9)

**Definition:** Minor issues with limited security impact, often defense-in-depth improvements.

**Characteristics:**
- Minimal direct impact
- Requires unlikely conditions
- Defense-in-depth concern
- No direct exploitation path

**Examples:**
- Missing security headers (CSP, HSTS)
- Debug information in responses
- Clickjacking on non-sensitive pages
- Outdated dependencies with no known exploit

**Response Time:** Next release cycle

**Actions:**
- Add to backlog
- Fix when touching related code
- Consider in architectural reviews

---

### Informational (CVSS 0.0)

**Definition:** Observations that don't represent vulnerabilities but suggest hardening opportunities.

**Characteristics:**
- No exploitation path
- Best practice recommendations
- Code quality concerns
- Future-proofing suggestions

**Examples:**
- Recommend using constant-time comparison
- Suggest input validation improvements
- Note missing logging for security events
- Recommend security documentation

**Response Time:** Best effort

**Actions:**
- Document for future reference
- Consider in design reviews
- No immediate action required

---

## CVSS Scoring Quick Reference

The Common Vulnerability Scoring System (CVSS) provides a standardized way to assess vulnerability severity.

### Attack Vector (AV)

| Value | Description | Score Impact |
|-------|-------------|--------------|
| Network (N) | Remotely exploitable | Higher |
| Adjacent (A) | Requires network proximity | Medium |
| Local (L) | Requires local access | Lower |
| Physical (P) | Requires physical access | Lowest |

### Attack Complexity (AC)

| Value | Description | Score Impact |
|-------|-------------|--------------|
| Low (L) | No special conditions | Higher |
| High (H) | Requires specific conditions | Lower |

### Privileges Required (PR)

| Value | Description | Score Impact |
|-------|-------------|--------------|
| None (N) | No authentication needed | Higher |
| Low (L) | Basic user privileges | Medium |
| High (H) | Admin privileges needed | Lower |

### User Interaction (UI)

| Value | Description | Score Impact |
|-------|-------------|--------------|
| None (N) | No user action required | Higher |
| Required (R) | Victim must perform action | Lower |

### Impact (CIA Triad)

Each rated: None (N), Low (L), High (H)

- **Confidentiality (C):** Data disclosure impact
- **Integrity (I):** Data modification impact
- **Availability (A):** Service disruption impact

### Quick CVSS Examples

| Scenario | Score | Severity |
|----------|-------|----------|
| Remote SQLi, no auth, full DB access | 9.8 | Critical |
| Auth bypass requiring valid session | 8.1 | High |
| XSS requiring user click | 6.1 | Medium |
| Information leak in error message | 3.7 | Low |

---

## Decision Matrix

Use this matrix when CVSS alone isn't sufficient:

| Factor | Increases Severity | Decreases Severity |
|--------|-------------------|-------------------|
| Exploitability | Public exploit exists | Complex, theoretical |
| Data Sensitivity | PII, credentials, financial | Public information |
| User Base | All users affected | Limited subset |
| Attack Surface | Internet-exposed | Internal only |
| Business Impact | Revenue, reputation | Minor inconvenience |

---

## Response Timeline Summary

| Severity | Response Time | Fix Timeline |
|----------|--------------|--------------|
| Critical | Immediate | Hours |
| High | 24-48 hours | Days |
| Medium | 1-2 weeks | Sprint |
| Low | Next release | Month |
| Info | Best effort | Backlog |

---

## Documentation Requirements

Each severity level requires different documentation:

### Critical/High
- Full finding details
- Proof of concept
- Remediation steps
- Verification test
- Stakeholder notification

### Medium
- Finding details
- Impact description
- Remediation guidance

### Low/Info
- Brief description
- Recommendation
