#!/usr/bin/env bash
set -euo pipefail

# PAI Environment
export PAI_DIR="@paiBasePath@"
export DA="@assistantName@"
export DA_COLOR="@assistantColor@"
export ENGINEER_NAME="${ENGINEER_NAME:-@userFullName@}"
export PATH="@paiBasePath@/bin:@paiEnvPath@:$PATH"

# disable telemetry and udpate checks
export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1

CLAUDE_FLAGS="--settings @paiBasePath@/claude/settings.json --mcp-config @paiBasePath@/claude/mcp.json --plugin-dir @paiBasePath@/claude"

# This checks if the nix option automaticPrivacy is set and if not,
# just bypasses the CCR stuff and launches claude
if [ "@automaticPrivacy@" = "false" ] || [ -z "@privateModel@" ]; then
    if [ -z "@privateModel@" ]; then
        echo "No private model set in your config, can't run in private mode."
    fi
    exec claude $CLAUDE_FLAGS "$@"
fi

use_private_mode() {
    export ANTHROPIC_BASE_URL="http://127.0.0.1:3456"
    export ANTHROPIC_AUTH_TOKEN="private"
    export PAI_PRIVATE_MODE="true"
    # allow override with env var
    export PAI_PRIVATE_MODEL="${PAI_PRIVATE_MODEL:-@privateModel@}"
    export DISABLE_PROMPT_CACHING=1
    #export DISABLE_INTERLEAVED_THINKING=1
    #export CLAUDE_CODE_DISABLE_EXTENDED_THINKING=1

    local ccr_home=""

    # Start router if not already running
    if ! curl -s http://127.0.0.1:3456/health >/dev/null 2>&1; then
        # CCR needs writable HOME for PID/logs but config from nix store
        # Use /tmp with symlink to nix store config
        ccr_home="/tmp/pai-ccr-$$"
        #echo $ccr_home
        mkdir -p "$ccr_home/.claude-code-router"
        ln -sf "@paiBasePath@/.claude-code-router/config.json" "$ccr_home/.claude-code-router/config.json"
        touch "$ccr_home/.claude.json"
        HOME="$ccr_home" eval "$(ccr activate)"
        HOME="$ccr_home" ccr start &>/dev/null &
        sleep 2

        # Cleanup trap - stop CCR and remove temp dir when claude exits
        trap 'HOME="'"$ccr_home"'" ccr stop 2>/dev/null; rm -rf "'"$ccr_home"'"' EXIT
    fi

    claude $CLAUDE_FLAGS "$@"
    exit $?
}

use_normal_mode() {
    exec claude $CLAUDE_FLAGS "$@"
}

if [ -f ".agent-config.toml" ]; then
    private_val=$(grep -E "^private\s*=" .agent-config.toml 2>/dev/null | head -1 | sed 's/.*=\s*//' | tr -d ' "')
    case "$private_val" in
        true|True|TRUE|1)  use_private_mode "$@" ;;
        false|False|FALSE|0) use_normal_mode "$@" ;;
    esac
fi

for license_file in LICENSE LICENSE.md LICENSE.txt; do
    if [ -f "$license_file" ]; then
        content=$(head -50 "$license_file" | tr '[:upper:]' '[:lower:]')
        if echo "$content" | grep -qE '(mit license|bsd|apache|gpl|lgpl|mozilla public|isc license|unlicense)'; then
            use_normal_mode "$@"
        fi
        break
    fi
done

printf "No OSS license or .agent-config.toml detected. Start in private mode (routes to local ollama)? [y/N] "
read -r answer
case "$answer" in
    [yY]|[yY][eE][sS]) use_private_mode "$@" ;;
    *) use_normal_mode "$@" ;;
esac
