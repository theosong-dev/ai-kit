# Claude Code Routing and Verification

Read only when the current host is Claude Code.

- Lifecycle actions: use hooks in `settings.json` per the existing configuration, or skill / agent frontmatter hooks supported by the host.
- Forbidden operations: evaluate `permissions.deny` or a `PreToolUse` hook; an existing `~/.claude/hooks/guard.sh` can serve as a reference, but read its implementation before modifying it. Do not assume text rules can block tools.
- File-type conditions: `.claude/rules/*.md` with `paths:` can be used; for directory requirements prefer a shared subdirectory `AGENTS.md`, make sure Claude's corresponding entry point reads it, and reference it from a subdirectory `CLAUDE.md` if needed.
- Permission configuration only takes effect in Claude Code; do not convert it into an already-authorized declaration for Codex.
- Tracing raw transcripts from the signal log (step 2): the path is `<config dir>/projects/<session cwd with / and other non-alphanumeric characters replaced by ->/<session id>.jsonl`, where the config dir is `~/.claude` or `CLAUDE_CONFIG_DIR`; the log's `account` field is the config dir name without the leading dot (`claude-2` -> `~/.claude-2`). Subagent transcripts are at `<session id>/subagents/agent-<agentId>.jsonl`. signals.sh gives only the first 8 characters of the session id; locate the file with `ls <config dir>/projects/*/<first 8 chars>*.jsonl`; grep only for the failed command or error text and read the surrounding excerpt, do not read it in full.
- Exact schema / version capabilities follow the local CLI and current official documentation. After a configuration change, verify with a real trigger and with matching / non-matching command cases; if a reload is needed, start a new session. `/doctor` can help diagnose, but passing it does not replace verifying the blocking behavior. Explicitly list any check not run as unverified.
