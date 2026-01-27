---
name: security-auditor
description: Comprehensive security audit skill for software repositories. Performs static analysis, dependency audits, SAST, fuzzing, and generates actionable markdown reports. Use when auditing code, reviewing security, finding vulnerabilities, or performing security assessments.
---

# Security Auditor Skill

## Activation Triggers

Use this skill when the user asks to:
- "audit this repo" / "security audit"
- "security review" / "review security"
- "find vulnerabilities" / "check for vulnerabilities"
- "dependency audit" / "check dependencies"
- "run security scan" / "security scan"
- "fuzz this code" / "set up fuzzing"
- "add property-based tests" / "security tests"

## Scope

**In Scope:**
- Static code analysis (SAST)
- Dependency vulnerability audits
- Secrets scanning
- Code pattern review (OWASP Top 10)
- Fuzzing setup and execution
- Property-based testing
- Security report generation

**Out of Scope:**
- Active penetration testing
- Network scanning
- Runtime/DAST testing
- Infrastructure security

## Quick Reference

### Language Detection

| Language | Detection | Audit Command |
|----------|-----------|---------------|
| Rust | `Cargo.toml` | `nix shell nixpkgs#cargo-audit -c cargo audit` |
| TypeScript/JS | `bun.lockb` | `nix shell nixpkgs#bun -c bun audit` |
| TypeScript/JS | `package-lock.json` | `nix shell nixpkgs#nodejs -c npm audit` |
| Python | `pyproject.toml` | `nix shell nixpkgs#python3Packages.pip-audit -c pip-audit` |
| Bash | `.sh` files | `nix shell nixpkgs#shellcheck -c shellcheck *.sh` |

### Static Analysis Tools

```bash
# Rust
nix develop -c cargo clippy -- -D warnings

# Python
nix shell nixpkgs#bandit -c bandit -r .

# All languages
nix shell nixpkgs#semgrep -c semgrep scan --config=auto .
```

### Secrets Scanning

```bash
nix shell nixpkgs#gitleaks -c gitleaks detect --source .
```

### Fuzzing (Rust)

```bash
# Initialize
nix shell nixpkgs#cargo-fuzz -c cargo fuzz init

# Run with time limit (2 minutes)
nix shell nixpkgs#cargo-fuzz -c cargo fuzz run <target> -- -max_total_time=120
```

## Core Workflow

1. **Detect** - Identify project type and languages
2. **Scan** - Run dependency audits and SAST tools
3. **Review** - Manual code review for vulnerability patterns
4. **Fuzz** - Set up and run fuzzing (if applicable)
5. **Test** - Add property-based security tests
6. **Report** - Generate actionable markdown report

## Report Output

Reports are saved as: `YYYY-MM-DD-SECURITY-AUDIT.md`

Sections:
1. Executive Summary
2. Findings Table (Critical/High/Medium/Low/Info)
3. Detailed Findings with CWE references
4. Automated Scan Results
5. Prioritized Recommendations
6. Appendix

## Detailed Documentation

For comprehensive methodology and guidance, see:
- [CLAUDE.md](./CLAUDE.md) - Full audit methodology
- [workflows/full-audit.md](./workflows/full-audit.md) - Complete audit checklist
- [workflows/dependency-audit.md](./workflows/dependency-audit.md) - Dependency scanning
- [workflows/fuzzing-workflow.md](./workflows/fuzzing-workflow.md) - Fuzzing setup
- [workflows/security-tests.md](./workflows/security-tests.md) - Property-based testing

## Integration Notes

- Uses Nix for all tool access (no global installs required)
- Integrates with IronCore language skills for Rust/TypeScript standards
- Reports designed to be actionable by both LLMs and humans
- All commands run in sandboxed Nix shells

## Example Usage

```
User: "Run a security audit on this Rust project"

1. Read CLAUDE.md for full methodology
2. Detect Cargo.toml presence
3. Run cargo audit, clippy, semgrep
4. Check for fuzzing targets
5. Review code for OWASP patterns
6. Generate YYYY-MM-DD-SECURITY-AUDIT.md
```
