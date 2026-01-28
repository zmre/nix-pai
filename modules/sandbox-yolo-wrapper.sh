#!/usr/bin/env bash
set -euo pipefail

# Environment setup
export PAI_DIR="@paiBasePath@"
export DA="@assistantName@"
export DA_COLOR="@assistantColor@"
export ENGINEER_NAME="${ENGINEER_NAME:-@userFullName@}"
export PATH="@paiBasePath@/bin:@paiEnvPath@:$PATH"
export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1

PLATFORM="$(uname -s)"
SANDBOX_HOME="/tmp/pai-sandbox-$$"
PROJECT_DIR="$PWD"
PROJECT_PARENT="$(dirname "$PROJECT_DIR")"
PRIVATE_MODE="false"
CCR_HOME=""

# Cleanup function (handles both sandbox home and CCR)
cleanup() {
    if [[ -n "$CCR_HOME" ]]; then
        HOME="$CCR_HOME" ccr stop 2>/dev/null || true
        rm -rf "$CCR_HOME" 2>/dev/null || true
    fi
    rm -rf "$SANDBOX_HOME" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

###########################################
# Private mode detection (same as main wrapper)
###########################################
detect_private_mode() {
    # Check if automatic privacy is enabled
    if [ "@automaticPrivacy@" = "false" ] || [ -z "@privateModel@" ]; then
        return 1
    fi

    # Check .agent-config.toml first
    if [ -f ".agent-config.toml" ]; then
        local private_val=$(grep -E "^private\s*=" .agent-config.toml 2>/dev/null | head -1 | sed 's/.*=\s*//' | tr -d ' "')
        case "$private_val" in
            true|True|TRUE|1)  return 0 ;;
            false|False|FALSE|0) return 1 ;;
        esac
    fi

    # Check LICENSE file
    for license_file in LICENSE LICENSE.md LICENSE.txt; do
        if [ -f "$license_file" ]; then
            local content=$(head -50 "$license_file" | tr '[:upper:]' '[:lower:]')
            if echo "$content" | grep -qE '(mit license|bsd|apache|gpl|lgpl|mozilla public|isc license|unlicense)'; then
                return 1  # OSS license = public mode
            fi
            break
        fi
    done

    # No config or license found - prompt user
    printf "No OSS license or .agent-config.toml detected. Start in private mode (routes to local ollama)? [y/N] "
    read -r answer
    case "$answer" in
        [yY]|[yY][eE][sS]) return 0 ;;
        *) return 1 ;;
    esac
}

###########################################
# Start CCR if private mode (OUTSIDE sandbox)
###########################################
setup_private_mode() {
    export ANTHROPIC_BASE_URL="http://127.0.0.1:3456"
    export ANTHROPIC_AUTH_TOKEN="private"
    export PAI_PRIVATE_MODE="true"
    export PAI_PRIVATE_MODEL="${PAI_PRIVATE_MODEL:-@privateModel@}"
    export DISABLE_PROMPT_CACHING=1
    PRIVATE_MODE="true"

    # Start CCR if not already running
    if ! curl -s http://127.0.0.1:3456/health >/dev/null 2>&1; then
        CCR_HOME="/tmp/pai-ccr-sandbox-$$"
        mkdir -p "$CCR_HOME/.claude-code-router"
        ln -sf "@paiBasePath@/.claude-code-router/config.json" "$CCR_HOME/.claude-code-router/config.json"
        touch "$CCR_HOME/.claude.json"
        HOME="$CCR_HOME" eval "$(ccr activate)"
        HOME="$CCR_HOME" ccr start &>/dev/null &
        sleep 2
    fi
}

# Detect and setup private mode (runs BEFORE sandbox)
if detect_private_mode; then
    setup_private_mode
fi

###########################################
# Create isolated sandbox home with Claude config
###########################################
mkdir -p "$SANDBOX_HOME/.claude"

# Get real home directory
REAL_HOME="${HOME:-$(eval echo ~)}"

