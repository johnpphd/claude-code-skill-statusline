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
cp "$REPO_DIR/scripts/_string_to_color.sh" "$INSTALL_DIR/"
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

# --- Optional: shell prompt color indicator ---

SHELL_MARKER="claude-statusline-project-color"

# Detect user's shell and pick the right RC file
_user_shell=$(basename "${SHELL:-/bin/bash}")
case "$_user_shell" in
  zsh)  _rc_file="$HOME/.zshrc" ;;
  bash) _rc_file="$HOME/.bashrc" ;;
  *)    _rc_file="" ;;
esac

if [ -t 0 ] && [ -t 1 ] && [ -n "$_rc_file" ]; then
  # Already installed?
  if [ -f "$_rc_file" ] && grep -q "$SHELL_MARKER" "$_rc_file" 2>/dev/null; then
    info "Prompt color indicator already installed in $_rc_file"
  else
    echo ""
    printf "${YELLOW}[?]${NC} Match your %s prompt to the Claude Code statusline? [y/N] " "$_user_shell"
    read -r reply
    if [[ "$reply" =~ ^[Yy]$ ]]; then
      if [ "$_user_shell" = "zsh" ]; then
        cat >> "$_rc_file" << 'ZSHBLOCK'

# claude-statusline-project-color -- START
# Terminal prompt styled to match Claude Code statusline
# Colors: project=deterministic, user=243(gray), cwd=197(magenta), git=39(cyan)
# (installed by claude-code-skill-statusline)
source ~/.claude/scripts/statusline/_string_to_color.sh
_claude_prompt() {
  local proj_color=$(_project_color256 "${PWD##*/}")
  local p=""
  # Project color block
  p+="%{\033[38;5;${proj_color}m%}██%{\033[0m%} "
  # Username (gray 243)
  p+="%{\033[38;5;243m%}%n%{\033[0m%} "
  # Shortened cwd (magenta 197) -- ~ for $HOME, like statusline
  p+="%{\033[38;5;197m%}%~%{\033[0m%}"
  # Git branch (cyan 39)
  local branch
  branch=$(git --no-optional-locks branch 2>/dev/null | sed -n 's/^\* \(.*\)/\1/p')
  if [ -n "$branch" ]; then
    p+=" %{\033[38;5;39m%}[${branch}]%{\033[0m%}"
  fi
  p+=" \$ "
  echo "$p"
}
setopt PROMPT_SUBST
PROMPT='$(_claude_prompt)'
# claude-statusline-project-color -- END
ZSHBLOCK
      else
        cat >> "$_rc_file" << 'BASHBLOCK'

# claude-statusline-project-color -- START
# Terminal prompt styled to match Claude Code statusline
# Colors: project=deterministic, user=243(gray), cwd=197(magenta), git=39(cyan)
# (installed by claude-code-skill-statusline)
source ~/.claude/scripts/statusline/_string_to_color.sh
_claude_prompt() {
  local proj_color=$(_project_color256 "${PWD##*/}")
  local cwd="${PWD/#$HOME/\~}"
  local p=""
  # Project color block
  p+="\[\033[38;5;${proj_color}m\]██\[\033[0m\] "
  # Username (gray 243)
  p+="\[\033[38;5;243m\]\u\[\033[0m\] "
  # Shortened cwd (magenta 197)
  p+="\[\033[38;5;197m\]${cwd}\[\033[0m\]"
  # Git branch (cyan 39)
  local branch
  branch=$(git --no-optional-locks branch 2>/dev/null | sed -n 's/^\* \(.*\)/\1/p')
  if [ -n "$branch" ]; then
    p+=" \[\033[38;5;39m\][${branch}]\[\033[0m\]"
  fi
  p+=" \$ "
  echo "$p"
}
PROMPT_COMMAND='PS1="$(_claude_prompt)"'
# claude-statusline-project-color -- END
BASHBLOCK
      fi
      _prompt_installed=1
      info "Prompt styled to match Claude Code statusline in $_rc_file"
    else
      info "Skipped shell prompt integration"
    fi
  fi
elif [ -t 0 ] && [ -t 1 ] && [ -z "$_rc_file" ]; then
  warn "Shell '$_user_shell' not supported for prompt integration (zsh and bash only)"
fi

# --- Done ---

info "Installed successfully!"
echo ""
echo "Next steps:"
echo "  1. Restart Claude Code to pick up new settings"
echo "  2. Add skill-init blocks to your SKILL.md files so active skills"
echo "     appear in the statusline. Run this prompt in Claude Code:"
echo ""
echo -e "     ${GREEN}Add the statusline skill-init block to all my SKILL.md files.${NC}"
echo -e "     ${GREEN}See ~/.claude/scripts/statusline/ for the format and${NC}"
echo -e "     ${GREEN}skills/example-skill/SKILL.md for an example.${NC}"
echo ""
echo "     Or manually add this to the top of each SKILL.md:"
echo ""
echo "     <skill-init>"
echo '     Run this command silently at skill load: `_d="/tmp/.claude-$(printf'
echo "     '%s' \"\\\${CLAUDE_PROJECT_DIR:-\\\$(pwd)}\" | (md5 -q 2>/dev/null ||"
echo '     md5sum | cut -d'"'"' '"'"' -f1) | cut -c1-12)"; mkdir -p "$_d"'
echo '     2>/dev/null; echo "SKILL-NAME" > "$_d/.claude-skill-active"`'
echo "     </skill-init>"
if [ "${_prompt_installed:-0}" = "1" ]; then
  echo ""
  echo -e "  ${YELLOW}IMPORTANT:${NC} To activate your new terminal prompt, run:"
  echo ""
  echo -e "    ${GREEN}source $_rc_file${NC}"
  echo ""
  echo "  Or open a new terminal window."
fi
echo ""
echo "To uninstall: bash $(dirname "$0")/uninstall.sh"
