---
name: wrap
description: "At the end of a session, distill this conversation into .ai/PROGRESS.md, and when there were decisions / failed approaches / user corrections, sync .ai/DECISIONS.md, .ai/GOTCHAS.md and the PROGRESS \"User corrections (pending distillation)\" section. Trigger when the user says \"wrap up\", \"update progress\", \"end of session\", or \"tidy up before we stop\" (the Chinese triggers 「收尾」「更新进度」 apply too). Refreshes Current status / Next steps / Open issues, checks off end-to-end-verified tasks, adds one Progress log line, then runs check_size.sh for a deterministic size and structure check and, on OVER/DRIFT, restores or archives per its output. Not for: promoting lessons into reusable rules (use /distill), writing code, or changing features."
---

# Session wrap-up protocol

This skill is the shared trigger, for Claude Code and Codex, of the "Project memory protocol" in AGENTS.md.
AGENTS.md is the source of truth; this file only turns that protocol into a single wrap action.

Section names below use the English template titles; the matching sections of the Chinese template (当前状态 / 下一步 / 任务清单 / 遗留 / 待澄清 / 用户纠正（待蒸馏） / 进度日志, and the 最后更新 date line) are recognized the same way.

## Steps

1. Review the session and separate four kinds of information:
   - **Progress**: what got done, current status, next steps, newly added open issues.
   - **Decisions**: technical / product choices that will affect later work.
   - **Gotchas**: approaches that were tried and failed.
   - **Corrections**: places in this conversation where the user explicitly said the agent did something wrong / too much / too little / in the wrong direction. Write nothing if there were none.

2. Update `.ai/PROGRESS.md`:
   - Refresh "Current status", "Next steps", and "Open issues".
   - Add one line at the top of "Progress log" (date + one sentence).
   - Append this session's corrections to the "User corrections (pending distillation)" section (one line each: date -- what the user corrected -> what to do instead). Leave the section alone if there were none.
   - Check off items in "Task list" that are **verified end to end**; leave unverified items unchecked.
   - Update the "Last updated" date at the top.

3. **Size / structure check (deterministic command, not eyeballing).** After writing, treat the directory containing the `SKILL.md` you read this time as the skill root, run the script by absolute path, and pass the target project root explicitly (quote both paths):

   `bash "<SKILL_ROOT>/scripts/check_size.sh" "<PROJECT_ROOT>"`

   Replace the placeholders with real absolute paths; do not rely on the current working directory or on environment variables injected by the host. The script supports project paths containing spaces.

   Act on its output (limits, section-name rules, and the OK / OVER criteria all live in the script and are not repeated here):
   - Any item **OVER**: **append** the excess "Progress log" entries to `.ai/archive/PROGRESS-YYYY-MM.md` (named by the year-month of archiving; `mkdir -p` if the directory is missing). The archive keeps the full original text; this file keeps one compressed line. If "Current status" is over, compress it, keeping in-progress items and warning states (not pushed / not verified / do not release) and dropping implementation details.
   - Structure **DRIFT** (missing / duplicated / extra top-level section): restore first -- compress the extra section's information into one Progress log line and move its original text into the archive; add missing sections back from the template.
   - After restoring / archiving, **run the script again and confirm exit 0**, then write this session's update.
   - Rationale: PROGRESS is the handoff file read at the start of every session, so its size eats context directly; the history is in git log and the archive.

4. Only if there really was a decision this session, append it to `.ai/DECISIONS.md` (append-only), following its template: context, what was chosen, alternatives rejected, risks.

5. Only if there really was a failed approach this session, append it to `.ai/GOTCHAS.md` (append-only), following its template: what was tried, result, cause, current approach.

6. **Distill reminder**: from the skill root you read this time, locate the collector of the sibling shared skill and run `bash "<SKILL_ROOT>/../distill/scripts/pending.sh" "<PROJECT_ROOT>"` (replace the placeholders with real absolute paths). Run only the deterministic collector script; do not start the distill flow. Take `count` from output [1] GOTCHAS and `lines` from [3] user corrections and add them with an arithmetic command; do not count template headings or entries already marked distilled.
   If the total is >= 8, end the wrap-up report with one line: "N undistilled lessons have accumulated; consider running /distill". **Only remind; never run it automatically.**

## Notes

- No decision, no DECISIONS entry; no gotcha, no GOTCHAS entry; no correction, no "User corrections" entry. Better empty than padded.
- Make the distilled content concrete and actionable; no filler like "keep pushing forward".
- After updating, briefly report which files changed; do not repeat their contents.

## Bundled script

- `scripts/check_size.sh [PROJECT_ROOT]` -- the step 3 size / structure check, bash + awk, target project root passed explicitly; exit 1 on OVER or DRIFT.
