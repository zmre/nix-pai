# Security Tests Workflow

This workflow covers property-based testing for security properties using proptest (Rust), fast-check (TypeScript/JavaScript), and hypothesis (Python).

## Overview

Property-based testing generates random inputs to verify that security invariants hold. Unlike unit tests with fixed inputs, property tests explore the input space automatically.

**Key Security Properties to Test:**
- No path traversal in sanitized paths
- No SQL injection in query builders
- No XSS in rendered output
- No command injection in shell commands
- Handles malformed/malicious input gracefully
- Cryptographic operations are constant-time
- Authentication always validates

---

## Rust with proptest

### Setup

Add to `Cargo.toml`:
```toml
[dev-dependencies]
proptest = "1.4"
```

### Basic Usage

```rust
use proptest::prelude::*;

proptest! {
    #[test]
    fn my_property(input in ".*") {
        // Property assertion
        assert!(some_invariant(&input));
    }
}
```

### Security Test Patterns

#### Path Traversal Prevention

```rust
use proptest::prelude::*;

proptest! {
    /// Sanitized paths must not contain path traversal sequences
    #[test]
    fn no_path_traversal(input in ".*") {
        let sanitized = sanitize_path(&input);

        // No parent directory traversal
        prop_assert!(!sanitized.contains(".."));

        // No absolute paths
        prop_assert!(!sanitized.starts_with('/'));
        prop_assert!(!sanitized.starts_with('\\'));

        // No null bytes
        prop_assert!(!sanitized.contains('\0'));
    }

    /// Path operations stay within allowed directory
    #[test]
    fn path_stays_in_bounds(
        base in "/tmp/allowed",
        user_input in ".*"
    ) {
        let resolved = resolve_path(&base, &user_input);
        if let Ok(path) = resolved {
            prop_assert!(path.starts_with(&base));
        }
    }
}
```

#### SQL Injection Prevention

```rust
proptest! {
    /// Query builder must parameterize all user input
    #[test]
    fn sql_injection_safe(user_input in ".*") {
        let query = build_query(&user_input);

        // No unescaped quotes
        prop_assert!(!query.contains("'") || query.contains("''"));

        // No comment sequences
        prop_assert!(!query.contains("--"));
        prop_assert!(!query.contains("/*"));

        // No statement terminators in middle
        prop_assert!(!query.contains("; "));
    }

    /// Prepared statement uses placeholders
    #[test]
    fn uses_prepared_statements(
        table in "[a-zA-Z_][a-zA-Z0-9_]*",
        value in ".*"
    ) {
        let (query, params) = prepare_query(&table, &value);

        // Query uses placeholder, not raw value
        prop_assert!(query.contains("?") || query.contains("$1"));

        // Value is in params, not query
        if !value.is_empty() {
            prop_assert!(params.contains(&value));
        }
    }
}
```

#### XSS Prevention

```rust
proptest! {
    /// HTML escaping must prevent script injection
    #[test]
    fn xss_safe(user_input in ".*") {
        let escaped = escape_html(&user_input);

        // No raw HTML tags
        prop_assert!(!escaped.contains('<'));
        prop_assert!(!escaped.contains('>'));

        // No raw quotes (for attribute context)
        prop_assert!(!escaped.contains('"'));

        // No JavaScript protocol
        prop_assert!(!escaped.to_lowercase().contains("javascript:"));
    }

    /// Template rendering escapes by default
    #[test]
    fn template_escapes_by_default(content in ".*") {
        let rendered = render_template("{{ content }}", &content);
        prop_assert!(!rendered.contains("<script"));
    }
}
```

#### Command Injection Prevention

```rust
proptest! {
    /// Shell command builder prevents injection
    #[test]
    fn command_injection_safe(filename in "[a-zA-Z0-9._-]*") {
        let cmd = build_command(&filename);

        // No shell metacharacters
        prop_assert!(!cmd.contains('|'));
        prop_assert!(!cmd.contains(';'));
        prop_assert!(!cmd.contains('`'));
        prop_assert!(!cmd.contains('$'));
        prop_assert!(!cmd.contains('&'));
    }

    /// Only allowlisted characters pass validation
    #[test]
    fn validates_shell_input(input in ".*") {
        match validate_shell_arg(&input) {
            Ok(valid) => {
                // Validated input is safe
                prop_assert!(valid.chars().all(|c| c.is_alphanumeric() || c == '_' || c == '-'));
            }
            Err(_) => {
                // Rejection is fine
            }
        }
    }
}
```

#### Authentication Invariants

```rust
proptest! {
    /// Password verification is consistent
    #[test]
    fn password_verification_consistent(password in ".{8,}") {
        let hash = hash_password(&password);

        // Correct password always verifies
        prop_assert!(verify_password(&password, &hash));

        // Modified password never verifies
        let wrong = format!("{}x", password);
        prop_assert!(!verify_password(&wrong, &hash));
    }

    /// Token validation rejects tampering
    #[test]
    fn token_tampering_detected(payload in ".*", key in ".{32}") {
        let token = sign_token(&payload, &key);

        // Valid token verifies
        prop_assert!(verify_token(&token, &key).is_ok());

        // Tampered token fails
        let tampered = format!("{}x", token);
        prop_assert!(verify_token(&tampered, &key).is_err());
    }
}
```

#### Input Validation

```rust
proptest! {
    /// Email validation rejects invalid formats
    #[test]
    fn email_validation(input in ".*") {
        if validate_email(&input).is_ok() {
            // Valid emails must have @ and domain
            prop_assert!(input.contains('@'));
            prop_assert!(input.split('@').last().unwrap().contains('.'));
        }
    }

    /// URL validation prevents SSRF
    #[test]
    fn url_validation_prevents_ssrf(input in ".*") {
        if let Ok(url) = validate_external_url(&input) {
            // No internal addresses
            prop_assert!(!url.host().contains("localhost"));
            prop_assert!(!url.host().contains("127."));
            prop_assert!(!url.host().contains("10."));
            prop_assert!(!url.host().contains("192.168."));
        }
    }
}
```

### Running proptest

```bash
# Run all tests including property tests
cargo test

