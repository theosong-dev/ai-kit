# wrap trigger and execution tests

7 test prompts: 3 normal / 2 edge / 2 out-of-scope. Each lists "Expected: trigger / no trigger" and "Execution checkpoints".
Used to regression-check that the description triggers only when it should and that execution follows the six-section structure and size check.

## normal (should trigger)

1. **"Let's wrap up"** (also 「收尾吧」)
   - Expected: trigger
   - Checkpoints: first separate progress / decisions / gotchas / corrections; update the six PROGRESS sections; after writing, run `bash "<SKILL_ROOT>/scripts/check_size.sh" "<PROJECT_ROOT>"` by absolute skill-root path; done only on exit 0.

2. **"Tidy up the progress before we stop"**
   - Expected: trigger
   - Checkpoints: one line (date + one sentence) at the top of Progress log; check off only end-to-end-verified tasks; touch DECISIONS / GOTCHAS / User corrections only when there really was a decision / gotcha / correction.

3. **"wrap up this session"**
   - Expected: trigger
   - Checkpoints: update the "Last updated" date at the top; append this session's user corrections to "User corrections (pending distillation)"; if `check_size.sh` reports OVER, archive first, then write -- do not cram.

## edge (borderline, should still trigger but needs judgment)

4. **"Update progress, though there were no decisions or gotchas this time"**
   - Expected: trigger
   - Checkpoints: update PROGRESS only; do not force DECISIONS / GOTCHAS entries; leave User corrections alone if there is nothing to add.

5. **(in a repo whose Progress log already has 10+ entries) "wrap up"**
   - Expected: trigger
   - Checkpoints: `check_size.sh` prints `Progress log entries : N / 10  OVER` and exits 1; per the output, append the oldest excess entries to `.ai/archive/PROGRESS-YYYY-MM.md` (archive keeps full text, this file keeps one compressed line), rerun the script and confirm exit 0 before writing the update.

## out-of-scope (should not trigger, or should hand off)

6. **"Turn these recurring gotchas into reusable rules"**
   - Expected: no trigger
   - Checkpoints: that is /distill's job; wrap only records to GOTCHAS faithfully, does no distilling or routing, and should point to /distill.

7. **"Fix this bug while you're at it"**
   - Expected: no trigger
   - Checkpoints: wrap does not change feature code or run builds; it only records the wrap-up.

## Script fixtures

- A PROGRESS using the Chinese template headings (`## 当前状态` ... `## 进度日志`) passes the same way as the English one: `Six-section structure : OK`, `Result: OK`, exit 0. Mixed headings (some English, some Chinese) also pass.
- The same logical section appearing twice -- in one language, or once in English and once in Chinese -- reports `DRIFT` with `duplicated: <Section> (x2)`, exit 1.
- English section names match exactly after normalization (trim, collapse spaces, case-insensitive; the corrections section also accepts `## User corrections` and ASCII or full-width parens with any spacing), so `##   CURRENT  Status` and `## User corrections （pending distillation）` still pass. An extra section whose title merely contains a section name -- e.g. `## Notes on progress log`, `## Open issues list`, `## Current status of CI`, `## User corrections policy` -- reports `DRIFT` under `extra top-level ## sections`, not `duplicated`, and its list items are not counted as Progress log entries. (Chinese names keep substring matching, so `## 进度日志备注` still counts as a duplicate 进度日志.)

## Cross-host regression

- Run Claude Code and Codex each in a fixture where cwd is not the target project root and the target path contains spaces; do not rely on a host-injected skill directory variable; check that the same script receives the correct project root.
