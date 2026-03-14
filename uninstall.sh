#!/usr/bin/env bash
# Uninstall claude-code-skill-statusline from ~/.claude/
#
# - Removes scripts from ~/.claude/scripts/statusline/
# - Removes our hook entries and statusLine from ~/.claude/settings.json
# - Preserves all other settings and hooks

set -euo pipefail

CLAUDE_DIR="$HOME/.claude"
INSTALL_DIR="$CLAUDE_DIR/scripts/statusline"
SETTINGS="$CLAUDE_DIR/settings.json"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

info()  { printf "${GREEN}[-]${NC} %s\n" "$1"; }
warn()  { printf "${YELLOW}[!]${NC} %s\n" "$1"; }

# --- Remove scripts ---

if [ -d "$INSTALL_DIR" ]; then
  rm -rf "$INSTALL_DIR"
  info "Removed $INSTALL_DIR/"
  # Clean up empty parent if we created it
  rmdir "$CLAUDE_DIR/scripts" 2>/dev/null || true
else
  warn "Scripts directory not found, skipping"
fi

# --- Remove hooks from settings.json ---

if [ -f "$SETTINGS" ] && command -v jq >/dev/null 2>&1; then
  cp "$SETTINGS" "$SETTINGS.bak"
  info "Backup saved to $SETTINGS.bak"

  JQ_FILTER=$(cat <<'JQEOF'
    (if .hooks.SessionStart then
      .hooks.SessionStart |= map(
        select(.hooks | all((.command == "bash ~/.claude/scripts/statusline/session-cleanup.sh") | not))
      )
    else . end) |
    (if .hooks.PostToolUse then
      .hooks.PostToolUse |= map(
        select(.hooks | all((.command == "bash ~/.claude/scripts/statusline/copy-skill-to-session.sh") | not))
      )
    else . end) |
    (if .hooks.SessionStart == [] then del(.hooks.SessionStart) else . end) |
    (if .hooks.PostToolUse == [] then del(.hooks.PostToolUse) else . end) |
    (if .hooks == {} then del(.hooks) else . end) |
    (if .statusLine.command == "bash ~/.claude/scripts/statusline/statusline.sh"
     then del(.statusLine)
     else . end)
JQEOF
  )
  jq "$JQ_FILTER" "$SETTINGS" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"

  info "Removed hooks and statusLine from $SETTINGS"
else
  warn "Could not update settings.json (missing jq or file)"
fi

info "Uninstalled. Restart Claude Code to apply."
