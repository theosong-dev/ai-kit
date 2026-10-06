# AGENTS.md

This repository is maintained collaboratively by AI coding agents. Before starting any work, read the project memory following the protocol below.

> CLAUDE.md is a symlink to this file. Claude Code, Codex and other agents read the same content.

## Project overview

A public toolkit for cross-tool AI collaboration: project-memory and global entry-file templates (`templates/`), shared skills (`skills/`: wrap / distill), Claude Code agents and hooks (`claude/`), mods (`mods/`), guides (`docs/`), and install scripts (`install.sh`, `scripts/`, `shell/`).

This is a **public repository**: no commit may contain private project names, absolute home-directory paths (write `~/…` or `$HOME`), secrets, or personal account information. Grep before committing.

## Build / test / run

- Install dry run (writes nothing): `bash install.sh --dry-run`
- Isolated install: `HOME=$(mktemp -d) bash install.sh`, then inspect the artifacts under that temporary HOME; do not try new changes against the real HOME
- Installer tests (fake HOME, never touches the real home directory): `bash tests/install_test.sh`
- Hook tests: `bash claude/hooks/guard_test.sh`
- Mod tests: `claude plugin test ./mods/turn-signals`
- Skill fixtures: run the commands in `skills/wrap/tests.md` and `skills/distill/tests.md`

## Read before starting

Read these files in order to restore project state in seconds:

1. `.ai/PROGRESS.md` — current progress, where the last session stopped, next steps, open items
2. The "Build / test / run" section of this file

Read when relevant:

- `.ai/DECISIONS.md` — past decisions on architecture, technology choices, product direction
- `.ai/GOTCHAS.md` — pitfalls hit, failed approaches, roads not to retake

## Working protocol

- Keep changes strictly within the user's current request; do not expand scope on your own. If scope needs to grow, explain why first.
- Read the existing implementation before changing code; do not edit based on file names or guesses.
- A task counts as done only once it is implemented **and verified**; written code is not done.

## Project memory protocol

After meaningful progress, update `.ai/PROGRESS.md`: what changed, current status, suggested next steps, open issues.

When an important decision is made, append it to `.ai/DECISIONS.md` (append-only): context, what was chosen, alternatives rejected, reasons.

When you hit a pitfall or an approach fails, append it to `.ai/GOTCHAS.md` (append-only): what was tried, why it failed, what to do instead.

> These three habits are what carry work across sessions. Progress not written to a file is lost by the next session.

## Communication

- Reply in the language the user writes in; commands, paths, code symbols and framework names stay as written.
- When reporting code changes, state which files changed and why.
- When blocked, state the blocker and give the smallest next step.