# Extract OAuth credentials from macOS Keychain (BEFORE entering sandbox)
# Claude Code on macOS stores OAuth tokens in Keychain, not in files
# We extract and write to .credentials.json (Linux-style) for sandbox use
if [[ "$PLATFORM" == "Darwin" ]]; then
    CREDS=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null || true)
    if [ -n "$CREDS" ]; then
        echo "$CREDS" > "$SANDBOX_HOME/.claude/.credentials.json"
    else
        echo "Warning: Could not extract Claude credentials from Keychain"
        echo "Run 'claude' outside sandbox first to authenticate"
    fi
fi

# Copy .claude.json for config/preferences (not auth)
if [ -f "$REAL_HOME/.claude.json" ]; then
    cp "$REAL_HOME/.claude.json" "$SANDBOX_HOME/.claude.json"
fi

# Copy other .claude directory contents (settings, history, etc.)
if [ -d "$REAL_HOME/.claude" ]; then
    cp -R "$REAL_HOME/.claude/"* "$SANDBOX_HOME/.claude/" 2>/dev/null || true
fi

CLAUDE_CMD="@paiBasePath@/bin/claude"
CLAUDE_ARGS="--dangerously-skip-permissions --settings @paiBasePath@/claude/sandbox-settings.json --mcp-config @paiBasePath@/claude/mcp.json --plugin-dir @paiBasePath@/claude"

# Build environment variables to pass into sandbox
ENV_VARS="HOME=$SANDBOX_HOME PATH=@paiBasePath@/bin:@paiEnvPath@:\$PATH PAI_DIR=@paiBasePath@ DA=@assistantName@ PAI_SANDBOX_MODE=true"
if [[ "$PRIVATE_MODE" == "true" ]]; then
    ENV_VARS="$ENV_VARS ANTHROPIC_BASE_URL=$ANTHROPIC_BASE_URL ANTHROPIC_AUTH_TOKEN=$ANTHROPIC_AUTH_TOKEN PAI_PRIVATE_MODE=$PAI_PRIVATE_MODE PAI_PRIVATE_MODEL=$PAI_PRIVATE_MODEL DISABLE_PROMPT_CACHING=$DISABLE_PROMPT_CACHING"
fi

###########################################
# Run in platform-specific sandbox
###########################################
if [[ "$PLATFORM" == "Darwin" ]]; then
    # macOS: sandbox-exec with Seatbelt profile
    # Resolve symlinks (macOS /tmp -> /private/tmp, /var -> /private/var)
    RESOLVED_TMP=$(cd "$SANDBOX_HOME" && pwd -P)
    RESOLVED_PROJECT=$(cd "$PROJECT_DIR" && pwd -P)

    # Handle /tmp which may differ from TMPDIR
    SLASH_TMP="/private/tmp"
    if [ -d "/tmp" ]; then
        SLASH_TMP=$(cd /tmp && pwd -P)
    fi

    # Resolve parent directory path for monorepo support
    RESOLVED_PARENT="$(cd "$(dirname "$PROJECT_DIR")" && pwd -P)"

    # Build complete sandbox profile: base + dynamic rules
    SANDBOX_PROFILE="$(cat @paiBasePath@/claude/sandbox/macos.sbpl)

; === Dynamic rules (appended by wrapper) ===

