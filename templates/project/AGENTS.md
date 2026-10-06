# AGENTS.md

This repository is maintained by AI coding agents working together. Before starting any work, every agent reads project memory as described below.

> CLAUDE.md is a symlink to this file. Claude Code, Codex and other agents all read the same content.

## Project overview

<!-- One or two sentences: what this project is and its current stage. -->

## Build / test / run

<!-- Put commands here that an agent cannot guess. If there are none, leave this empty. Do not invent any. Examples: -->
<!-- - Install: `pnpm install` -->
<!-- - Test: `pnpm test` -->
<!-- - Start: `pnpm dev` -->

## Required reading before work

Read these files in order to restore project state in seconds:

1. `.ai/PROGRESS.md` — current progress, where the last session stopped, next steps, open items
2. The "Build / test / run" section of this file

Read when relevant:

- `.ai/DECISIONS.md` — past decisions on architecture, technology choices and product direction
- `.ai/GOTCHAS.md` — gotchas hit, approaches that failed, paths not to retake

## Working protocol

- Keep changes strictly within the user's current request. Do not expand scope on your own; if scope must grow, explain why first.
- Read the existing implementation before changing code. Do not change code based on file names or guesses.
- A task can be marked done only after it is implemented **and verified**. Code written is not done.

## Project memory protocol

After meaningful progress, update `.ai/PROGRESS.md`: what changed this session, current status, suggested next steps, open issues.

When an important decision is made, append it to `.ai/DECISIONS.md` (append-only): context, what was chosen, rejected alternatives, rationale.

When you hit a gotcha or an approach fails, append it to `.ai/GOTCHAS.md` (append-only): what you tried, why it failed, what to do next time.

> These three files carry work across sessions. Progress not written to a file is lost in the next session.

## Communication

- Reply in the language the user writes in (default English). Code identifiers, technical terms, error messages, commands, paths and framework names stay as written.
- When reporting code changes, state which files changed and why.
- When blocked, state the blocker and give the smallest next step.
