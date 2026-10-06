# Decision log

> Append-only. Record any technical / product decision that affects later work.
> Three months from now, this file should make it immediately clear why a choice was made.

<!-- Append new decisions at the top. Template: -->

## 2026-10-06 English by default, Chinese kept as an opt-in mirror

**Chose:** English is the default language. The Chinese text lives under `zh-CN/` and is installed with `install.sh --lang zh-CN`. Scripts are maintained once, emit English output, and accept both English and Chinese section names when parsing.

**Context:** The repository is being promoted to an English-speaking audience. When the files an AI reads are in Chinese, the agent replies in Chinese and English-speaking users cannot maintain the rules.

**Alternatives rejected:** Translating only the README and docs — the installed templates, skills and agents would still be Chinese, so the problem remains. Two complete sets of scripts — double the maintenance for logic that is identical.

**Risks / known costs:** The two bodies of text (English and `zh-CN/`) must be kept in sync. The translated skills / agents were verified only at the format and script level; their behavior has not been compared against the Chinese versions in real long-running tasks.

## 2026-10-06 Templates moved into templates/; global entry split into "shared preferences + a thin entry per host"

**Chose:** Project templates and global templates all live in `templates/`; the repo-root `AGENTS.md` / `.ai/` become this repository's own real memory. The global entry changes from "`~/.claude/CLAUDE.md` and `~/.codex/AGENTS.md` both symlink to `~/.ai/AGENTS.md`" to "`~/.ai/AGENTS.md` holds cross-tool shared preferences, and each host has a thin entry file that references it first and then adds host-specific configuration".

**Context:** In the old design the root files doubled as the new-project template, so the repository's own progress stayed an empty template; with three global symlinks to one file, host-specific content had nowhere to go.

**Why:**
- Host-specific configuration (Claude's implementer agent tiers, `permissions.allow`, hooks; Codex's sandbox and rules) in the shared file would mislead the other host
- The repository needs to record its own progress, decisions and gotchas, and can no longer share files with the templates

**Alternatives rejected:** Keeping the symlinks, or splitting the shared file into per-host sections — every host would read irrelevant content, and it is easy to mistake one host's allowance for authorization on another.

**Risks / known costs:** There are now three entry files; when shared rules change, make sure nothing is duplicated in the thin entries.

<!--
## YYYY-MM-DD Decision title

**Chose:** xxx

**Context:** The problem at the time / what the options were.

**Why:**
- Reason 1
- Reason 2

**Alternatives rejected:** yyy — why it was rejected.

**Risks / known costs:** Hazards this choice introduces (if any).
-->
