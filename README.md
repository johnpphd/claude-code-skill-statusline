# Claude Code Skill Statusline

Show which skill is active in your Claude Code statusline -- with correct session isolation when running multiple sessions simultaneously.

```
██ dev ~/my-project [main] 8a3f1c02 /agent-orchestrator [general-purpose] Opus 4.6 $1.23 [ctx:45.2k in:602.1k out:89.3k]
||  |       |         |      |         |                    |               |        |          |
project user cwd    branch session   skill              agent type       model     cost      tokens
color
```

## Install

```bash
git clone https://github.com/johnpphd/claude-code-skill-statusline.git
cd claude-code-skill-statusline
bash install.sh
```

This installs to `~/.claude/` (user-level, works across all projects):

- Copies scripts to `~/.claude/scripts/statusline/`
- Merges hooks into `~/.claude/settings.json` (preserves your existing hooks)
- Sets `statusLine` in `~/.claude/settings.json`

Restart Claude Code after installing.

## Uninstall

```bash
bash uninstall.sh
```

Removes scripts, hooks, and statusLine. Preserves all other settings.

## Upgrading

Pull and re-run `bash install.sh`. The installer removes the old PostToolUse Bash hook (`copy-skill-to-session.sh`) and adds the new ones.

Older versions needed a `<skill-init>` block at the top of every SKILL.md. Hooks now record the active skill, so delete those blocks. A leftover block does no harm, but nothing reads the file it writes.

## The Problem

The statusline should show the skill each session is running. When two sessions run in the same project, a single shared marker file lets Session A show Session B's skill. The marker has to be keyed by session ID.

## How It Works

Two hooks write the marker, because a skill starts in one of two ways:

```
PreToolUse hook, matcher Skill (mark-skill-active.sh)
  fires when the model loads a skill
  reads session_id and tool_input.skill from hook JSON
  writes -> /tmp/.claude-<hash>/.claude-skill-active-<session_id>

UserPromptSubmit hook (mark-skill-on-prompt.sh)
  fires when the user types "/name args", which makes no Skill tool call
  parses the leading /name from the prompt
  writes the same marker only if name is a real skill or command on disk

Statusline (statusline.sh)
  reads .claude-skill-active-<session_id> for its own session_id

SessionStart hook (session-cleanup.sh)
  clears this session's marker on a fresh start (kept on resume and compact)
  sweeps markers older than 7 days
```

The last skill invoked wins. The disk check reads `.claude/skills/<name>/SKILL.md` and `.claude/commands/<name>.md` in the project, then the same under `~/.claude`. A prompt like "/tmp is full" matches neither and leaves the marker alone. Plugin skills (`plugin:skill`) skip the disk check and show their full name.

## Dead Ends We Tried

These approaches don't work. Documenting them here to save you the debugging time.

| Approach | Why It Fails |
|----------|-------------|
| PPID as session key | Claude Code spawns `bash -c "bash hook.sh"`. PPID = ephemeral intermediate shell PID, not Claude Code PID. Different every invocation. |
| `CLAUDE_SESSION_ID` env var | Exists but **empty** in v2.1.x. Not populated in the Bash tool environment. |
| Two hooks under one matcher | They **share stdin**. First hook does `cat`, consumes everything. Second hook gets empty input. |

## Customization

### Segments

Edit `scripts/statusline.sh` (or `~/.claude/scripts/statusline/statusline.sh` after install) to add, remove, or reorder segments. Each segment is a `printf` call with ANSI color codes.

### Colors

The default color scheme uses 256-color ANSI codes:

| Segment | Color Code | Description |
|---------|-----------|-------------|
| Project color | hash-derived | Unique per directory name |
| Username | 243 | Gray |
| Session ID | 67 | Dim cyan |
| Working dir | 197 | Magenta |
| Git branch | 39 | Cyan |
| Active skill | 114 | Muted green |
| Agent type | 214 | Orange |
| Model | 103 | Muted purple |
| Cost | 178 | Yellow |
| Token usage | 245 | Light gray |

### Project Color Indicator

The `██` block at the start of the statusline is colored uniquely per project directory name. The color is derived by triple-hashing the directory basename using a djb2-variant hash, then mapping the resulting hex color to the nearest 256-color ANSI index. Brightness is clamped so the block is readable on dark terminals. The same directory name always produces the same color.

### JSON Parser

The scripts use `python3` to parse hook JSON and `jq` for statusline field extraction.

## Requirements

- **bash** (4.0+)
- **python3** -- for JSON parsing in hooks (available on macOS and most Linux)
- **jq** -- for JSON field extraction in the statusline ([install](https://jqlang.github.io/jq/download/))
- **Claude Code** with `statusLine`, a `PreToolUse` hook that fires on the Skill tool, `UserPromptSubmit` hooks, and `session_id` in hook JSON

## Compatibility

- **macOS**: Uses `md5 -q` for hashing. Tested on macOS 14+.
- **Linux**: Falls back to `md5sum`. Should work on any distro with bash 4+ and python3.

## Related Claude Code Issues

- [#10052](https://github.com/anthropics/claude-code/issues/10052) -- Expose current agent information for external monitoring
- [#7881](https://github.com/anthropics/claude-code/issues/7881) -- SubagentStop hook cannot identify which specific subagent finished
- [#14859](https://github.com/anthropics/claude-code/issues/14859) -- Agent hierarchy in hook events
- [#18022](https://github.com/anthropics/claude-code/issues/18022) -- Add session name to statusline JSON input

## License

MIT
