#!/usr/bin/env bash
#
# fleet-track.sh <EventName>
#
# Emits per-session state for the "fleet" view of running Claude instances.
# Each session owns exactly one file: $PAI_FLEET_DIR/<session_id>.json (single
# writer -> no lock contention). Writes are atomic (temp file + mv). A clean
# quit (SessionEnd) removes the file; crashes/kills are reaped later by the CLI
# via the recorded pid. This hook must never block Claude: all errors are
# swallowed and we always exit 0.
#
# Wired in modules/pai.nix for SessionStart, UserPromptSubmit, Notification,
# PermissionRequest, Stop and SessionEnd. Placeholder-free on purpose (the build
# only substitutes .ts/.js hooks) - it reads everything from env + stdin.

EVENT="${1:-Unknown}"
DIR="${PAI_FLEET_DIR:-/tmp/pai-fleet}"

input="$(cat)"
[ -z "$input" ] && input='{}'

sid="$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)"
[ -z "$sid" ] && exit 0   # nothing to track without a session id

mkdir -p "$DIR" 2>/dev/null
file="$DIR/$sid.json"

# Clean quit -> drop it from the list entirely (even though it could be resumed).
if [ "$EVENT" = "SessionEnd" ]; then
  rm -f "$file" 2>/dev/null
  exit 0
fi

now="$(date +%s)"
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)"
pmode="$(printf '%s' "$input" | jq -r '.permission_mode // empty' 2>/dev/null)"
transcript="$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)"
model="$(printf '%s' "$input" | jq -r '(.model // empty) | if type=="object" then (.display_name // .id // "") else tostring end' 2>/dev/null)"
msg="$(printf '%s' "$input" | jq -r '.message // empty' 2>/dev/null)"
project=""
[ -n "$cwd" ] && project="$(basename "$cwd" 2>/dev/null)"

sandbox=false
[ "${PAI_SANDBOX_MODE:-}" = "true" ] && sandbox=true

# Mode: a yolo sandbox run overrides the reported permission mode.
if [ "$sandbox" = true ]; then mode="yolo"; else mode="${pmode:-default}"; fi

pid="${PAI_LAUNCH_PID:-$PPID}"
case "$pid" in ''|*[!0-9]*) pid=0 ;; esac

# State + attention per event.
#
#   running  - actively working (prompt submitted, tools running)
#   waiting  - BLOCKED on a tool-permission request; needs the user to unblock
#   done     - turn complete, idle, awaiting the user's next prompt
#
# Stop is the clean "done" signal (it does NOT fire during a permission pause).
# A permission pause surfaces via Notification ("...needs your permission to
# use X"); Notification ALSO fires on the ~60s idle nudge ("...waiting for your
# input"), which is really just "done", so we classify by the message text.
# PostToolUse flips us back to running after a permission is granted.
state="running"; attention=false; reason=""
case "$EVENT" in
  Stop)
    state="done" ;;
  PostToolUse|PreToolUse)
    state="running" ;;
  PermissionRequest)
    state="waiting"; attention=true; reason="permission" ;;
  Notification)
    lc="$(printf '%s' "$msg" | tr '[:upper:]' '[:lower:]')"
    case "$lc" in
      *permission*|*approve*|*"needs your"*)
        state="waiting"; attention=true; reason="permission" ;;
      *"waiting for your input"*|*idle*)
        state="done"; attention=false ;;
      *)
        # Unknown notification: surface it as needing attention rather than
        # silently dropping a possible permission request.
        state="waiting"; attention=true; reason="notification" ;;
    esac ;;
  *)
    state="running" ;;
esac

# Title: refresh from the prompt on submit; otherwise keep whatever was there.
title=""
if [ "$EVENT" = "UserPromptSubmit" ]; then
  title="$(printf '%s' "$input" | jq -r '.prompt // empty' 2>/dev/null | tr '\n' ' ' | cut -c1-60 | sed 's/[[:space:]]*$//')"
fi

# Context usage (best-effort, on Stop): last assistant usage in the transcript tail.
ctx=""
if [ "$EVENT" = "Stop" ] && [ -n "$transcript" ] && [ -f "$transcript" ]; then
  ctx="$(tail -n 80 "$transcript" 2>/dev/null | jq -s 'map(select(.message.usage)) | last | .message.usage | ((.input_tokens // 0) + (.cache_read_input_tokens // 0) + (.cache_creation_input_tokens // 0))' 2>/dev/null)"
  case "$ctx" in ''|null) ctx="" ;; esac
fi

existing='{}'
[ -f "$file" ] && existing="$(cat "$file" 2>/dev/null || printf '{}')"

tmp="$(mktemp "$DIR/.$sid.XXXXXX" 2>/dev/null)" || exit 0
if printf '%s' "$existing" | jq \
  --arg sid "$sid" --argjson pid "$pid" \
  --arg state "$state" --argjson attention "$attention" --arg reason "$reason" \
  --arg cwd "$cwd" --arg project "$project" --arg title "$title" \
  --arg model "$model" --arg mode "$mode" --argjson sandbox "$sandbox" \
  --arg cmd "${DA:-claude}" --argjson now "$now" \
  --arg event "$EVENT" --arg ctx "$ctx" '
    . as $e
    | .session_id = $sid
    | .pid = $pid
    | .state = $state
    | .attention = $attention
    | (if $attention
         then .attention_reason = $reason | .attention_since = ($e.attention_since // $now)
         else .attention_reason = null   | .attention_since = null end)
    | .cwd = $cwd | .project = $project
    | (if $title != "" then .title = $title else . end)
    | .model = $model | .mode = $mode | .sandbox = $sandbox
    | .command_name = $cmd
    | .started_at = ($e.started_at // $now)
    | .updated_at = $now
    | .last_event = $event
    | (if $ctx != "" then .context_tokens = ($ctx | tonumber) else . end)
  ' > "$tmp" 2>/dev/null; then
  mv -f "$tmp" "$file" 2>/dev/null
fi
rm -f "$tmp" 2>/dev/null
exit 0
