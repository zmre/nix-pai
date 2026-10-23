#!/usr/bin/env bash
set -euo pipefail

# Environment setup
export PAI_DIR="@paiBasePath@"
export DA="@assistantName@"
export DA_COLOR="@assistantColor@"
export ENGINEER_NAME="${ENGINEER_NAME:-@userFullName@}"
export PATH="@paiBasePath@/bin:@paiEnvPath@:/run/current-system/sw/bin:$PATH"
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
        local private_val=$(grep -E "^private[[:space:]]*=" .agent-config.toml 2>/dev/null | head -1 | sed 's/.*=[[:space:]]*//' | tr -d ' "')
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

###########################################
# User-configured sandbox paths and env (pai.sandboxYolo.* options)
###########################################
# Defines PAI_SANDBOX_{RW,RO,DENY,COPY}_PATHS and PAI_SANDBOX_ENV_{NAMES,CMDS}.
# Arrays may be empty; expand with ${a[@]+"${a[@]}"} so bash 3.2 + set -u copes.
source "@paiBasePath@/claude/sandbox/config.sh"

# ~ or ~/x -> real home path; anything else unchanged
expand_path() {
    case "$1" in
        "~") printf '%s\n' "$REAL_HOME" ;;
        "~/"*) printf '%s\n' "$REAL_HOME/${1:2}" ;;
        *) printf '%s\n' "$1" ;;
    esac
}

