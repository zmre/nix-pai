#!/usr/bin/env bash
#
# pai-fleet — summarize running Claude instances.
#
# Reads per-session state written by claude/hooks/fleet-track.sh from
# $PAI_FLEET_DIR (default /tmp/pai-fleet). Before reporting, it reaps any entry
# whose process is gone (kill -0 fails) so quit/killed/crashed instances that
# fired no SessionEnd hook disappear from the list.
#
# Modes:
#   (default) / --table   aligned summary table
#   --json                JSON array of live sessions (for menubar / scripts)
#   --counts              "running waiting done" on one line (for sketchybar)
#   --watch               redraw the table every 2s

export PATH="@paiEnvPath@:$PATH"

DIR="${PAI_FLEET_DIR:-/tmp/pai-fleet}"
MODE="table"
case "${1:-}" in
  --json)        MODE="json" ;;
  --counts)      MODE="counts" ;;
  --rows)        MODE="rows" ;;
  --watch)       MODE="watch" ;;
  ""|--table)    MODE="table" ;;
  -h|--help)     echo "usage: $(basename "$0") [--table|--json|--counts|--rows|--watch]"; exit 0 ;;
  *)             echo "unknown option: $1" >&2; exit 2 ;;
esac

# Emit one JSON object per LIVE session; delete files for dead pids.
live_json() {
  [ -d "$DIR" ] || return 0
  local f pid
  for f in "$DIR"/*.json; do
    [ -e "$f" ] || continue
    pid="$(jq -r '.pid // 0' "$f" 2>/dev/null)"
    if [ -z "$pid" ] || [ "$pid" = "0" ] || [ "$pid" = "null" ] || ! kill -0 "$pid" 2>/dev/null; then
      rm -f "$f" 2>/dev/null
      continue
    fi
    cat "$f" 2>/dev/null
  done
}

render_counts() {
  live_json | jq -s -r '
    "\(map(select(.state=="running")) | length) \(map(select(.state=="waiting")) | length) \(map(select(.state=="done")) | length)"'
}

render_json() { live_json | jq -s '.'; }

# One TAB-separated line per session, most-attention-first, for the sketchybar
# popup. Columns: state, attention(0/1), project, mode, model, age, ctx, title.
render_rows() {
  local now; now="$(date +%s)"
  live_json | jq -s -r --argjson now "$now" '
    def age(s): ($now - (s // $now)) as $d
      | if   $d < 60   then "\($d)s"
        elif $d < 3600 then "\(($d/60)|floor)m"
        else                "\(($d/3600)|floor)h\((($d%3600)/60)|floor)m" end;
    def ctx: if (.context_tokens != null) then "\((.context_tokens/1000)|floor)k" else "-" end;
    sort_by([(.attention|not), .state])[]
      | [ (.state // "running"),
          (if .attention then "1" else "0" end),
          (.project // "?"),
          (.mode // "?"),
          (.model // "?"),
          age(.started_at),
          ctx,
          ((.title // "") | gsub("[\t\n]"; " "))
        ] | @tsv'
}

render_table() {
  local now; now="$(date +%s)"
  live_json | jq -s -r --argjson now "$now" '
    def age(s): ($now - (s // $now)) as $d
      | if   $d < 60   then "\($d)s"
        elif $d < 3600 then "\(($d/60)|floor)m"
        else                "\(($d/3600)|floor)h\((($d%3600)/60)|floor)m" end;
    def state_str(s;a):
      if a then "⚠ waiting" elif s=="done" then "✓ done" else "● running" end;
    def ctx:
      if (.context_tokens != null) then "\((.context_tokens/1000)|floor)k" else "-" end;
    if length == 0 then "No running Claude instances."
    else
      (["STATE","PROJECT","MODE","MODEL","AGE","CTX","TITLE"] | @tsv),
      ( sort_by([(.attention|not), .state])[]
        | [ state_str(.state; .attention),
            (.project // "?"),
            (.mode // "?"),
            (.model // "?"),
            age(.started_at),
            ctx,
            ((.title // "") | if length > 50 then .[0:49] + "…" else . end)
          ] | @tsv )
    end' | column -t -s "$(printf '\t')"
}

case "$MODE" in
  counts) render_counts ;;
  json)   render_json ;;
  rows)   render_rows ;;
  table)  render_table ;;
  watch)
    while true; do
      clear
      printf 'Claude fleet — %s\n' "$(date '+%H:%M:%S')"
      render_table
      sleep 2
    done
    ;;
esac
