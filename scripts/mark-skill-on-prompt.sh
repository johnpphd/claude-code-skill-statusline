#!/usr/bin/env bash
# UserPromptSubmit hook: records a skill the user TYPES as "/name args".
#
# A typed slash command expands into the prompt without a Skill tool call, so
# the PreToolUse writer (mark-skill-active.sh) never sees it. The prompt field
# carries the raw typed text, so the leading token is parsed. A command-name
# tag fallback covers harness versions that pre-expand the command.
#
# Only a token that resolves to a real skill or command on disk counts. Prose
# like "/tmp is full" and paths like /Users/x never touch the marker.
# Plugin-namespaced names (plugin:skill) have no fixed path on disk, so they
# skip the check.
#
# Exit codes:
#   0 = always (a display helper must never block a prompt)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_proj-hash.sh"

_hook_json=$(cat)
_parsed=$(echo "$_hook_json" | python3 -c "
import sys, json, re
NAME = r'[A-Za-z0-9][A-Za-z0-9_-]*(?::[A-Za-z0-9][A-Za-z0-9_-]*)?'
try:
    d = json.load(sys.stdin)
    prompt = d.get('prompt', '') or ''
    m = re.match(r'\s*/(' + NAME + r')(?=\s|$)', prompt)
    if not m:
        m = re.search(r'<command-name>/?(' + NAME + r')</command-name>', prompt)
    print(d.get('session_id', ''))
    print(m.group(1) if m else '')
except Exception:
    print(); print()
" 2>/dev/null)
SESSION_ID=$(echo "$_parsed" | sed -n 1p)
SKILL_NAME=$(echo "$_parsed" | sed -n 2p)

[ -z "$SESSION_ID" ] || [ -z "$SKILL_NAME" ] && exit 0

# Project definitions shadow global ones, so check the project first.
if [[ "$SKILL_NAME" != *:* ]]; then
  _PROJ="${CLAUDE_PROJECT_DIR:-$(pwd)}"
  _found=no
  for _c in \
    "$_PROJ/.claude/skills/$SKILL_NAME/SKILL.md" \
    "$_PROJ/.claude/commands/$SKILL_NAME.md" \
    "$HOME/.claude/skills/$SKILL_NAME/SKILL.md" \
    "$HOME/.claude/commands/$SKILL_NAME.md"; do
    [ -f "$_c" ] && { _found=yes; break; }
  done
  [ "$_found" = "no" ] && exit 0
fi

echo "$SKILL_NAME" > "$CLAUDE_TMPDIR/.claude-skill-active-${SESSION_ID}" 2>/dev/null
exit 0
