#!/bin/bash

# Read JSON input from stdin
input=$(cat)

# Get Digital Assistant configuration from environment
DA_NAME="${DA:-Assistant}"  # Assistant name
DA_COLOR="${DA_COLOR:-purple}"  # Color for the assistant name

# Extract data from JSON input
current_dir=$(echo "$input" | jq -r '.workspace.current_dir')
model_name=$(echo "$input" | jq -r '.model.display_name')
context_size=$(echo "$input" | jq -r '.context_window.context_window_size')
usage=$(echo "$input" | jq '.context_window.current_usage')

# Get directory name
dir_name=$(basename "$current_dir")

# Counts are injected at build time since nix store is read-only
# These values are computed during the nix build phase
claude_dir="@paiBasePath@/claude"
skills_count="@skills_count@"
mcps_count="@mcps_count@"
fabric_count="@fabric_count@"
mcp_names_raw="@mcp_names_raw@"

# Tokyo Night Storm Color Scheme
# Using $'...' syntax so escape sequences become actual ESC characters
BACKGROUND=$'\033[48;2;36;40;59m'
BRIGHT_PURPLE=$'\033[38;2;187;154;247m'
BRIGHT_BLUE=$'\033[38;2;122;162;247m'
DARK_BLUE=$'\033[38;2;100;140;200m'
BRIGHT_GREEN=$'\033[38;2;158;206;106m'
DARK_GREEN=$'\033[38;2;130;170;90m'
BRIGHT_ORANGE=$'\033[38;2;255;158;100m'
BRIGHT_RED=$'\033[38;2;247;118;142m'
BRIGHT_CYAN=$'\033[38;2;125;207;255m'
BRIGHT_MAGENTA=$'\033[38;2;187;154;247m'
BRIGHT_YELLOW=$'\033[38;2;224;175;104m'

# Map DA_COLOR to actual ANSI color code
case "$DA_COLOR" in
    "purple") DA_DISPLAY_COLOR=$'\033[38;2;147;112;219m' ;;
    "blue") DA_DISPLAY_COLOR="$BRIGHT_BLUE" ;;
    "green") DA_DISPLAY_COLOR="$BRIGHT_GREEN" ;;
    "cyan") DA_DISPLAY_COLOR="$BRIGHT_CYAN" ;;
    "magenta") DA_DISPLAY_COLOR="$BRIGHT_MAGENTA" ;;
    "yellow") DA_DISPLAY_COLOR="$BRIGHT_YELLOW" ;;
    "red") DA_DISPLAY_COLOR="$BRIGHT_RED" ;;
    "orange") DA_DISPLAY_COLOR="$BRIGHT_ORANGE" ;;
    *) DA_DISPLAY_COLOR=$'\033[38;2;147;112;219m' ;;  # Default to purple
esac

# Line-specific colors
LINE1_PRIMARY="$BRIGHT_PURPLE"
LINE1_ACCENT=$'\033[38;2;160;130;210m'
MODEL_COLOR=$'\033[38;2;135;206;250m'

LINE2_PRIMARY="$DARK_BLUE"
LINE2_ACCENT=$'\033[38;2;110;150;210m'

LINE3_PRIMARY="$DARK_GREEN"
LINE3_ACCENT=$'\033[38;2;140;180;100m'
COST_COLOR="$LINE3_ACCENT"
TOKENS_COLOR=$'\033[38;2;169;177;214m'

SEPARATOR_COLOR=$'\033[38;2;140;152;180m'
DIR_COLOR=$'\033[38;2;135;206;250m'

# MCP colors
MCP_DAEMON="$BRIGHT_BLUE"
MCP_STRIPE="$LINE2_ACCENT"
MCP_DEFAULT="$LINE2_PRIMARY"

RESET=$'\033[0m'

# Format MCP names efficiently
mcp_names_formatted=""
for mcp in $mcp_names_raw; do
    case "$mcp" in
        "daemon") formatted="${MCP_DAEMON}Daemon${RESET}" ;;
        "stripe") formatted="${MCP_STRIPE}Stripe${RESET}" ;;
        "httpx") formatted="${MCP_DEFAULT}HTTPx${RESET}" ;;
        "brightdata") formatted="${MCP_DEFAULT}BrightData${RESET}" ;;
        "naabu") formatted="${MCP_DEFAULT}Naabu${RESET}" ;;
        "apify") formatted="${MCP_DEFAULT}Apify${RESET}" ;;
        "content") formatted="${MCP_DEFAULT}Content${RESET}" ;;
        "Ref") formatted="${MCP_DEFAULT}Ref${RESET}" ;;
        "pai") formatted="${MCP_DEFAULT}Foundry${RESET}" ;;
        "playwright") formatted="${MCP_DEFAULT}Playwright${RESET}" ;;
        *) formatted="${MCP_DEFAULT}${mcp^}${RESET}" ;;
    esac

    if [ -z "$mcp_names_formatted" ]; then
        mcp_names_formatted="$formatted"
    else
        mcp_names_formatted="$mcp_names_formatted${SEPARATOR_COLOR}, ${formatted}"
    fi
done

# Output the full 3-line statusline
# LINE 1 - PURPLE theme with all counts
printf "%s%s%s%s here, running on %s🧠 %s%s%s in 📁 %s%s%s%s\n" \
    "$DA_DISPLAY_COLOR" "$DA_NAME" "$RESET" "$LINE1_PRIMARY" \
    "$MODEL_COLOR" "$model_name" "$RESET" "$LINE1_PRIMARY" \
    "$DIR_COLOR" "$dir_name" "$RESET" "$RESET"

printf "%s🔧 %s Skills%s%s, %s%s🔌 %s MCPs%s%s, and %s%s📚 %s Patterns%s\n" \
  "${LINE1_PRIMARY}" "${skills_count}" "${RESET}" "${LINE1_PRIMARY}" \
  "${RESET}" "${LINE1_PRIMARY}" "${mcps_count}" "${RESET}" "${LINE1_PRIMARY}" \
  "${RESET}" "${LINE1_PRIMARY}" "${fabric_count}" "${RESET}"

# LINE 3 - BLUE theme with MCP names
printf "%s🔌 MCPs%s%s: %s%s%s\n" "$LINE2_PRIMARY" "$RESET" "$LINE2_PRIMARY" "$SEPARATOR_COLOR" "$mcp_names_formatted" "$RESET"

# LINE 4 - Private indicator and usage
if [ "$usage" != "null" ]; then
    # Calculate current context from current_usage fields
    current_tokens=$(echo "$usage" | jq '.input_tokens + .cache_creation_input_tokens + .cache_read_input_tokens')
    percent_used=$((current_tokens * 100 / context_size))
    printf "📖 %sInput Context: %s%s%s%%%s (%'d)" "${LINE1_PRIMARY}" "${RESET}" "${DIR_COLOR}" "${percent_used}" "${RESET}" "${current_tokens}"
fi