# Run with more iterations
PROPTEST_CASES=10000 cargo test

# Run specific property test
cargo test no_path_traversal

# Show shrunk failure case
PROPTEST_VERBOSE=1 cargo test
```

---

## TypeScript/JavaScript with fast-check

### Setup

```bash
# With bun
bun add -D fast-check

# With npm
npm install --save-dev fast-check
```

### Basic Usage

```typescript
import fc from 'fast-check';

describe('Security Properties', () => {
  it('satisfies property', () => {
    fc.assert(
      fc.property(fc.string(), (input) => {
        return someInvariant(input);
      })
    );
  });
});
```

### Security Test Patterns

#### Path Traversal Prevention

```typescript
import fc from 'fast-check';

describe('Path Security', () => {
  it('sanitized paths have no traversal', () => {
    fc.assert(
      fc.property(fc.string(), (input) => {
        const sanitized = sanitizePath(input);

        // No parent traversal
        expect(sanitized).not.toContain('..');

        // No absolute paths
        expect(sanitized).not.toMatch(/^[/\\]/);

        // No null bytes
        expect(sanitized).not.toContain('\0');
      })
    );
  });

  it('resolved paths stay in bounds', () => {
    fc.assert(
      fc.property(fc.string(), (userPath) => {
        const base = '/allowed/directory';
        const resolved = resolvePath(base, userPath);

        if (resolved !== null) {
          expect(resolved.startsWith(base)).toBe(true);
        }
      })
    );
  });
});
```

#### SQL Injection Prevention

```typescript
describe('SQL Security', () => {
  it('query builder prevents injection', () => {
    fc.assert(
      fc.property(fc.string(), (userInput) => {
        const query = buildQuery(userInput);

        // No SQL comments
        expect(query).not.toContain('--');
        expect(query).not.toContain('/*');

        // No statement breaks
        expect(query).not.toMatch(/;\s*\w/);
      })
    );
  });

  it('uses parameterized queries', () => {
    fc.assert(
      fc.property(
        fc.string(),
        fc.string(),
        (table, value) => {
          const { query, params } = prepareQuery(table, value);

          // Uses placeholders
          expect(query).toMatch(/\$\d+|\?/);

          // Value in params, not query
          if (value.length > 0) {
            expect(params).toContain(value);
          }
        }
      )
    );
  });
});
```

#### XSS Prevention

```typescript
describe('XSS Prevention', () => {
  it('escapes HTML entities', () => {
    fc.assert(
      fc.property(fc.string(), (input) => {
        const escaped = escapeHtml(input);

        expect(escaped).not.toContain('<');
        expect(escaped).not.toContain('>');
        expect(escaped).not.toContain('"');
        expect(escaped).not.toContain("'");
      })
    );
  });

  it('prevents script injection', () => {
    fc.assert(
      fc.property(fc.string(), (input) => {
        const rendered = renderUserContent(input);

        expect(rendered.toLowerCase()).not.toContain('<script');
        expect(rendered.toLowerCase()).not.toContain('javascript:');
        expect(rendered.toLowerCase()).not.toContain('onerror=');
      })
    );
  });
});
```

#### Unicode Edge Cases

```typescript
describe('Unicode Handling', () => {
  it('handles full unicode safely', () => {
    fc.assert(
      fc.property(fc.fullUnicodeString(), (input) => {
        // Should not throw
        const result = processInput(input);
        expect(typeof result).toBe('string');
      })
    );
  });

  it('normalizes unicode consistently', () => {
    fc.assert(
      fc.property(fc.fullUnicodeString(), (input) => {
        const norm1 = normalizeInput(input);
        const norm2 = normalizeInput(norm1);

        // Normalization is idempotent
        expect(norm1).toBe(norm2);
      })
    );
  });
});
```

### Running fast-check

```bash
# With Jest
npx jest --testPathPattern=security

# With Vitest
npx vitest run --testPathPattern=security

