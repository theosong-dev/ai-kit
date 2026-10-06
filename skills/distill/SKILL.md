---
name: distill
description: "Distill accumulated gotchas and user corrections into reusable rules and route each one to the right loading channel. Trigger when the user says \"distill\", \"turn lessons into rules\", \"consolidate rules\", or when /wrap reports that undistilled lessons have piled up; the Chinese triggers 「蒸馏」「整理规则」 work too. First run pending.sh to collect unmarked .ai/GOTCHAS / DECISIONS entries plus the PROGRESS \"User corrections (pending distillation)\" section, and signals.sh to add cross-session repeated failures from the signal log; candidates that pass the entry threshold (repeated >=2 times or high cost) are routed to shared rules / a skill / the current host's hook or permission mechanism, old rules are pruned, and changes land only within the scope the user has approved. Not for: recording this session's progress (use /wrap), changing code directly, or running tests."
---

# Lesson Distillation Protocol

The **outer improvement loop** of the memory system: /wrap faithfully records what happened (inner loop); /distill promotes repeated or costly lessons into a reusable rule and puts it in the right loading channel, so the same mistake is less likely next time. Official guidance: route rules by loading channel ("every time X, do Y" is a hook, not a prompt), and distillation must include subtraction.

## Steps

1. **Collect inputs (deterministically, not by eye)**: Treat the directory containing the `SKILL.md` you read this time as the skill root and run `bash "<SKILL_ROOT>/scripts/pending.sh" "<PROJECT_ROOT>"` (replace the placeholders with real absolute paths, quote each one, and pass the target project root explicitly; do not rely on cwd or host-injected environment variables). Its output is authoritative: undistilled GOTCHAS / DECISIONS titles, the PROGRESS "User corrections (pending distillation)" section, title repetition hints (shared CJK 2-grams or shared Latin words), the current rule volume of the target files, and, in section [6], the counts of rules with / without a rationale. Then run `bash "<SKILL_ROOT>/scripts/signals.sh" "<PROJECT_ROOT>"` (last 30 days by default, adjustable with `--days N`) to get same-kind tool failures in this project's signal log that repeat **across >=2 sessions**, plus verifier review hints grouped by `cat`. Skip it when the host reference says this input is unavailable; if the log is missing, the script prints a single explanatory line and you continue as usual. Both kinds of repetition hints are **hints, not verdicts**; double-check them yourself.

2. **Entry threshold (filter out what should not be promoted first)**. A candidate must meet one of:
   - The same problem **occurred >=2 times** (pending.sh 2-gram hints + your own judgment; same-kind failures across >=2 sessions listed by signals.sh also count; so does the same `cat` across >=2 sessions in its verifier review hints, and for these, prefer changing the dispatch template / the implementer agent body / a check that can block automatically over adding another text rule);
   - Or a single occurrence was **very costly** (data loss / wrong version shipped / security boundary / production data touched).

   Each candidate must come with one sentence stating **"which real mistake this would have prevented"**, citing the source entry title; if you cannot write that sentence, do not propose it. One distillation usually yields 1-3 rules; fewer is better.

   The signal log only shows that something repeated, not why: before promoting a rule, take only the sessions in the signals.sh samples, locate their raw transcripts per the host reference, and read the excerpts before and after the failure to understand the cause; do not read every transcript in full. If the cause is unclear, do not promote.

3. **Route by loading channel** (not every rule goes into AGENTS.md):

   First identify the current host and read only its reference: [Claude Code](references/claude.md) or [Codex](references/codex.md). If the host cannot be determined, analysis of shared targets may continue, but confirm before landing any host configuration.

   | Rule shape | Target channel |
   | --- | --- |
   | Every time X, do Y / something must happen | A hook supported by the current host, verified per its reference |
   | Never X | The current host's permission mechanism or tool interception, with coverage judged per its reference |
   | Multi-step procedure / checklist | Shared skill (`.agents/skills/<name>/SKILL.md`, global: `~/.agents/skills/`) |
   | Applies only to one directory | Subdirectory `AGENTS.md`; file-type conditions handled per the host reference |
   | Standing fact / invariant / project gotcha | Project `AGENTS.md` |
   | Cross-project and verified in multiple projects | `~/.ai/AGENTS.md` |

   Shared files affect both hosts; host configuration affects only that tool. State the scope of impact in the proposal, and do not generalize one host's permission allowances or model behavior to the other.

   Repeated `refused` entries in the signal log (rejected without running) are a permission issue, like "Never X": if the action should be allowed, allow it through the current host's permission mechanism; if not, switch to an already-allowed approach. Do not add "don't try X again"-style prompt rules.

