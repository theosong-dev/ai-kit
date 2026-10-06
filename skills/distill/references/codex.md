# Codex Routing and Verification

Read only when the current host is Codex. Before configuring, check the current Codex version and the official manual; do not copy the Claude schema.

- Lifecycle / tool interception: configure `~/.codex/hooks.json` with the currently supported events. New or modified unmanaged hooks require trust review; until trusted, do not claim they are in effect and do not bypass the review.
- Command policy outside the sandbox: use `~/.codex/rules/*.rules`, expressing allow, prompt, or forbid with the currently supported rule syntax. It is not equivalent to Claude's `permissions.deny`, nor a general interceptor for all in-sandbox operations. First confirm the target operation actually goes through this mechanism; where it does not, evaluate the sandbox configuration or a supported tool hook.
- Directory requirements: use a subdirectory `AGENTS.md`; do not treat `.claude/rules` `paths:` as a format Codex supports automatically. File-type requirements can go into the corresponding directory rules or an on-demand skill, with the scope stated.
- Present the minimal diff and scope of impact first, land only the specific authorized changes, and do not loosen permissions for other commands along the way.
- Signal log (signals.sh) and raw transcript tracing: Codex has no such input; skip.
- Check rules with the locally supported `codex execpolicy check` against matching and non-matching cases (check `--help` for arguments first), then verify actual execution behavior. Verify hooks with real events after the trust requirements are met. A configuration that parses does not mean blocking is in effect; when trust or an actual invocation is missing, report it truthfully as unverified.
