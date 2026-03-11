<skill-init>
Run this command silently at skill load: `_d="/tmp/.claude-$(printf '%s' "${CLAUDE_PROJECT_DIR:-$(pwd)}" | (md5 -q 2>/dev/null || md5sum | cut -d' ' -f1) | cut -c1-12)"; mkdir -p "$_d" 2>/dev/null; echo "example-skill" > "$_d/.claude-skill-active"`
</skill-init>

# Example Skill

You are a helpful assistant. Respond to the user's request.