# With Bun
bun test security
```

### Configuration

```typescript
// Increase iterations for thorough testing
fc.assert(
  fc.property(fc.string(), (input) => {
    // ...
  }),
  { numRuns: 10000 }
);

// Set seed for reproducibility
fc.assert(
  fc.property(fc.string(), (input) => {
    // ...
  }),
  { seed: 12345 }
);
```

---

## Python with hypothesis

### Setup

```bash
# With pip
pip install hypothesis

# With uv
uv add --dev hypothesis
```

### Basic Usage

```python
from hypothesis import given, strategies as st

@given(st.text())
def test_my_property(input_str):
    assert some_invariant(input_str)
```

### Security Test Patterns

#### Path Traversal Prevention

```python
from hypothesis import given, strategies as st
import pytest

class TestPathSecurity:
    @given(st.text())
    def test_no_path_traversal(self, user_input):
        sanitized = sanitize_path(user_input)

        # No parent traversal
        assert '..' not in sanitized

        # No absolute paths
        assert not sanitized.startswith('/')
        assert not sanitized.startswith('\\')

        # No null bytes
        assert '\0' not in sanitized

    @given(st.text())
    def test_path_stays_in_bounds(self, user_path):
        base = '/allowed/directory'
        resolved = resolve_path(base, user_path)

        if resolved is not None:
            assert resolved.startswith(base)
```

#### SQL Injection Prevention

```python
class TestSQLSecurity:
    @given(st.text())
    def test_query_builder_safe(self, user_input):
        query = build_query(user_input)

        # No SQL comments
        assert '--' not in query
        assert '/*' not in query

        # No statement separators (dangerous)
        assert '; ' not in query

    @given(st.text(), st.text())
    def test_uses_parameters(self, table, value):
        query, params = prepare_query(table, value)

        # Uses placeholders
        assert '%s' in query or '?' in query

        # Value in params
        if value:
            assert value in params
```

#### XSS Prevention

```python
class TestXSSPrevention:
    @given(st.text())
    def test_html_escaping(self, user_input):
        escaped = escape_html(user_input)

        assert '<' not in escaped
        assert '>' not in escaped
        assert '"' not in escaped

    @given(st.text())
    def test_template_escaping(self, content):
        rendered = render_template('{{ content }}', content=content)

        assert '<script' not in rendered.lower()
        assert 'javascript:' not in rendered.lower()
```

#### Cryptographic Properties

```python
from hypothesis import given, strategies as st, settings, Phase

class TestCrypto:
    @given(st.binary(min_size=1, max_size=1000))
    def test_encryption_roundtrip(self, plaintext):
        key = generate_key()
        ciphertext = encrypt(plaintext, key)
        decrypted = decrypt(ciphertext, key)

        assert decrypted == plaintext

    @given(st.text(min_size=8))
    def test_password_hashing(self, password):
        hash1 = hash_password(password)
        hash2 = hash_password(password)

        # Different salts produce different hashes
        assert hash1 != hash2

        # Both verify correctly
        assert verify_password(password, hash1)
        assert verify_password(password, hash2)

    @given(st.binary(), st.binary(min_size=32, max_size=32))
    def test_signature_verification(self, data, key):
        signature = sign(data, key)

        # Valid signature verifies
        assert verify(data, signature, key)

        # Tampered data fails
        tampered = data + b'x'
        assert not verify(tampered, signature, key)
```

### Running hypothesis

```bash
# Run with pytest
pytest tests/test_security.py

# Run with verbose output
pytest tests/test_security.py -v

# Run with more examples
pytest tests/test_security.py --hypothesis-seed=0

# Profile test performance
pytest tests/test_security.py --hypothesis-show-statistics
```

### Configuration

```python
from hypothesis import settings, Phase

# Increase examples for thorough testing
@settings(max_examples=1000)
@given(st.text())
def test_thorough(input_str):
    pass

# Disable shrinking for performance
@settings(phases=[Phase.generate])
@given(st.text())
def test_no_shrink(input_str):
    pass

# Set deadline for timing-sensitive tests
@settings(deadline=1000)  # 1 second
@given(st.text())
def test_with_deadline(input_str):
    pass
```

---

## CI Integration

### GitHub Actions

```yaml
name: Security Tests
on: [push, pull_request]

jobs:
  security-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      # Rust
      - name: Rust Property Tests
        if: hashFiles('Cargo.toml') != ''
        run: |
          PROPTEST_CASES=1000 cargo test security

      # TypeScript
      - name: TypeScript Property Tests
        if: hashFiles('package.json') != ''
        run: |
          npm test -- --testPathPattern=security

      # Python
      - name: Python Property Tests
        if: hashFiles('pyproject.toml') != ''
        run: |
          pytest tests/test_security.py --hypothesis-seed=0
```

---

## Quick Reference

```bash
# Rust (proptest)
PROPTEST_CASES=10000 cargo test security

# TypeScript (fast-check)
npx jest --testPathPattern=security

# Python (hypothesis)
pytest tests/test_security.py -v
```
