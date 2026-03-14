#!/usr/bin/env bash
# Shared helper: computes project-scoped temp directory.
# Source this from other hook scripts: source "$SCRIPT_DIR/_proj-hash.sh"
#
# Exports:
#   CLAUDE_TMPDIR  -- /tmp/.claude-<12char_hash>/ (created if missing)

_PROJ_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
_HASH=$(printf '%s' "$_PROJ_DIR" | md5 -q 2>/dev/null || printf '%s' "$_PROJ_DIR" | md5sum 2>/dev/null | cut -d' ' -f1)
CLAUDE_TMPDIR="/tmp/.claude-${_HASH:0:12}"
mkdir -p "$CLAUDE_TMPDIR"

# Read active skill: session-scoped first, fall back to project-scoped.
# Usage: _read_skill "session_id"
_read_skill() {
  local sid="${1:-shared}"
  local sf="$CLAUDE_TMPDIR/.claude-skill-active-${sid}"
  local pf="$CLAUDE_TMPDIR/.claude-skill-active"
  if [ -f "$sf" ]; then cat "$sf"
  elif [ -f "$pf" ]; then cat "$pf"
  fi
}
