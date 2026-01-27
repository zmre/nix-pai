# Fuzzing Workflow

This workflow covers setting up and running fuzz testing for security vulnerabilities.

## Overview

Fuzzing is an automated testing technique that generates random inputs to find crashes, hangs, and security vulnerabilities. It's particularly effective for:

- Input parsing code
- File format parsers
- Protocol handlers
- Deserialization logic
- Any code that processes untrusted input

## Rust Fuzzing with cargo-fuzz

### Prerequisites

cargo-fuzz requires nightly Rust. The Nix shell handles this automatically.

### Initial Setup

```bash
# Initialize fuzzing infrastructure
nix shell nixpkgs#cargo-fuzz -c cargo fuzz init
```

This creates:
```
fuzz/
├── Cargo.toml
└── fuzz_targets/
    └── (empty, add targets here)
```

### Creating Fuzz Targets

#### 1. Add a New Target

```bash
nix shell nixpkgs#cargo-fuzz -c cargo fuzz add parse_input
```

#### 2. Write the Fuzz Target

Edit `fuzz/fuzz_targets/parse_input.rs`:

```rust
#![no_main]
use libfuzzer_sys::fuzz_target;
use my_crate::parse_input;

fuzz_target!(|data: &[u8]| {
    // Option 1: Raw bytes
    let _ = parse_input(data);

    // Option 2: UTF-8 string (common for text parsing)
    if let Ok(s) = std::str::from_utf8(data) {
        let _ = parse_input(s);
    }

    // Option 3: Structured input with arbitrary
    // (requires adding arbitrary = "1" to fuzz/Cargo.toml)
});
```

#### 3. Structured Fuzzing with Arbitrary

Add to `fuzz/Cargo.toml`:
```toml
[dependencies]
arbitrary = { version = "1", features = ["derive"] }
```

Create structured input:
```rust
#![no_main]
use libfuzzer_sys::fuzz_target;
use arbitrary::Arbitrary;

#[derive(Arbitrary, Debug)]
struct FuzzInput {
    name: String,
    count: u32,
    flags: Vec<bool>,
}

fuzz_target!(|input: FuzzInput| {
    let _ = my_crate::process(input.name, input.count, input.flags);
});
```

### Running the Fuzzer

#### Basic Run

```bash
# Run indefinitely (Ctrl+C to stop)
nix shell nixpkgs#cargo-fuzz -c cargo fuzz run parse_input
```

#### Time-Limited Run

```bash
# Run for 2 minutes
nix shell nixpkgs#cargo-fuzz -c cargo fuzz run parse_input -- -max_total_time=120

# Run for 30 seconds (quick CI check)
nix shell nixpkgs#cargo-fuzz -c cargo fuzz run parse_input -- -max_total_time=30
```

#### Resource-Limited Run

```bash
# Memory limit (2GB)
nix shell nixpkgs#cargo-fuzz -c cargo fuzz run parse_input -- -rss_limit_mb=2048

# Combined limits
nix shell nixpkgs#cargo-fuzz -c cargo fuzz run parse_input -- -max_total_time=120 -rss_limit_mb=2048
```

#### Parallel Fuzzing

```bash
# Use 4 parallel jobs
nix shell nixpkgs#cargo-fuzz -c cargo fuzz run parse_input -- -jobs=4 -workers=4
```

### Analyzing Results

#### List Existing Targets

```bash
nix shell nixpkgs#cargo-fuzz -c cargo fuzz list
```

#### Check for Crashes

```bash
# Crashes are saved here
ls fuzz/artifacts/parse_input/

# Typical crash filename
# crash-da39a3ee5e6b4b0d3255bfef95601890afd80709
```

#### Minimize Crash Cases

```bash
# Minimize a crash to smallest reproducing input
nix shell nixpkgs#cargo-fuzz -c cargo fuzz tmin parse_input fuzz/artifacts/parse_input/crash-xxx
```

#### Reproduce a Crash

```bash
# Run target with specific input
nix shell nixpkgs#cargo-fuzz -c cargo fuzz run parse_input fuzz/artifacts/parse_input/crash-xxx
```

### Effective Fuzz Target Patterns

#### Pattern 1: String Parser

```rust
fuzz_target!(|data: &[u8]| {
    if let Ok(s) = std::str::from_utf8(data) {
        // Limit input size to avoid timeouts
        if s.len() < 10000 {
            let _ = parse_config(s);
        }
    }
});
```

#### Pattern 2: Binary Format Parser

```rust
fuzz_target!(|data: &[u8]| {
    // Provide minimum required bytes
    if data.len() >= 4 {
        let _ = parse_header(data);
    }
});
```

#### Pattern 3: API Function

```rust
use arbitrary::Arbitrary;

#[derive(Arbitrary, Debug)]
struct ApiInput {
    endpoint: String,
    params: Vec<(String, String)>,
}

fuzz_target!(|input: ApiInput| {
    let _ = handle_request(&input.endpoint, &input.params);
});
```

#### Pattern 4: Stateful Fuzzing

```rust
fuzz_target!(|operations: Vec<Operation>| {
    let mut state = State::new();
    for op in operations.iter().take(100) {  // Limit operations
        let _ = state.apply(op);
    }
});
```

### Coverage-Guided Tips

