# Gotchas

> Append-only. "Tried X, it failed because Y, now we use Z" — the kind of negative knowledge an agent cannot infer by reading the code.
> Write it once and avoid retaking the old road in every future session.

<!-- Append new gotchas at the top. Template: -->

## 2026-10-06 The old install.sh wrote through symlinks when copying skill files with `cp`

**Tried:** The old `install.sh` used `cp` to write the wrap `SKILL.md` to `~/.claude/skills/wrap/SKILL.md`.

**Result:** If that directory was already a symlink to the shared skill (`~/.agents/skills/wrap`), `cp` followed the link and overwrote the shared skill body, so the Codex side was changed too.

**Cause:** `cp` follows directory symlinks when writing to the target path; it does not replace the link itself.

**What to do now:** Check whether the target is a symlink before installing; install skills into the shared directory only, create symlinks in host directories, and never `cp` files into a symlinked directory.

<!--
## Short title

**Tried:** What was done.

**Result:** How it failed / what was observed.

**Cause:** Why it failed (if identified).

**What to do now:** What to use instead / how to work around it.
-->
