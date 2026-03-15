#!/usr/bin/env bash
# PostToolUse Bash hook: copies project-scoped skill-active to session-keyed file.
#
# Fires after every Bash command. Quick-exits unless the command is a skill init
# block that WRITES to .claude-skill-active (detected by redirect "> " before
# the filename -- cat/ls/rm don't have this).
#
# This is the ONLY reliable way to write session-keyed files because:
#   - PreToolUse/PostToolUse Skill hooks DO NOT FIRE (Skill tool is internal)
#   - CLAUDE_SESSION_ID env var is empty in v2.1.x
#   - The SKILL.md init block (Bash command) is the only observable skill event
#
# Exit codes:
#   0 = always (PostToolUse hooks are observational)

# Quick check: bail unless this is a write to .claude-skill-active
# Init blocks: echo "skill-name" > "$_d/.claude-skill-active"
# In JSON, quotes are escaped (\"), but "> " redirect is preserved literally.
# cat/ls/rm commands don't contain "> " before the filename.
_raw=$(cat)
case "$_raw" in
  *'> '*'.claude-skill-active'*) ;;
  *) exit 0 ;;
esac

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_proj-hash.sh"

_session_id=$(echo "$_raw" | python3 -c "
import sys, json
try: print(json.load(sys.stdin).get('session_id',''))
except: print('')
" 2>/dev/null)

if [ -n "$_session_id" ] && [ -f "$CLAUDE_TMPDIR/.claude-skill-active" ]; then
  cp "$CLAUDE_TMPDIR/.claude-skill-active" "$CLAUDE_TMPDIR/.claude-skill-active-${_session_id}"
fi

exit 0
