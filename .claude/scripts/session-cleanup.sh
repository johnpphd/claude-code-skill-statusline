#!/usr/bin/env bash
# SessionStart hook: clears session-scoped skill files so each session starts fresh.
#
# Hook data arrives via JSON on stdin.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_proj-hash.sh"

_hook_json=$(cat)
_session_id=$(echo "$_hook_json" | python3 -c "
import sys, json
try: print(json.load(sys.stdin).get('session_id',''))
except: print('')
" 2>/dev/null)
SESSION_ID="${_session_id:-shared}"

# Clear this session's skill-active flag
rm -f "$CLAUDE_TMPDIR/.claude-skill-active-${SESSION_ID}"

# Clear project-scoped skill-active (backward compat)
rm -f "$CLAUDE_TMPDIR/.claude-skill-active"

# Clean stale session-scoped files older than 24h
find "$CLAUDE_TMPDIR" -name ".claude-skill-active-*" -mmin +1440 -delete 2>/dev/null

exit 0
