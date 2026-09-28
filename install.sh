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
cp "$REPO_DIR/scripts/mark-skill-active.sh" "$INSTALL_DIR/"
cp "$REPO_DIR/scripts/mark-skill-on-prompt.sh" "$INSTALL_DIR/"
cp "$REPO_DIR/scripts/session-cleanup.sh" "$INSTALL_DIR/"
cp "$REPO_DIR/scripts/statusline.sh" "$INSTALL_DIR/"
# Older versions installed this script. Its hook entry is removed below.
rm -f "$INSTALL_DIR/copy-skill-to-session.sh"
chmod +x "$INSTALL_DIR"/*.sh

# --- Merge settings.json ---

# The hooks and statusLine we want to add. settings-example.json is the single
# source, so the documented example and the install cannot drift.
STATUSLINE_HOOKS=$(cat "$REPO_DIR/settings-example.json")

if [ ! -f "$SETTINGS" ]; then
  info "Creating $SETTINGS"
  echo "$STATUSLINE_HOOKS" | jq '.' > "$SETTINGS"
else
  info "Merging hooks into $SETTINGS"

  # Back up existing settings
  cp "$SETTINGS" "$SETTINGS.bak"
  info "Backup saved to $SETTINGS.bak"

  # Merge using jq:
  # - Drop the PostToolUse Bash hook that older versions installed. Its script
  #   no longer exists, so leaving the entry would fail on every Bash call.
  # - For each hook event we own, append our entry unless its command is
  #   already present, so re-running the installer adds no duplicates.
  # - Set statusLine (overwrites any existing statusLine)
  jq --argjson new "$STATUSLINE_HOOKS" '
    def has_command($cmd):
      any(.[]; .hooks[]? | .command == $cmd);

    def add_event($event):
      ($new.hooks[$event][0].hooks[0].command) as $cmd |
      .hooks[$event] //= [] |
      if (.hooks[$event] | has_command($cmd)) then .
      else .hooks[$event] += $new.hooks[$event]
      end;

    .hooks //= {} |

    (if .hooks.PostToolUse then
      .hooks.PostToolUse |= (
        map(.hooks |= map(select(.command != "bash ~/.claude/scripts/statusline/copy-skill-to-session.sh")))
        | map(select(.hooks | length > 0))
      ) |
      (if .hooks.PostToolUse == [] then del(.hooks.PostToolUse) else . end)
    else . end) |

    add_event("SessionStart") |
    add_event("PreToolUse") |
    add_event("UserPromptSubmit") |

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
echo "  2. If you used an older version, delete the <skill-init> block from"
echo "     your SKILL.md files. Hooks now record the active skill, so the block"
echo "     is dead code."
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
