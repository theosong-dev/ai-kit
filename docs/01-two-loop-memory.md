# Two-Loop Memory: Keeping Project Memory From Getting Lost, Bloated, or Stuck as Notes

English | [简体中文](zh-CN/01-双层记忆循环.md)

An AI coding agent starts every session from zero. Progress that is not written to a file is gone by the next session. But if you pile everything into files, those files eat context at the start of every session. The approach here splits memory into two loops:

- **Inner loop (`/wrap`)**: at the end of each session, record faithfully what happened.
- **Outer loop (`/distill`)**: once enough experience has accumulated, promote the repeated or high-cost part into a reusable rule and put it in the right loading channel.

The inner loop only "records"; the outer loop only "changes". They are kept separate so that wrapping up stays light enough that you actually do it every time.

## Inner loop: three files

Put a `.ai/` directory in each project root, with three files:

| File | What it records | How it is written |
|---|---|---|
| `PROGRESS.md` | `Current status`, `Next steps`, `Task list`, `Open issues`, `User corrections (pending distillation)`, `Progress log` (the Chinese templates under `zh-CN/` use Chinese section names, and the scripts accept either) | Editable, with a size cap |
| `DECISIONS.md` | Important decisions: background, what was chosen, alternatives rejected, reasons | Append-only |
| `GOTCHAS.md` | Gotchas hit: what was tried, why it failed, what to do next time | Append-only |

The project's `AGENTS.md` says "read `.ai/PROGRESS.md` before starting work", and to read `DECISIONS.md` and `GOTCHAS.md` when relevant. That way a new session recovers state in seconds without reading the entire history.

`DECISIONS.md` and `GOTCHAS.md` are append-only because they are evidence: when you later distill rules, you need to point back to what actually happened. Rewritten history cannot serve as evidence.

### Why PROGRESS needs a hard cap

`PROGRESS.md` is the only file that is **read at the start of every session**, so every line of it directly consumes context. Decisions and gotchas can be read on demand; progress cannot. So `PROGRESS.md` has a hard cap, and anything over it is archived.

The cap is not judged by eye. "It doesn't look that long yet" loosens a little each time, and the file ends up bloated. `/wrap` runs a check script (`check_size.sh`); the cap values, the section-name rules, and the criteria for each OK / OVER item all live in the script, and the skill body does not repeat them.

### What `/wrap` does

It is triggered at the end of a session ("wrap up", "update progress", "end of session", or "tidy up before we stop"; the Chinese triggers work too), and runs these steps in order:

1. Refresh `Current status` / `Next steps` / `Open issues`.
2. Check off the items in the task list that have been **verified end to end**; do not check off unverified ones. Code written is not the same as done.
3. Add one line to the progress log.
4. If this session involved decisions or gotchas, append them to `DECISIONS.md` / `GOTCHAS.md`.
5. If the user corrected the agent's approach during this session, record it in the `User corrections (pending distillation)` section of PROGRESS. Corrections are the best raw material for rules; if they are not recorded, they are lost.
6. Run `check_size.sh`. If any item is OVER: append the original text of the excess progress-log entries to `.ai/archive/PROGRESS-YYYY-MM.md`, leaving only a compressed one-liner in this file; if "current status" exceeds its line limit, compress it, but keep warning states (not pushed / not verified / do not release) and drop implementation details. After archiving, run the script again and confirm exit 0.

## Outer loop: `/distill` promotes experience into rules

Most of what the inner loop records should not become a rule. The more rules there are, the lower the chance that each one is followed. The job of `/distill` is to filter, route, and do subtraction (removing rules).

### Entry bar

Input is collected by scripts, not by eyeballing: `pending.sh` lists the undistilled GOTCHAS / DECISIONS entries and the "user corrections (pending distillation)", and flags duplicate-title leads; `signals.sh` finds, in the signal log, tool failures of the same kind that recur across ≥2 sessions. Both kinds of output are only leads and still need a manual re-check.

A candidate must meet at least one of:

- the same problem **has occurred ≥2 times**;
- or a single occurrence was **very costly** (data loss, shipping the wrong version, a security boundary, touching production data).

And every candidate must be able to state in one sentence "**which real error it could have prevented**". If it cannot, it is guarding against an imagined problem and is not promoted.

### Routing by loading channel

The same piece of experience takes effect in completely different ways depending on where it is placed. Routing is based on "how does it need to take effect":

| Shape of the experience | Destination |
|---|---|
| Every time X, Y must happen | hook (executed by the host, does not depend on the model remembering) |
| Do not do X | permission config / PreToolUse interception |
| Multi-step procedure, needed only in certain scenarios | skill (loaded on demand) |
| Standing fact needed in every session | `AGENTS.md` |

If "every time X, do Y" is written as a prompt, no error is raised when the model forgets it once; written as a hook, it cannot be forgotten. This is expanded in `03-guardrails-as-mechanisms.md`.

### Subtraction

Every distillation also looks at what can be removed: old rules covered by a new rule, text rules already taken over by a mechanism (hook / permission), and rules that have never had any effect. Deletion also requires user approval.

### Rules carry a rationale

A rule that is added or changed carries a rationale at the end of the same line: year and month, source (which GOTCHAS / DECISIONS entry, which day's user correction, or "signal log N sessions M times"), and the name of the model that ran this distillation.

The model name is there so the rule can be re-checked after a model change: many rules compensate for a behavioral flaw of one model generation and may no longer be needed on another. `/distill` puts rules whose "rationale names a different model than the current one", and rules that "have no rationale and look like they compensate for a model flaw", on a re-review list. Re-review does not mean deletion.

### Nothing lands without approval

The output of `/distill` is a **minimal-diff proposal**. Each item states: source entry → original text to add / change / delete → destination channel → the real error it could have prevented → a one-line verification method (what command to run, what result to expect). Only what the user approves lands; anything outside that scope is left untouched.

## Not yet verified / current limitations

- **Re-review after a model change has not actually been done.** Model names in the rationale are already being recorded, but the full flow of "after a model change, re-check against the list and delete outdated rules" has not been run once; its effect is currently only an expectation.
- **Signal statistics are still thin.** `signals.sh` depends on the signal log accumulating; when the log covers a short time, leads for "recurring across sessions" are sparse, and entry-bar judgment still rests mainly on GOTCHAS and user corrections.
- The specific size-cap values are rules of thumb; there has been no comparison of what cap is best.

## How to use it in this repo

- `templates/project/`: project memory templates; copy them into your project root.
- `skills/wrap/`: the body of `/wrap` and `check_size.sh`.
- `skills/distill/`: the body of `/distill` and `pending.sh` / `signals.sh`.
- `mods/`: the signal-recording mod in it supplies the log source for `signals.sh`.

The scripts of both skills locate themselves by the directory of `SKILL.md` and take the target project root explicitly, without depending on the current working directory or environment variables injected by the host, so Claude Code and Codex can share the same copy.
