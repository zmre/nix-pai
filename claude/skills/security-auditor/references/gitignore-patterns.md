# .gitignore Security Patterns

This reference provides recommended .gitignore patterns to prevent accidental commit of sensitive files.

---

## Essential Patterns

These patterns should be in every project's .gitignore:

```gitignore
# Environment and secrets
.env
.env.*
.env.local
.env.*.local
!.env.example
!.env.template

# Credentials and keys
*.pem
*.key
*.p12
*.pfx
*.crt
*.cer
*.der
credentials.json
credentials.yaml
secrets.json
secrets.yaml
**/secret*
**/*secret*
*.secret

# API keys and tokens
api_key*
apikey*
token*
*_token
*_key
auth.json
oauth*.json

# SSH
id_rsa
id_ed25519
id_ecdsa
*.ppk
known_hosts

# AWS
.aws/
aws-credentials
.boto

# GCP
gcloud/
application_default_credentials.json
service-account*.json

# Azure
.azure/
azure-credentials

# Database
*.sqlite
*.db
*.sql
dump.sql
```

---

## IDE and Editor Patterns

```gitignore
# VS Code (settings may contain secrets)
.vscode/settings.json
.vscode/launch.json

# JetBrains
.idea/
*.iml

# Vim
*.swp
*.swo
*~

# Emacs
*~
\#*\#
.#*

# macOS
.DS_Store
.AppleDouble
.LSOverride
```

---

## Build and Runtime Patterns

```gitignore
# Build outputs
dist/
build/
out/
target/
*.egg-info/

# Dependencies (may contain local paths)
node_modules/
.venv/
venv/
__pycache__/

# Coverage and test artifacts
coverage/
.coverage
*.lcov
.nyc_output/

# Logs (may contain sensitive data)
*.log
logs/
npm-debug.log*
yarn-debug.log*
yarn-error.log*
```

---

## Language-Specific Patterns

### Rust

```gitignore
/target/
Cargo.lock  # Only for libraries, keep for binaries
**/*.rs.bk
```

### JavaScript/TypeScript

```gitignore
node_modules/
.npm
.yarn/
*.tsbuildinfo
.next/
.nuxt/
.output/
```

### Python

```gitignore
__pycache__/
*.py[cod]
*$py.class
.Python
.venv/
venv/
ENV/
.eggs/
*.egg
.mypy_cache/
.pytest_cache/
```

### Go

```gitignore
/vendor/
go.work
```

---

## Docker and Infrastructure

```gitignore
# Docker
.docker/
docker-compose.override.yml

# Terraform
.terraform/
*.tfstate
*.tfstate.*
*.tfvars
!*.tfvars.example

# Ansible
*.retry
vault_password
```

---

## Complete Recommended .gitignore

Copy this template for new projects:

```gitignore
# ===========================
# Secrets and Credentials
# ===========================
.env
.env.*
!.env.example
*.pem
*.key
*.p12
*.pfx
credentials.json
secrets.json
**/secret*
api_key*
token*

# ===========================
# Cloud Provider Credentials
# ===========================
.aws/
.gcloud/
.azure/
service-account*.json

# ===========================
# SSH Keys
# ===========================
id_rsa
id_ed25519
id_ecdsa
*.ppk

# ===========================
# IDE and Editor
# ===========================
.vscode/settings.json
.idea/
*.swp
*.swo
.DS_Store

# ===========================
# Build Outputs
# ===========================
dist/
build/
out/
target/

# ===========================
# Dependencies
# ===========================
node_modules/
.venv/
venv/
__pycache__/

# ===========================
# Logs and Artifacts
# ===========================
*.log
logs/
coverage/
.coverage

# ===========================
# Infrastructure
# ===========================
.terraform/
*.tfstate*
*.tfvars
!*.tfvars.example
```

---

## Verification Commands

### Check for Secrets in Git History

```bash
# Using gitleaks
nix shell nixpkgs#gitleaks -c gitleaks detect --source . --log-opts="--all"

# Using trufflehog
nix shell nixpkgs#trufflehog -c trufflehog git file://. --only-verified
```

### Check .gitignore Effectiveness

```bash
# List tracked files that match a pattern
git ls-files | grep -E "\.env|secret|key|credential"

# List untracked files that should be ignored
git status --porcelain | grep "^\?\?" | grep -E "\.env|secret|key"

# Test if a file would be ignored
git check-ignore -v path/to/file
```

### Fix Accidentally Committed Secrets

```bash
# Remove file from history (DESTRUCTIVE - requires force push)
git filter-branch --force --index-filter \
  "git rm --cached --ignore-unmatch path/to/secret" \
  --prune-empty --tag-name-filter cat -- --all

# Using BFG Repo-Cleaner (faster)
nix shell nixpkgs#bfg-repo-cleaner -c bfg --delete-files secret.key

# Then force push (COORDINATE WITH TEAM)
git push --force --all
```

---

## CI/CD Check

Add this check to CI:

```yaml
- name: Check for secrets in .gitignore
  run: |
    MISSING=""
    for pattern in ".env" "*.pem" "*.key" "credentials.json"; do
      if ! grep -q "$pattern" .gitignore; then
        MISSING="$MISSING $pattern"
      fi
    done
    if [ -n "$MISSING" ]; then
      echo "Missing patterns in .gitignore:$MISSING"
      exit 1
    fi
```

---

## Best Practices

1. **Add patterns before creating files** - Prevent accidents
2. **Use `.env.example`** - Document required variables without secrets
3. **Audit regularly** - Run gitleaks in CI
4. **Never commit then delete** - History retains the secret
5. **Rotate exposed secrets** - Assume compromised if ever committed
