#!/usr/bin/env bash
# Install claude-code-skill-statusline to ~/.claude/
#
# - Copies scripts to ~/.claude/scripts/statusline/
# - Merges hooks and statusLine into ~/.claude/settings.json
# - Non-destructive: preserves existing hooks and settings
#
# Requirements: jq, python3, bash 4+
# Usage: bash install.sh

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
INSTALL_DIR="$CLAUDE_DIR/scripts/statusline"
SETTINGS="$CLAUDE_DIR/settings.json"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

info()  { printf "${GREEN}[+]${NC} %s\n" "$1"; }
warn()  { printf "${YELLOW}[!]${NC} %s\n" "$1"; }
error() { printf "${RED}[x]${NC} %s\n" "$1" >&2; exit 1; }

# --- Preflight checks ---

command -v jq >/dev/null 2>&1 || error "jq is required. Install: https://jqlang.github.io/jq/download/"
command -v python3 >/dev/null 2>&1 || error "python3 is required."

if [ ! -d "$CLAUDE_DIR" ]; then
  error "~/.claude/ not found. Is Claude Code installed?"
fi

# --- Copy scripts ---

info "Installing scripts to $INSTALL_DIR/"
mkdir -p "$INSTALL_DIR"
cp "$REPO_DIR/scripts/_proj-hash.sh" "$INSTALL_DIR/"
cp "$REPO_DIR/scripts/copy-skill-to-session.sh" "$INSTALL_DIR/"
cp "$REPO_DIR/scripts/session-cleanup.sh" "$INSTALL_DIR/"
cp "$REPO_DIR/scripts/statusline.sh" "$INSTALL_DIR/"
chmod +x "$INSTALL_DIR"/*.sh

# --- Merge settings.json ---

# The hooks and statusLine we want to add
STATUSLINE_HOOKS=$(cat <<'HOOKJSON'
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/scripts/statusline/session-cleanup.sh",
            "timeout": 5
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/scripts/statusline/copy-skill-to-session.sh",
            "timeout": 5
          }
        ]
      }
    ]
  },
  "statusLine": {
    "type": "command",
    "command": "bash ~/.claude/scripts/statusline/statusline.sh"
  }
}
HOOKJSON
)

if [ ! -f "$SETTINGS" ]; then
  info "Creating $SETTINGS"
  echo "$STATUSLINE_HOOKS" | jq '.' > "$SETTINGS"
else
  info "Merging hooks into $SETTINGS"

  # Back up existing settings
  cp "$SETTINGS" "$SETTINGS.bak"
  info "Backup saved to $SETTINGS.bak"

  # Merge using jq:
  # - For each hook category (SessionStart, PostToolUse), append our entries
  #   to existing arrays (skip if our command is already present)
  # - Set statusLine (overwrites any existing statusLine)
  jq --argjson new "$STATUSLINE_HOOKS" '
    # Helper: check if a command string already exists in a hook category array
    def has_command($cmd):
      . as $arr | any($arr[]; .hooks[]? | .command == $cmd);

    # Merge hook arrays
    .hooks //= {} |

    # SessionStart
    .hooks.SessionStart //= [] |
    (if (.hooks.SessionStart | has_command("bash ~/.claude/scripts/statusline/session-cleanup.sh"))
     then .
     else .hooks.SessionStart += $new.hooks.SessionStart
     end) |

    # PostToolUse -- need to check if our specific matcher+command combo exists
    .hooks.PostToolUse //= [] |
    (if (.hooks.PostToolUse | has_command("bash ~/.claude/scripts/statusline/copy-skill-to-session.sh"))
     then .
     else .hooks.PostToolUse += $new.hooks.PostToolUse
     end) |

    # StatusLine (simple overwrite)
    .statusLine = $new.statusLine
  ' "$SETTINGS" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"
fi

# --- Done ---

info "Installed successfully!"
echo ""
echo "Next steps:"
echo "  1. Restart Claude Code to pick up new settings"
echo "  2. Add init blocks to your SKILL.md files (see README.md)"
echo ""
echo "To uninstall: bash $(dirname "$0")/uninstall.sh"