; System paths (read-only) - required for binaries and libraries
(allow file-read*
    (literal \"/\")
    (subpath \"/System\")
    (subpath \"/usr\")
    (subpath \"/bin\")
    (subpath \"/sbin\")
    (subpath \"/Library\")
    (subpath \"/AppleInternal\")
    (subpath \"/private\")
    (subpath \"/var\")
    (subpath \"/tmp\")
    (subpath \"/etc\")
    (subpath \"/dev\")
    (subpath \"/opt\")
    (subpath \"/cores\")
    (subpath \"/Applications\")
    (subpath \"/Volumes\"))

; Nix store (read-only) - required for all nix dependencies
(allow file-read* (subpath \"/nix\"))

; PAI installation (read-only)
(allow file-read* (subpath \"@paiBasePath@\"))

; Project directory (read/write) - the main work area
(allow file-read* (subpath \"$RESOLVED_PROJECT\"))
(allow file-write* (subpath \"$RESOLVED_PROJECT\"))

; Parent directory (read-only) - for monorepo dependency access
(allow file-read* (subpath \"$RESOLVED_PARENT\"))

; Sandbox home (read/write) - isolated temporary home
(allow file-read* (subpath \"$RESOLVED_TMP\"))
(allow file-write* (subpath \"$RESOLVED_TMP\"))

; Temp directories (read/write)
(allow file-write* (subpath \"$SLASH_TMP\"))

; Allow file metadata operations broadly (needed by dyld, stat, etc.)
(allow file-read-metadata)

; Network access for Anthropic API and MCP servers
(allow network-outbound)
(allow network-inbound)
(allow system-socket)
"

    # Build env command with optional private mode variables
    ENV_CMD=(env
        HOME="$SANDBOX_HOME"
        PATH="@paiBasePath@/bin:@paiEnvPath@:$PATH"
        PAI_DIR="@paiBasePath@"
        DA="@assistantName@"
        PAI_SANDBOX_MODE="true"
    )

    if [[ "$PRIVATE_MODE" == "true" ]]; then
        ENV_CMD+=(
            ANTHROPIC_BASE_URL="$ANTHROPIC_BASE_URL"
            ANTHROPIC_AUTH_TOKEN="$ANTHROPIC_AUTH_TOKEN"
            PAI_PRIVATE_MODE="$PAI_PRIVATE_MODE"
            PAI_PRIVATE_MODEL="$PAI_PRIVATE_MODEL"
            DISABLE_PROMPT_CACHING="$DISABLE_PROMPT_CACHING"
        )
    fi

    /usr/bin/sandbox-exec \
        -p "$SANDBOX_PROFILE" \
        "${ENV_CMD[@]}" "$CLAUDE_CMD" $CLAUDE_ARGS "$@"
else
    # Linux: bubblewrap
    BWRAP_ARGS=(
        --die-with-parent
        --unshare-all
        --share-net
        --proc /proc
        --dev /dev
        --tmpfs /tmp
        --bind "$SANDBOX_HOME" "$HOME"
        --bind "$PROJECT_DIR" "$PROJECT_DIR"
        --ro-bind "$PROJECT_PARENT" "$PROJECT_PARENT"
        --ro-bind "@paiBasePath@" "@paiBasePath@"
        --ro-bind /nix /nix
        --ro-bind /usr /usr
        --ro-bind /bin /bin
        --ro-bind /etc /etc
        --setenv HOME "$SANDBOX_HOME"
        --setenv PATH "@paiBasePath@/bin:@paiEnvPath@:$PATH"
        --setenv PAI_DIR "@paiBasePath@"
        --setenv DA "@assistantName@"
        --setenv PAI_SANDBOX_MODE "true"
    )

    # Add lib paths if they exist
    [[ -d /lib ]] && BWRAP_ARGS+=(--ro-bind /lib /lib)
    [[ -d /lib64 ]] && BWRAP_ARGS+=(--ro-bind /lib64 /lib64)

    # Add private mode env vars if enabled
    if [[ "$PRIVATE_MODE" == "true" ]]; then
        BWRAP_ARGS+=(
            --setenv ANTHROPIC_BASE_URL "$ANTHROPIC_BASE_URL"
            --setenv ANTHROPIC_AUTH_TOKEN "$ANTHROPIC_AUTH_TOKEN"
            --setenv PAI_PRIVATE_MODE "$PAI_PRIVATE_MODE"
            --setenv PAI_PRIVATE_MODEL "$PAI_PRIVATE_MODEL"
            --setenv DISABLE_PROMPT_CACHING "$DISABLE_PROMPT_CACHING"
        )
    fi

    bwrap "${BWRAP_ARGS[@]}" -- "$CLAUDE_CMD" $CLAUDE_ARGS "$@"
fi
