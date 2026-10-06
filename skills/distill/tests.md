# distill trigger and execution tests

7 test prompts: 3 normal / 2 edge / 2 out-of-scope. Each lists "Expected: trigger / no trigger" and "Execution checkpoints".
Used for regression checks that the description triggers only when it should and that execution respects the entry bar and routing.

## normal (should trigger)

1. **"Distill the gotchas we've piled up recently"**
   - Expected: trigger
   - Execution checkpoints: the first step runs `bash "<SKILL_ROOT>/scripts/pending.sh" "<PROJECT_ROOT>"` and `signals.sh` by absolute path to collect input, instead of eyeballing files; signals.sh cross-session groups are leads, and before promoting a rule only the raw record excerpts of the cited sessions are read; only candidates that pass the entry bar are proposed; every proposal carries one sentence on "which real mistake this would have prevented" and cites the source title; proposals not yet approved are shown first and wait for the user to approve them one by one; an explicit approval already given is not re-confirmed.

2. **"Distill these lessons into rules"**
   - Expected: trigger
   - Execution checkpoints: the landing spot is chosen from the routing table (shared skill / AGENTS.md / global / the current host's hook or permission mechanism), not everything stuffed into AGENTS.md; during the proposal stage the target files are also scanned and deletable old rules are flagged (subtraction), and rules whose rationale names a model different from the current one, or that have no rationale and look like compensation for a model weakness, are listed under "to review"; review does not delete directly.

3. **"Tidy up the rules and promote what deserves promoting"**
   - Expected: trigger
   - Execution checkpoints: changes land only after approval; each new or modified rule ends with a one-sentence rationale (year-month, source, model name), written as a comment when it lands in a hook / script / skill; consumed entries get `<!-- distilled YYYY-MM-DD -->` on the line below the title, explicitly skipped ones get `... skipped -->`, and unevaluated / unapproved / still-watching entries get no marker; the "how to verify" sentence goes after the marker; only the user corrections handled this time are archived, unevaluated / unapproved / still-watching ones are kept; one line is added to the progress log.

## edge (borderline, should still trigger but needs judgment)

4. **(at /wrap time the prompt says "12 undistilled lessons have accumulated, consider running /distill", and the user replies) "OK, run it"**
   - Expected: trigger
   - Execution checkpoints: the actual `pending.sh` output is authoritative, not the number in the prompt; candidates that pass the bar may be far fewer than 12 -- only promote what qualifies, leave still-watching entries unmarked; only explicitly skipped entries get `skipped`; do not force promotions to hit a number.

5. **"This gotcha only happened once, but doing it again would ship the wrong version -- can we make a rule?"**
   - Expected: trigger (via the "high cost" bar, not "repeated >= 2 times")
   - Execution checkpoints: accepted under the high-cost bar, not rejected for having happened only once; states "which real mistake this would have prevented"; a "never X / always X" rule like shipping the wrong version preferably lands in a hook or permission mechanism that the current host supports and that actually covers the operation, not as a prompt sentence in AGENTS.md.

## out-of-scope (should not trigger, or should hand off)

6. **"Record this session's progress for me"**
   - Expected: no trigger
   - Execution checkpoints: this is /wrap's job; distill does not record progress, should suggest /wrap instead, and does not touch PROGRESS's current status / progress log.

7. **"Change the code according to this rule"**
   - Expected: no trigger
   - Execution checkpoints: distill only produces rule proposals and landing spots; it does not write business code or run tests; actual code changes go to the implementation flow.

## Cross-host regression

- Each host reads only its own references file; shared landing spots note that they affect both sides. Codex does not write Claude settings.json and does not treat `.rules` as a deny for all tool operations. Codex skips the signal log and raw session record lookups.
- With a path containing spaces and a cwd that is not the project root, the target project is still collected correctly; part 5 shows the three skills entry points separately and must not add symlinked duplicate entries into a deduplicated total.
- Deleting an old rule requires evidence from representative tasks; without evidence, do not delete based on model name or version alone.
- Repeated `refused` entries in the signal log land as permission allowances or a different approach, not as prompt rules.

## Script regression

Rerun after changing `scripts/`. `<D>` is the skill root, `<SP>` is a temp directory; fixture timestamps are generated relative to the current time, no real logs are written.

- `pending.sh`: run `bash <D>/scripts/pending.sh <project-root>` on any project and diff against the output before the change; [1]-[5] stay the same, only an extra [6] at the end is allowed. [6] counts "rationale on the same line / rationale on a continuation line / no rationale / list items inside code blocks and comments" as with / with / without / not counted.
- `pending.sh` word-level duplicate hints for Latin text: create `<SP>/enproj/.ai/` with a `GOTCHAS.md` holding two undistilled entries `## 2026-10-01 deploy script skipped migrations` and `## 2026-10-03 migrations missing on staging deploy`, an empty `DECISIONS.md` (`# Decisions`), and a `PROGRESS.md` whose `## User corrections (pending distillation)` section has `- Always run migrations before deploy (rationale: staging broke twice)` and `- Prefer rsync over scp`. Expect section [4] `Title duplicate hints` to report `pairs: 3`: GOTCHAS 1 <-> GOTCHAS 2 `[shared word: deploy,migrations]`, GOTCHAS 1 <-> the first correction `[shared word: deploy,migrations]`, GOTCHAS 2 <-> the first correction `[shared word: staging,deploy,migrations]`; the rsync line pairs with nothing. [3] shows `lines: 2`.
- `pending.sh` English rationale detection: in the same project add `AGENTS.md` with `- rule one (rationale: 2026-10, incident, opus)` and `- rule two`. Expect [6] `project AGENTS.md       : 2 list-item rules: 1 with rationale / 1 without`. (The `global ~/.ai/AGENTS.md` lines in [5]/[6] depend on the machine and are not compared.)
- `pending.sh` corrections heading and [6] wording: in an English project, `## User corrections (pending distillation)` (or `## User corrections`, any case / spacing / paren width) with 2 list items gives `[3] lines: 2`; renaming the heading to `## User corrections policy` gives `lines: 0`. With exactly one rule in `AGENTS.md`, [6] prints `1 list-item rule: ...` (singular).
- `signals.sh`: `python3 <D>/tests/make_signals_fixture.py <SP>/fx.jsonl /tmp/fixproj`, then `TURN_SIGNALS_PATH=<SP>/fx.jsonl bash <D>/scripts/signals.sh /tmp/fixproj`; expected:
  - `groups: 4`, in order `[1] Bash · error · $ ls` (`count 4 · sessions 3`, with `subagent 1`; a `cd X &&` prefix does not affect grouping), `[2] Bash · interrupted` (no command), `[3] Bash · refused · $ rm`, `[4] Edit · error` (messages with newlines and CJK text, different quoted content merged into one group).
  - Not present: `git push` repeated within only 1 session, another project `/Users/x/other`, the similarly prefixed `fixproj-bar`, the `Read` group from 35/40 days ago.
  - verifier section: `verdicts 6 (PASS 1 · PASS-WITH-NOTES 1 · FAIL 3 · UNKNOWN 1) · sessions 4`; then in order `[V1] no-real-path ★ recurs across sessions` (`rows 3 · sessions 2 · ... · implementers: opus-implementer 2`), `[V2] other` (non-enum category), `[V3] test-fail`; the uncommitted verdict from 40 days ago does not appear; `all projects (not filtered by project):` reads `no-real-path 4 rows/3 sessions · false-claim 1 rows/1 sessions · other 1 rows/1 sessions · test-fail 1 rows/1 sessions`.
  - Ends with `(skipped bad rows: 1 non-JSON rows; 2 tool/verdict rows missing ts/session/cwd or with unparseable ts)`, exit code 0. With only tool rows, the verifier section prints `(no verifier verdicts for this project in the window)`.
  - With `--days 60` an extra `[5] Read · error` group appears; writing the project root with a trailing slash (`/tmp/fixproj/`) gives the same result (a relative path is resolved against the real working directory, so on macOS, where `/tmp` is a symlink, it only matches if the fixture `cwd` uses the resolved path); with `fixproj-bar` as the root only its own `[1] Bash · error · $ pnpm build` group appears.
  - `TURN_SIGNALS_PATH` pointing to a missing file prints `(no signal log: <path> does not exist; skipping)`, to an empty file prints `(signal log is empty: <path>; skipping)`; no `python3` on `PATH` prints `(python3 not found; skipping signal log analysis)`; exit code 0 in all three cases.
  - Run once against the real log; when there is no cross-session group, a single line starting `(no tool failure recurs across >=2 sessions; ...` is the correct result -- do not loosen the bar.
