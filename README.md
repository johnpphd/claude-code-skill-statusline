# Claude Code Skill Statusline

Show which skill is active in your Claude Code statusline -- with correct session isolation when running multiple sessions simultaneously.

```
dev 8a3f1c02 ~/my-project [main] /agent-orchestrator [general-purpose] Opus 4.6 $1.23 [ctx:45.2k in:602.1k out:89.3k]
 |    |          |          |        |                    |               |        |          |
 user session    cwd     branch    skill              agent type       model     cost      tokens
```

## Install

```bash
git clone https://github.com/jpearson/claude-code-skill-statusline.git
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

## SKILL.md Init Block

For skills to appear in the statusline, each SKILL.md needs a one-liner init block at the top:

```markdown
<skill-init>
Run this command silently at skill load: `_d="/tmp/.claude-$(printf '%s' "${CLAUDE_PROJECT_DIR:-$(pwd)}" | (md5 -q 2>/dev/null || md5sum | cut -d' ' -f1) | cut -c1-12)"; mkdir -p "$_d" 2>/dev/null; echo "my-skill-name" > "$_d/.claude-skill-active"`
</skill-init>
```

Replace `my-skill-name` with the skill's display name (e.g., `agent-orchestrator`, `verify`).

See [`skills/example-skill/SKILL.md`](skills/example-skill/SKILL.md) for a working example.

## The Problem

Claude Code skills write their name to a temp file via a SKILL.md init block. When two sessions run in the same project, they overwrite the same file -- Session A shows Session B's skill.

The obvious fix is to key the file by session ID. But **the Skill tool is internal to Claude Code** -- PreToolUse and PostToolUse hooks never fire for it. There's no direct hook observability into skill activation.

## How It Works

```
SKILL.md init block (Bash tool)
  writes -> /tmp/.claude-<hash>/.claude-skill-active  (project-scoped, shared)

PostToolUse Bash hook (copy-skill-to-session.sh)
  detects write via "> " pattern in raw JSON
  reads session_id from hook JSON
  copies -> .claude-skill-active-<session_id>  (session-keyed, isolated)

Statusline (statusline.sh)
  extracts session_id from statusline JSON
  reads .claude-skill-active-<session_id> first
  falls back to .claude-skill-active if no session-keyed file

SessionStart hook (session-cleanup.sh)
  clears stale skill files on new session start
```

**Key insight:** The SKILL.md init block runs as a Bash tool call. PostToolUse hooks DO fire for the Bash tool, and hook JSON includes `session_id`. So we intercept the init block's Bash command, extract the session ID, and copy the shared file to a session-keyed path.

### End-to-End Flow

```
Session A invokes /my-skill:
  1. Skill tool fires (internal -- no hooks)
  2. SKILL.md init block runs as Bash tool
  3. Bash writes "my-skill" to .claude-skill-active
  4. PostToolUse Bash hook fires, detects "> " + ".claude-skill-active"
  5. Extracts session_id from JSON, copies to .claude-skill-active-<A>
  6. Statusline reads .claude-skill-active-<A> -> shows /my-skill

Session B invokes /other-skill:
  1-5. Same flow, writes .claude-skill-active-<B>
  6. Session A still shows /my-skill. Session B shows /other-skill.
```

## Dead Ends We Tried

These approaches don't work. Documenting them here to save you the debugging time.

| Approach | Why It Fails |
|----------|-------------|
| PreToolUse/PostToolUse Skill hooks | Skill tool is internal to Claude Code. Hooks **never fire**. Confirmed with debug file writes -- zero output. |
| PPID as session key | Claude Code spawns `bash -c "bash hook.sh"`. PPID = ephemeral intermediate shell PID, not Claude Code PID. Different every invocation. |
| `CLAUDE_SESSION_ID` env var | Exists but **empty** in v2.1.x. Not populated in the Bash tool environment. |
| Two hooks under one matcher | They **share stdin**. First hook does `cat`, consumes everything. Second hook gets empty input. |
| Pattern matching on `echo "` in JSON | JSON escapes quotes as `\"`. Pattern `*'echo "'*` doesn't match `echo \"` in raw JSON. |
| Broad pattern `*.claude-skill-active*` | Triggers on `cat` and `ls` commands that READ the file, not just writes. Overwrites session-keyed file with stale data. |

## Customization

### Segments

Edit `scripts/statusline.sh` (or `~/.claude/scripts/statusline/statusline.sh` after install) to add, remove, or reorder segments. Each segment is a `printf` call with ANSI color codes.

### Colors

The default color scheme uses 256-color ANSI codes:

| Segment | Color Code | Description |
|---------|-----------|-------------|
| Username | 243 | Gray |
| Session ID | 67 | Dim cyan |
| Working dir | 197 | Magenta |
| Git branch | 39 | Cyan |
| Active skill | 114 | Muted green |
| Agent type | 214 | Orange |
| Model | 103 | Muted purple |
| Cost | 178 | Yellow |
| Token usage | 245 | Light gray |

### JSON Parser

The scripts use `python3` for session ID extraction (from hook JSON) and `jq` for statusline field extraction.

## Requirements

- **bash** (4.0+)
- **python3** -- for JSON parsing in hooks (available on macOS and most Linux)
- **jq** -- for JSON field extraction in the statusline ([install](https://jqlang.github.io/jq/download/))
- **Claude Code** v2.1+ -- for `statusLine`, `PostToolUse` hooks, and `session_id` in hook JSON

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
