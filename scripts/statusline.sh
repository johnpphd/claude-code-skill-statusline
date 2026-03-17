#!/usr/bin/env bash
# Claude Code statusline: shows user, cwd, git branch, active skill, agent,
# model, cost, and context token usage.
#
# Reads JSON from stdin (provided by Claude Code's statusLine system).
# Uses session-keyed skill lookup for correct multi-session display.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_proj-hash.sh"
source "$SCRIPT_DIR/_string_to_color.sh"

# Read stdin once, store for reuse
INPUT=$(cat)

# Extract session_id for session-scoped skill lookup
_session_id=$(echo "$INPUT" | python3 -c "
import sys, json
try: print(json.load(sys.stdin).get('session_id',''))
except: print('')
" 2>/dev/null)

ACTIVE_SKILL=$(_read_skill "${_session_id:-shared}")

# Extract fields from JSON
agent=$(echo "$INPUT" | jq -r '.agent_type // empty')
model=$(echo "$INPUT" | jq -r '.model.display_name // empty')
cost=$(echo "$INPUT" | jq -r '.cost.total_cost_usd // empty')
current_tokens=$(echo "$INPUT" | jq -r '.context_window.current_usage.input_tokens // empty')
total_in=$(echo "$INPUT" | jq -r '.context_window.total_input_tokens // empty')
total_out=$(echo "$INPUT" | jq -r '.context_window.total_output_tokens // empty')
cwd=$(echo "$INPUT" | jq -r '.workspace.current_dir')
session_id=$(echo "$INPUT" | jq -r '.session_id // empty' | cut -c1-8)

# Get git branch
git_branch=$(cd "$cwd" 2>/dev/null && git --no-optional-locks branch 2>/dev/null | sed -n 's/^\* \(.*\)/[\1]/p')

# Get username
username=$(whoami)

# --- Display ---
# Colors: 243=gray, 197=magenta, 39=cyan, 67=dim cyan, 114=muted green,
#         214=orange, 103=muted purple, 178=yellow, 245=light gray

# Project color indicator (deterministic per directory name)
_proj_color=$(_project_color256 "${cwd##*/}")
printf "\033[38;5;%sm██\033[0m " "$_proj_color"

printf "\033[38;5;243m%s\033[0m" "$username"

if [ -n "$session_id" ]; then
  printf " \033[38;5;67m%s\033[0m" "$session_id"
fi

printf " \033[38;5;197m%s\033[0m" "$cwd"

if [ -n "$git_branch" ]; then
  printf " \033[38;5;39m%s\033[0m" "$git_branch"
fi

if [ -n "$ACTIVE_SKILL" ]; then
  printf " \033[38;5;114m/%s\033[0m" "$ACTIVE_SKILL"
fi

if [ -n "$agent" ]; then
  printf " \033[38;5;214m[%s]\033[0m" "$agent"
fi

if [ -n "$model" ]; then
  printf " \033[38;5;103m%s\033[0m" "$model"
fi

if [ -n "$cost" ]; then
  printf " \033[38;5;178m\$%.2f\033[0m" "$cost"
fi

if [ -n "$current_tokens" ] && [ -n "$total_in" ] && [ -n "$total_out" ]; then
  fmt_current=$(echo "$current_tokens" | awk '{ if ($1 >= 1000) printf "%.1fk", $1/1000; else print $1 }')
  fmt_in=$(echo "$total_in" | awk '{ if ($1 >= 1000) printf "%.1fk", $1/1000; else print $1 }')
  fmt_out=$(echo "$total_out" | awk '{ if ($1 >= 1000) printf "%.1fk", $1/1000; else print $1 }')
  printf " \033[38;5;245m[ctx:%s in:%s out:%s]\033[0m" "$fmt_current" "$fmt_in" "$fmt_out"
fi