1. **Start with good seeds**
   ```bash
   # Add seed corpus
   mkdir -p fuzz/corpus/parse_input
   echo "valid input" > fuzz/corpus/parse_input/seed1
   ```

2. **Check coverage**
   ```bash
   nix shell nixpkgs#cargo-fuzz -c cargo fuzz coverage parse_input
   ```

3. **Merge corpora**
   ```bash
   nix shell nixpkgs#cargo-fuzz -c cargo fuzz cmin parse_input
   ```

---

## Python Fuzzing with Atheris

### Setup

Create a fuzz target file:

```python
#!/usr/bin/env python3
# fuzz_parse_input.py

import atheris
import sys

# Instrument imports for coverage
with atheris.instrument_imports():
    from my_module import parse_input

def test_one_input(data):
    """Fuzz target function."""
    try:
        fdp = atheris.FuzzedDataProvider(data)

        # Generate string input
        input_str = fdp.ConsumeUnicodeNoSurrogates(1000)
        parse_input(input_str)

    except ValueError:
        pass  # Expected for invalid input
    except UnicodeDecodeError:
        pass  # Expected for bad encoding

if __name__ == "__main__":
    atheris.Setup(sys.argv, test_one_input)
    atheris.Fuzz()
```

### Running

```bash
# Basic run
nix shell nixpkgs#python3Packages.atheris -c python fuzz_parse_input.py

# Time-limited
nix shell nixpkgs#python3Packages.atheris -c python fuzz_parse_input.py -max_total_time=120

# With corpus directory
mkdir -p corpus
nix shell nixpkgs#python3Packages.atheris -c python fuzz_parse_input.py corpus/
```

### FuzzedDataProvider Methods

```python
fdp = atheris.FuzzedDataProvider(data)

# Strings
fdp.ConsumeString(max_length)
fdp.ConsumeUnicodeNoSurrogates(max_length)

# Numbers
fdp.ConsumeInt(num_bytes)
fdp.ConsumeUInt(num_bytes)
fdp.ConsumeFloat()
fdp.ConsumeIntInRange(min, max)

# Bytes
fdp.ConsumeBytes(max_length)
fdp.ConsumeRemainingBytes()

# Boolean
fdp.ConsumeBool()
```

### Effective Python Fuzz Targets

#### Pattern 1: JSON Parser

```python
def test_one_input(data):
    fdp = atheris.FuzzedDataProvider(data)
    json_str = fdp.ConsumeUnicodeNoSurrogates(10000)
    try:
        parsed = json.loads(json_str)
        my_module.process_config(parsed)
    except json.JSONDecodeError:
        pass
```

#### Pattern 2: Binary Parser

```python
def test_one_input(data):
    if len(data) < 4:
        return
    try:
        my_module.parse_binary(data)
    except ValueError:
        pass
```

---

## JavaScript/TypeScript Fuzzing

### Using jsfuzz

```bash
# Install
nix shell nixpkgs#nodejs -c npm install -g jsfuzz

# Create fuzz target
# fuzz.js
module.exports.fuzz = function(data) {
    const str = data.toString('utf8');
    parseInput(str);
};

# Run
jsfuzz fuzz.js
```

### Using Jazzer.js

```javascript
// fuzz.js
const { fuzzer } = require('@aspect/jazzer');

fuzzer.fuzzerTestOneInput = function(data) {
    const str = new TextDecoder().decode(data);
    try {
        parseInput(str);
    } catch (e) {
        if (e.message.includes('expected')) {
            return;  // Expected error
        }
        throw e;  // Unexpected error
    }
};
```

### Recommendation

For JavaScript/TypeScript, property-based testing with fast-check is often more practical than coverage-guided fuzzing. See `security-tests.md`.

---

## Interpreting Fuzzing Results

### Types of Findings

1. **Crashes (SEGFAULT, abort)**
   - Severity: Usually High/Critical
   - Memory corruption, null pointer dereference
   - Requires immediate fix

2. **Timeouts**
   - Severity: Medium (DoS potential)
   - Algorithm complexity issues
   - Regular expression catastrophic backtracking

3. **Memory Leaks**
   - Severity: Low to Medium
   - Resource exhaustion over time

4. **Assertion Failures**
   - Severity: Varies
   - Logic errors, invariant violations

### Creating Reproducers

For each crash, create a test case:

```rust
#[test]
fn test_crash_001() {
    // Minimized crash input
    let input = b"\x00\xff\x00\x00";
    let result = parse_input(input);
    assert!(result.is_err());
}
```

### CI Integration

```yaml
# GitHub Actions
- name: Fuzz Test
  run: |
    nix shell nixpkgs#cargo-fuzz -c cargo fuzz run parse_input -- -max_total_time=60
  continue-on-error: false
```

---

## Quick Reference

```bash
# Rust - Initialize
nix shell nixpkgs#cargo-fuzz -c cargo fuzz init

# Rust - Add target
nix shell nixpkgs#cargo-fuzz -c cargo fuzz add target_name

# Rust - Run (2 min)
nix shell nixpkgs#cargo-fuzz -c cargo fuzz run target_name -- -max_total_time=120

# Rust - Minimize crash
nix shell nixpkgs#cargo-fuzz -c cargo fuzz tmin target_name fuzz/artifacts/target_name/crash-xxx

# Python - Run
nix shell nixpkgs#python3Packages.atheris -c python fuzz_target.py -max_total_time=120
```
