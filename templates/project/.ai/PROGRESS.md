# Project progress

> Main cross-session handoff file. Read it at the start of every session; update it before the session ends.
> Last updated: <!-- YYYY-MM-DD, filled in by the agent -->
>
> **Size limits (/wrap enforces them with `wc -l` / `grep -c`, not by eye):**
> Whole file ≤ 120 lines; "Current status" ≤ 10 lines; "Progress log" keeps only the latest 10 entries.
> Over the limit: **append** the extra "Progress log" entries to `.ai/archive/PROGRESS-YYYY-MM.md`
> (named by the year and month of archiving; create the directory if missing). The original text goes to the archive; this file keeps only a compressed one-line summary.
> The structure is fixed to the six sections below. If it drifts (extra top-level date sections, etc.), restore the structure before updating.
> Why: this handoff file is read at the start of every session, so its size directly consumes context. Historical detail lives in git log and the archive.

## Current status

<!-- ≤10 lines. What stage the work is in overall and where it is stuck. Keep in-progress items and warning states
     (not pushed / not deployed / not verified on a real device / release forbidden). Drop implementation detail (it lives in the archive and commits). -->

## Next steps

<!-- 1-3 concrete items you can start on immediately. Not vague goals. -->
<!-- Example: implement the NMS post-processing step of the person detection pipeline -->

## Task list

<!-- Check off only items verified end to end. Code written is not done. -->

- [ ] Task A
  - [ ] Subtask A1
  - [ ] Subtask A2  ← current
- [ ] Task B

## Open issues

<!-- Items that are stuck, need a user decision, or depend on something external. One line each; when one grows long, move the original text to the archive. -->

## User corrections (pending distillation)

<!-- User corrections to the agent's approach in this session, one per line: date — what the user corrected → what to do instead.
     Cleared after /distill consumes them (content moves to the archive). Leave empty if none. -->

## Progress log

<!-- Reverse chronological, newest first. One line each: date + what was done. Keep only the latest 10; older entries go to the archive. -->

- YYYY-MM-DD —
