# Codex global entry file

> Template: install to `~/.codex/AGENTS.md`. Mirrors the structure of the Claude Code entry file (`claude-CLAUDE.md`) and holds only Codex-specific execution config.

Before starting work, read `~/.ai/AGENTS.md` and follow its shared preferences and working protocol. This file adds Codex execution config. Project rules still take precedence per the shared protocol.

## Implementation and verification

- The main session owns planning, discussion, solution design and final calls; concrete implementation goes to native subagents or independent workers. Keep the main session model unchanged.
- Choose the implementer model and effort by spec clarity, hidden edge cases and cost of error, not by task size: routine cross-file implementation uses the latest model available on the current host with effort `medium`; use `high` when there is room for judgment, a high cost of error or many edge cases, and `xhigh` for clearly hard tasks. If the same problem fails twice, return to the main session to redo the plan; do not move up another tier.
- If a cheaper external worker (your own CLI) is available, you may hand it simple, clear, checkable mechanical implementation or simple verification. The task file states context, goal, constraints, relevant files and verification criteria; the worker does not inherit main session history. Read-only by default; grant write access explicitly when it must change files. Check exit codes and returned results; a successful call is not a passed verification.
- Before a brief, write out implicit assumptions and possibly missed edge cases, and give the implementer a self-check (a test, build or command it can run) — one check costs one round; a higher tier costs more thinking every round.
- The independent verifier stays read-only and receives only the task requirements, the diff/files to verify and the verification criteria, never implementation history or conclusions. Complex verification uses a native subagent on the current latest model with effort `high`, created without session history (set `fork_turns` to `none` when the tool supports it). When model and `reasoning_effort` must be set explicitly, do not use a full-history fork plus override.
- When a worker call fails or the result does not meet requirements, first fix the task description or add context based on the error, then decide whether to retry or switch models. Must not retry blindly, and must not mark failed or unverified results as done.
- To fix a bug, reproduce it first; where applicable, confirm the regression test fails on unfixed code. Checks must cover the real path of the change: a syntax check is not functional verification, a command that never started has not run, and when something cannot run, state the limitation.
- For user-visible UI changes, use the currently available Browser or Chrome skill, read its instructions, and walk through the change in a real browser.
- Do not treat Claude model names or agent files as Codex config.
- Trivial-change exception (pure conversation, code-reading Q&A, trivial one- or two-line changes): per the shared protocol, the main session handles these directly, with no worker and no verifier.

## Model resolution

- For every brief, confirm the latest callable full model ID and its effort support from the available model list / tool schema provided by the current host. Do not hardcode version numbers, and do not assume aliases such as `latest` exist.
- An old model still being in the available list does not make it the latest; compare version numbers numerically, not as strings.
- If the available list is missing, must not guess model IDs; say so explicitly and use the current host's default model.

## Permissions and execution

- Use Codex's current sandbox, approval and rules config. Claude's `permissions.allow` / `permissions.deny` do not apply in Codex; must not claim a command is allowed based on them.
- Continue authorized remote and deploy tasks. When the execution environment requires escalated approval, request it through the tool; do not hand the command to the user to run by hand.
- Do not create hooks or loosen permissions just because you read this file. `~/.codex/rules/*.rules` governs commands outside the sandbox and is not equivalent to Claude's deny list; configure hooks according to current Codex support and trust requirements.

## Shared skills

- `wrap` and `distill` share the body under `~/.agents/skills/`; do not maintain an older same-named `~/.codex/skills/wrap`.
- Locate scripts by absolute path from the directory of the `SKILL.md` you read this time, and pass the target project root explicitly; do not rely on host environment variables.
- After these files are updated, sessions that already read the old content should reread the relevant file, or use a new session.
