# Project progress

> Main cross-session handoff file. Read it at the start of every session, update it before ending.
> Last updated: 2026-10-06
>
> **Size limits (/wrap enforces them with `wc -l` / `grep -c`, not by eyeballing):**
> Whole file ≤ 120 lines; "Current status" ≤ 10 lines; "Progress log" keeps only the latest 10 entries.
> If over the limit: **append** the surplus "Progress log" entries to `.ai/archive/PROGRESS-YYYY-MM.md`
> (named by the year and month of archiving; create the directory if missing). The original text goes into the archive, and this file keeps only a compressed one-liner.
> The structure is fixed at the six sections below; if you see drift (extra top-level dated sections, etc.), put things back in place before updating.
> Reason: this is the handoff file read at the start of every session, so its size comes straight out of context; history details live in git log and the archive.

## Current status

- 2026-10-06 Switched the default language to English; the Chinese versions are kept under `zh-CN/` (install with `--lang zh-CN`).
- 2026-10-06 Upgraded from the June "three-file template + wrap" to a full toolkit: added `templates/` (project / global templates), `skills/` (wrap, distill), `claude/` (tiered implementer agents, verifier, hooks, settings snippets), `mods/`, `docs/`.
- The global entry is now "shared preferences in `~/.ai/AGENTS.md` + a thin entry per host"; the repo-root `AGENTS.md` / `.ai/` are this repository's own real memory.
- No end-to-end install verification on a new machine yet; Windows / Git Bash untested.

## Next steps

- On a clean machine (or a fresh temporary HOME), walk through the install end to end following the README, and confirm that both Claude Code and Codex can read the entry files and that wrap / distill work.
- Verify `install.sh` symlink and path handling under Windows / Git Bash; if it does not work, state in the README that it is unsupported.

## Task list

- [x] Move templates into `templates/`; repo root becomes real memory
- [x] Remove private details from the global templates (shared preferences + Claude / Codex entries)
- [ ] End-to-end install verification on a new machine
- [ ] Windows / Git Bash verification

## Open issues

## User corrections (pending distillation)

## Progress log

- 2026-10-06 — Switched the default language to English: templates, skills, agents, hooks, installer output and docs; Chinese versions kept under zh-CN/ (install with --lang zh-CN).
- 2026-10-06 — Upgraded to a full toolkit: templates moved into templates/, global entry split into shared preferences + a thin entry per host, repository's own memory filled in