# Follow symlinks on the final component until a non-link remains
follow_links() {
    local p="$1" t
    while [[ -L "$p" ]]; do
        t="$(readlink "$p")"
        case "$t" in
            /*) p="$t" ;;
            *) p="$(dirname "$p")/$t" ;;
        esac
    done
    printf '%s\n' "$p"
}

# Resolve directory symlinks (/tmp -> /private/tmp); missing paths unchanged
resolve_path() {
    local p="$1"
    if [[ -d "$p" ]]; then
        (cd "$p" && pwd -P)
    elif [[ -d "$(dirname "$p")" ]]; then
        printf '%s/%s\n' "$(cd "$(dirname "$p")" && pwd -P)" "$(basename "$p")"
    else
        printf '%s\n' "$p"
    fi
}

# Path relative to the real home, or failure if not under it (or escapes via ..)
home_rel() {
    case "$1" in
        *"/.."*) return 1 ;;
        "$REAL_HOME"/?*) printf '%s\n' "${1#"$REAL_HOME"/}" ;;
        *) return 1 ;;
    esac
}

# True if $1 is $2 or lies beneath it
is_under() {
    [[ "$1" == "$2" || "$1" == "$2"/* ]]
}

# Copy selected files/dirs from the real home into the sandbox home. Runs
# after the git/direnv copies (so user entries override them) and before the
# .claude copy and Keychain step (so Claude auth can't be clobbered).
copy_from_home() {
    local entry src rel dest
    for entry in ${PAI_SANDBOX_COPY_PATHS[@]+"${PAI_SANDBOX_COPY_PATHS[@]}"}; do
        src="$(expand_path "$entry")"
        if ! rel="$(home_rel "$src")"; then
            echo "Warning: sandbox copyFromHome: $entry is not under home, skipping" >&2
            continue
        fi
        if [[ ! -e "$src" ]]; then
            echo "Warning: sandbox copyFromHome: $entry not found, skipping" >&2
            continue
        fi
        dest="$SANDBOX_HOME/$rel"
        mkdir -p "$(dirname "$dest")"
        rm -rf "$dest"
        cp -RL "$src" "$dest" || echo "Warning: sandbox copyFromHome: failed to copy $entry" >&2
    done
}

# Run envFromCommands outside the sandbox; collect successful results
EXTRA_ENV_NAMES=()
EXTRA_ENV_VALUES=()
collect_env_from_commands() {
    local i=0 name cmd value
    while [[ $i -lt ${#PAI_SANDBOX_ENV_NAMES[@]} ]]; do
        name="${PAI_SANDBOX_ENV_NAMES[$i]}"
        cmd="${PAI_SANDBOX_ENV_CMDS[$i]}"
        i=$((i + 1))
        if value="$(bash -c "$cmd")" && [[ -n "$value" ]]; then
            EXTRA_ENV_NAMES+=("$name")
            EXTRA_ENV_VALUES+=("$value")
        else
            echo "Warning: sandbox envFromCommands: '$cmd' failed or was empty, $name not set" >&2
        fi
    done
}
collect_env_from_commands

# Copy .claude.json for config/preferences (not auth)
if [ -f "$REAL_HOME/.claude.json" ]; then
    cp "$REAL_HOME/.claude.json" "$SANDBOX_HOME/.claude.json"
fi

if [ -f "$REAL_HOME/.config/git/config" ]; then
  mkdir -p "$SANDBOX_HOME/.config/git"
  cat "$REAL_HOME/.config/git/config" | grep -E '(\[user\]|email =|name =)' > "$SANDBOX_HOME/.config/git/config"
fi

if [ -d "$REAL_HOME/.config/direnv/lib" ]; then
  mkdir -p "$SANDBOX_HOME/.config/direnv/"
  cp -R "$REAL_HOME/.config/direnv/lib" "$SANDBOX_HOME/.config/direnv/"
fi

copy_from_home

# Copy .claude directory contents (settings, history, and on Linux the
# .credentials.json OAuth file). The trailing /. form copies hidden files
# too — a plain * glob misses .credentials.json and forces re-login.
if [ -d "$REAL_HOME/.claude" ]; then
    cp -R "$REAL_HOME/.claude/." "$SANDBOX_HOME/.claude/" 2>/dev/null || true
fi

# macOS: OAuth tokens live in the Keychain, not a file. Extract them and
# write .credentials.json so the sandboxed Claude can authenticate. This
# runs after the directory copy so it overrides any stale file there.
if [[ "$PLATFORM" == "Darwin" ]]; then
    CREDS=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null || true)
    if [ -n "$CREDS" ]; then
        echo "$CREDS" > "$SANDBOX_HOME/.claude/.credentials.json"
    else
        echo "Warning: Could not extract Claude credentials from Keychain"
        echo "Run 'claude' outside sandbox first to authenticate"
    fi
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

    DUDIR="$(cd "$(dirname "$(getconf DARWIN_USER_CACHE_DIR)")" && pwd -P)"   # /var/folders/0x/sppmy…

    # Handle /tmp which may differ from TMPDIR
    SLASH_TMP="/private/tmp"
    if [ -d "/tmp" ]; then
        SLASH_TMP=$(cd /tmp && pwd -P)
    fi

    # Resolve parent directory path for monorepo support
    RESOLVED_PARENT="$(cd "$(dirname "$PROJECT_DIR")" && pwd -P)"

    # User-configured rules, appended last: allows first, then denies, since
    # seatbelt applies the last matching rule. Each path is emitted both
    # dir-resolved and fully resolved (home-manager files symlink into /nix).
    ADDITIONAL_SANDBOX_RULES=""
    sb_escape() {
        local s="${1//\\/\\\\}"
        printf '%s' "${s//\"/\\\"}"
    }
    add_sb_rule() {
        local expanded resolved full
        expanded="$(expand_path "$2")"
        resolved="$(resolve_path "$expanded")"
        full="$(resolve_path "$(follow_links "$expanded")")"
        ADDITIONAL_SANDBOX_RULES+="($1 (subpath \"$(sb_escape "$resolved")\"))"$'\n'
        if [[ "$full" != "$resolved" ]]; then
            ADDITIONAL_SANDBOX_RULES+="($1 (subpath \"$(sb_escape "$full")\"))"$'\n'
        fi
    }
    for p in ${PAI_SANDBOX_RW_PATHS[@]+"${PAI_SANDBOX_RW_PATHS[@]}"}; do
        add_sb_rule "allow file-read* file-write*" "$p"
    done
    for p in ${PAI_SANDBOX_RO_PATHS[@]+"${PAI_SANDBOX_RO_PATHS[@]}"}; do
        add_sb_rule "allow file-read*" "$p"
    done
    for p in ${PAI_SANDBOX_DENY_PATHS[@]+"${PAI_SANDBOX_DENY_PATHS[@]}"}; do
        add_sb_rule "deny file-read* file-write*" "$p"
    done

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

; per-user Darwin cache/temp
(allow file-read* file-write* (subpath \"$DUDIR\"))

; Xcode/Metal dev-support + toolchain (read + exec)
(allow file-read* file-write* process-exec
    (subpath \"$HOME/Library/Developer\")
    (subpath \"$HOME/Library/Caches/com.apple.dt.Xcode\")
    (subpath \"$HOME/Library/Caches/org.llvm.clang\")
    (subpath \"$HOME/Library/Caches/org.swift.swiftpm\"))

; GUI apps launched inside the sandbox resolve their support directories via
; getpwuid(), not \$HOME, so they land in the REAL home no matter what HOME is
; set to. Grant only the per-bundle-id subtrees those apps need. Add a bundle
; id here to support another GUI app; do not widen to ~/Library.
;   com.zmre.mbr - mbr, the markdown viewer (WebKit website data + caches)
(allow file-read* file-write*
    (subpath \"$HOME/Library/Caches/com.zmre.mbr\")
    (subpath \"$HOME/Library/WebKit/com.zmre.mbr\")
    (literal \"$HOME/Library/Preferences/com.zmre.mbr.plist\"))

; services Xcode/Metal/TLS need
(allow mach-lookup
    (global-name \"com.apple.FSEvents\")
    (global-name \"com.apple.coreservices.launchservicesd\")
    (global-name \"com.apple.SecurityServer\")
    (global-name \"com.apple.trustd.agent\")
    (global-name \"com.apple.bsd.dirhelper\")
    (global-name \"com.apple.mobileassetd.v2\")
    (global-name \"com.apple.mobileassetd\")
    (global-name \"com.apple.security.cryptexd\")
    (global-name-regex #\"^com\.apple\.(dt|metal|MTL|gpu)\"))

; needed if you also want to RUN GPU inference in-sandbox (not just build):
(allow iokit-open
    (iokit-user-client-class \"IOAccelerator\")
    (iokit-user-client-class \"AGXDeviceUserClient\")
    (iokit-user-client-class \"IOGPU\"))
(allow iokit-get-properties)

; Nix store (read-only) - required for all nix dependencies
(allow file-read* (subpath \"/nix\"))

; PAI installation (read-only)
(allow file-read* (subpath \"@paiBasePath@\"))

; Project directory (read/write) - the main work area
(allow file-read* (subpath \"$RESOLVED_PROJECT\"))
(allow file-write* (subpath \"$RESOLVED_PROJECT\"))

; Parent directory (read-only) - for monorepo dependency access
(allow file-read* (subpath \"$RESOLVED_PARENT\"))
(allow file-write* (subpath \"$RESOLVED_PARENT/.bare\"))

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

; === User-configured paths (allow, then deny - last match wins) ===
$ADDITIONAL_SANDBOX_RULES"

    # Debug aid: print the exact profile this wrapper would apply, then exit.
    # Lets sandbox problems be reproduced against the real profile instead of a
    # hand-maintained copy in a test script, which silently drifts.
    #   PAI_SANDBOX_DUMP_PROFILE=1 pai-sandbox-yolo > profile.sb
    if [[ -n "${PAI_SANDBOX_DUMP_PROFILE:-}" ]]; then
        printf '%s\n' "$SANDBOX_PROFILE"
        exit 0
    fi

    # HOME points at the sandbox home, so expose allowed paths under the real
    # home at the same relative spot (Linux gets this from its bind mounts).
    # Existing entries (e.g. copyFromHome results) win.
    for p in ${PAI_SANDBOX_RW_PATHS[@]+"${PAI_SANDBOX_RW_PATHS[@]}"} ${PAI_SANDBOX_RO_PATHS[@]+"${PAI_SANDBOX_RO_PATHS[@]}"}; do
        src="$(expand_path "$p")"
        rel="$(home_rel "$src")" || continue
        [[ -e "$src" ]] || continue
        dest="$SANDBOX_HOME/$rel"
        [[ -e "$dest" || -L "$dest" ]] && continue
        mkdir -p "$(dirname "$dest")"
        ln -s "$src" "$dest"
    done

    # Build env command with optional private mode variables
    ENV_CMD=(env
        HOME="$SANDBOX_HOME"
        PATH="@paiBasePath@/bin:@paiEnvPath@:/run/current-system/sw/bin:$PATH"
        PAI_DIR="@paiBasePath@"
        DA="@assistantName@"
        PAI_SANDBOX_MODE="true"
        PAI_LAUNCH_PID="$$"
        PAI_FLEET_DIR="${PAI_FLEET_DIR:-/tmp/pai-fleet}"
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

    i=0
    while [[ $i -lt ${#EXTRA_ENV_NAMES[@]} ]]; do
        ENV_CMD+=("${EXTRA_ENV_NAMES[$i]}=${EXTRA_ENV_VALUES[$i]}")
        i=$((i + 1))
    done

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
        --ro-bind "$PROJECT_PARENT" "$PROJECT_PARENT"
        --bind "$PROJECT_DIR" "$PROJECT_DIR"
        --ro-bind "@paiBasePath@" "@paiBasePath@"
        --ro-bind /nix /nix
        --ro-bind /usr /usr
        --ro-bind /bin /bin
        --ro-bind /etc /etc
        --setenv HOME "$HOME"
        --setenv PATH "@paiBasePath@/bin:@paiEnvPath@:/run/current-system/sw/bin:$PATH"
        --setenv PAI_DIR "@paiBasePath@"
        --setenv DA "@assistantName@"
        --setenv PAI_SANDBOX_MODE "true"
        --setenv PAI_LAUNCH_PID "$$"
        --setenv PAI_FLEET_DIR "${PAI_FLEET_DIR:-/tmp/pai-fleet}"
    )

    # Add lib paths if they exist
    [[ -d /lib ]] && BWRAP_ARGS+=(--ro-bind /lib /lib)
    [[ -d /lib64 ]] && BWRAP_ARGS+=(--ro-bind /lib64 /lib64)

    # DNS: on NixOS (and many other distros) /etc/resolv.conf is a symlink
    # into /run/, which isn't bound — leaving the symlink dangling inside
    # the sandbox. Bind the real file at its actual path so the existing
    # /etc/resolv.conf symlink chain resolves correctly.
    RESOLV_CONF="$(readlink -f /etc/resolv.conf 2>/dev/null || true)"
    if [[ -n "$RESOLV_CONF" && -f "$RESOLV_CONF" && "$RESOLV_CONF" != "/etc/resolv.conf" ]]; then
        BWRAP_ARGS+=(--ro-bind "$RESOLV_CONF" "$RESOLV_CONF")
    fi

    # User-configured paths. Bound after the home bind so paths under ~ show up
    # at their real location, which is also $HOME/<rel> inside the sandbox.
    # -try variants skip missing sources instead of aborting.
    BOUND_PATHS=("$PROJECT_DIR" "$PROJECT_PARENT")
    for p in ${PAI_SANDBOX_RW_PATHS[@]+"${PAI_SANDBOX_RW_PATHS[@]}"}; do
        src="$(expand_path "$p")"
        BWRAP_ARGS+=(--bind-try "$src" "$src")
        BOUND_PATHS+=("$src")
    done
    for p in ${PAI_SANDBOX_RO_PATHS[@]+"${PAI_SANDBOX_RO_PATHS[@]}"}; do
        src="$(expand_path "$p")"
        BWRAP_ARGS+=(--ro-bind-try "$src" "$src")
        BOUND_PATHS+=("$src")
    done

    # Denies: mounted after all binds so they shadow them. Only needed for
    # paths under something bound; everything else is already invisible, and
    # mounting over it would litter the sandbox home with empty mountpoints.
    for p in ${PAI_SANDBOX_DENY_PATHS[@]+"${PAI_SANDBOX_DENY_PATHS[@]}"}; do
        src="$(expand_path "$p")"
        [[ -e "$src" ]] || continue
        for b in "${BOUND_PATHS[@]}"; do
            if is_under "$src" "$b"; then
                if [[ -d "$src" ]]; then
                    BWRAP_ARGS+=(--tmpfs "$src")
                else
                    BWRAP_ARGS+=(--ro-bind /dev/null "$src")
                fi
                break
            fi
        done
    done

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

    # Debug aid (same as macOS): print the bwrap arguments, one per line, then exit.
    if [[ -n "${PAI_SANDBOX_DUMP_PROFILE:-}" ]]; then
        printf '%s\n' "${BWRAP_ARGS[@]}"
        exit 0
    fi

    # envFromCommands values added after the dump so tokens aren't printed
    i=0
    while [[ $i -lt ${#EXTRA_ENV_NAMES[@]} ]]; do
        BWRAP_ARGS+=(--setenv "${EXTRA_ENV_NAMES[$i]}" "${EXTRA_ENV_VALUES[$i]}")
        i=$((i + 1))
    done

    bwrap "${BWRAP_ARGS[@]}" -- "$CLAUDE_CMD" $CLAUDE_ARGS "$@"
fi