4. **Subtraction (reviewed together with additions)**. Scan the existing rules in the target files (project `AGENTS.md`, `~/.ai/AGENTS.md`) and mark deletion candidates:
   - Rules that are outdated, covered by another mechanism, or old model workarounds, but the basis must be stated.
   - Before deleting a behavioral constraint, there must be evidence from representative tasks that requirements are still met without loading the rule; without evidence, keep it and list verification as a next step. Verification results on one model do not automatically carry over to another model.
   - **Re-review on model change**: rules whose rationale names a model different from the current one, and rules with no rationale that appear to compensate for model behavior flaws, go on a "to re-review" list attached to the proposal for the user (pending.sh section [6] gives the counts with / without a rationale). Re-review is not deletion; deletion is still bound by the previous point.

   Deletions are reviewed together with new proposals; do not delete rules by a fixed ratio.

5. **Output a minimal diff proposal**. One paragraph per item, stating: source entry -> exact text added / changed / deleted -> target channel -> the real mistake it would have prevented -> one sentence on **how to verify** (what command to run, what result to expect). Every new or changed rule ends with a one-line rationale, on the same line as the rule in the rule file, as short as possible, containing year-month, source (GOTCHAS / DECISIONS title, user correction date, or "signal log N sessions M times"), and the name of the model running this distillation ("model unknown" if not known), e.g. `(rationale: 2026-10, GOTCHAS "xxx" + signal log 3 sessions 5 times; <model name>)`. **Show unauthorized concrete changes first, and write files only after each is approved. Proposals already covered by explicit approval are applied directly without asking again; authorization does not expand execution-environment permissions.**

6. **Land after approval**:
   - Apply the approved diff (including deletions) and write each rule's rationale with it; when the target is a hook / script / skill, write the rationale as a comment in that file. Land host configuration per the corresponding reference; do not assume every change belongs in `settings.json`.
   - For consumed GOTCHAS / DECISIONS entries, add `<!-- distilled YYYY-MM-DD -->` on the **line right below the title** (entries explicitly skipped this time get `<!-- distilled YYYY-MM-DD skipped -->`; entries not yet evaluated, not approved, or left for observation get no marker); write the entry's "how to verify" sentence after the distilled marker.
   - Move only the PROGRESS "User corrections (pending distillation)" entries processed this time, verbatim, into `.ai/archive/PROGRESS-YYYY-MM.md` (create the directory if missing); keep entries not yet evaluated, not approved, or left for observation; do not clear the whole section. Explicitly skipped entries also need a recorded reason for skipping.
   - Add one line to the PROGRESS "Progress log": "Distilled: N rules -> target (file names)".

## Memory file section names

This skill uses English section titles; the Chinese names are recognized too:

| English | Chinese |
| --- | --- |
| `## Current status` | `## 当前状态` |
| `## Next steps` | `## 下一步` |
| `## Task list` | `## 任务清单` |
| `## Open issues` | `## 遗留 / 待澄清` |
| `## User corrections (pending distillation)` | `## 用户纠正（待蒸馏）` |
| `## Progress log` | `## 进度日志` |

## Notes

- Distillation is **abstraction**, not copying: turn one concrete mishap into a one-sentence rule to follow next time; do not paste GOTCHAS text verbatim into AGENTS.md.
- After changing host configuration, verify it actually takes effect per the corresponding reference; editing the file alone does not count as done. Run the checks you are already authorized to run yourself; where host trust approval is still needed, name the specific action awaiting approval.
- Be most cautious at the cross-project level (`~/.ai/AGENTS.md`): if a lesson has not held in multiple projects, do not write it there.
- When unsure whether to promote, lean toward not promoting; leave it in GOTCHAS and wait for it to recur.

## Bundled scripts

- `scripts/pending.sh [PROJECT_ROOT]` — deterministic input collector for step 1, bash + awk, with the target project root passed explicitly.
- `scripts/signals.sh <PROJECT_ROOT> [--days N]` — cross-session repetition hints for step 1 (same-kind tool failures + verifier review issues counted by category), reading the turn-signals signal log (path overridable via `TURN_SIGNALS_PATH`), bash + python3; grouping and normalization rules are in the script's header comment.
