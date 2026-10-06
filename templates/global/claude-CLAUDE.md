# Claude Code global entry file

> Template: install to `~/.claude/CLAUDE.md`. The agents below (`*-implementer*`, `verifier`) and hooks are installed into `~/.claude/` by ai-kit.

Before starting work, read `~/.ai/AGENTS.md` and follow its shared preferences and working protocol. This file adds Claude Code execution config. Project rules still take precedence per the shared protocol.

## Implementation and verification

- The main session's model and effort are set in `settings.json` (choose per your situation). The main session only plans, writes briefs and runs verification; implementation goes to subagents.
- Effort can only be set in agent file frontmatter and cannot be set per brief, so there is one agent per tier; pick by name in the brief. Effort buys more verification and edge case coverage; it does not fix a wrong direction. Choose the tier by how many hidden edge cases there are and how costly a mistake is, not by task size:
  - `sonnet-implementer` (`model: sonnet`, `effort: medium`): fully specified mechanical tasks touching one or a few files.
  - `opus-implementer` (`model: opus`, `effort: medium`): routine implementation with a clear plan that spans files and needs more context. Use this when unsure.
  - `opus-implementer-high` (`effort: high`): plans that leave room for judgment, need tradeoffs between implementation paths, or have a high cost of error.
  - `opus-implementer-xhigh` (`effort: xhigh`): non-obvious bugs, concurrency/consistency issues, core-path refactors. Use only on clearly hard tasks. If the same problem fails twice, return to the main session to redo the plan; do not move up another tier.
- Before moving up a tier, first give the implementer a self-check in the brief (a test, build or command it can run): one check costs one round; a higher tier costs more thinking every round.
- Every implementer agent's output goes through the verifier.
- Verification uses `~/.claude/agents/verifier.md`: read-only, no implementation history; give it only the task requirements, the diff/files to verify and the verification criteria.
- Walk through user-visible UI changes in a real browser with `claude-in-chrome`.

## Remote and deployment

- Allow rules for `ssh / scp / rsync` and each repo's deploy scripts live in `permissions.allow` in `~/.claude/settings.json`; the actual config is authoritative. When adding a deploy script, add its rule to the same file.
- Use ssh as `ssh <alias> '<cmd>'` (aliases in `~/.ssh/config`), not `ssh -o … user@IP`. Call deploy scripts directly without a `cd` prefix so allow rules match.

## auto classifier

- The classifier reliably blocks three categories: reading/writing browser cookies / login state / credential sync; cloning and running third-party code, or opening Chrome remote debugging; writing to user config such as `~/.ai` or `~/.zshrc`, and changing the frontmatter of `~/.claude/agents/*.md` (the body can be edited directly). For these three, do not try first yourself; give the user a pasteable command to run with `!`, and read `--help` first to confirm the input format.
- Tools that need a lasting allowance go through `permissions.allow` (allow is checked before the classifier); do not work around it by changing prompts.

## Shared skills

- `wrap` and `distill` share the body under `~/.agents/skills/`. Locate scripts from the directory of the `SKILL.md` you read this time, and pass the target project root explicitly; do not rely on host environment variables.
- After these files are updated, sessions that already read the old content should reread the relevant file, or use a new session.
