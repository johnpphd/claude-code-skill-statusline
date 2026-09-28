#!/usr/bin/env bash
# SessionStart hook: clears this session's skill marker on a fresh start.
#
# Hook data arrives via JSON on stdin.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_proj-hash.sh"

_hook_json=$(cat)
_parsed=$(echo "$_hook_json" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('session_id', ''))
    print(d.get('source', ''))
except Exception:
    print(); print()
" 2>/dev/null)
SESSION_ID=$(echo "$_parsed" | sed -n 1p)
SOURCE=$(echo "$_parsed" | sed -n 2p)

# A resumed or compacted session continues the same work, so it keeps its
# skill. Only a fresh start or an explicit clear wipes the marker.
if [ -n "$SESSION_ID" ] && [ "$SOURCE" != "resume" ] && [ "$SOURCE" != "compact" ]; then
  rm -f "$CLAUDE_TMPDIR/.claude-skill-active-${SESSION_ID}"
fi

# Any session start in the project runs this sweep, and mtime is the only
# liveness signal. A 24h window reaped markers from long-running sibling
# sessions. /tmp clears on reboot, so hygiene can wait a week.
find "$CLAUDE_TMPDIR" -name ".claude-skill-active-*" -mtime +7 -delete 2>/dev/null

exit 0
