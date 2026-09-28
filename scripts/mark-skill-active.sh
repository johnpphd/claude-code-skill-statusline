#!/usr/bin/env bash
# PreToolUse Skill hook: records the skill the model just loaded.
#
# The hook JSON carries session_id and tool_input.skill, so the marker is keyed
# by session and two sessions in one project never show each other's skill.
# Plugin skills keep their "plugin:skill" name, which is also how the user
# types them, so the statusline shows what the user would recognize.
#
# Exit codes:
#   0 = always (a display helper must never block a skill)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_proj-hash.sh"

_hook_json=$(cat)
_parsed=$(echo "$_hook_json" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    ti = d.get('tool_input', {})
    if isinstance(ti, str): ti = json.loads(ti)
    print(d.get('session_id', ''))
    print(ti.get('skill', ''))
except Exception:
    print(); print()
" 2>/dev/null)
SESSION_ID=$(echo "$_parsed" | sed -n 1p)
SKILL_NAME=$(echo "$_parsed" | sed -n 2p)

[ -z "$SESSION_ID" ] || [ -z "$SKILL_NAME" ] && exit 0

echo "$SKILL_NAME" > "$CLAUDE_TMPDIR/.claude-skill-active-${SESSION_ID}" 2>/dev/null
exit 0
