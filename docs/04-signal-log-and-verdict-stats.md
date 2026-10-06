# Signal Log and Verdict Stats

English | [简体中文](zh-CN/04-信号日志与验收统计.md)

## The problem

Per-task verification (spawning one verifier after each implementer run) catches mistakes in that one task. It cannot see a different kind of problem: several agents making the same class of mistake across sessions, or repeatedly taking the same shortcut. For example, the same command fails the same way in five sessions, or implementers keep saying "verified" after running only mocks. Each task looks like a small issue on its own; together they are the signal that a rule needs to change.

The point of spot-checking is to find repeated patterns, not to review item by item.

## Approach

Two steps, with recording and statistics each doing one job:

1. **Record**: a Claude Code mod, `turn-signals`, listens in on sessions and appends compact signals to a JSONL file shared across sessions and accounts. It displays nothing; it only writes the file.
2. **Aggregate**: `signals.sh` in the `distill` skill reads that file, computes deterministic statistics, and hands the "repeated across sessions" leads to a human or an agent to judge.

The script does the statistics, not the model reading the log and looking for patterns: the same input always gives the same grouping, so results can be re-checked. The script's output is a lead, not a verdict; whether to change a rule because of it is still the human's call.

## What gets recorded

By default the file is `~/.local/state/claude-insight/turn-signals.jsonl`; set the environment variable `TURN_SIGNALS_PATH` to use another path. Each record is one line of JSON:

```json
{"type":"tool","kind":"error","ts":"…","session":"…","cwd":"…","account":"claude-2","tool":"Bash","subagent":false,"error":"Exit code 2\n…","command":"ls /nonexistent-dir-xyz"}
{"type":"turn","ts":"…","session":"…","cwd":"…","account":"claude-2","reason":"answer","durationMs":6134,"tools":1,"failures":1}
{"type":"interrupt","ts":"…","session":"…","cwd":"…","account":"claude-2","durationMs":900,"tools":1}
{"type":"verdict","ts":"…","session":"…","cwd":"…","account":"claude-2","agentId":"…","implementer":"opus-implementer","verdict":"FAIL","issues":[{"cat":"no-real-path","text":"…"}]}
```

- `tool`: a tool failed or was refused. `kind` is `error` (it ran and reported an error), `interrupted` (interrupted while running), or `refused` (it never ran: a permission rule, a user denial, or a hook deny). `error` is truncated to 200 characters, and Bash also records the first 120 characters of `command`; calls made inside a subagent carry `subagent: true` and `agentId`.
- `turn`: one summary per main-loop turn; `reason` is `answer` / `aborted` / `refusal` / `error`.
- `interrupt`: an extra record when the user presses Esc to interrupt the whole turn.
- `verdict`: one record each time a subagent of type `verifier` finishes a turn. It takes the last `VERDICT: PASS|PASS-WITH-NOTES|FAIL` in the answer, or `UNKNOWN` if there is none; `issues` takes lines shaped like `- [slug] text`, at most 12. `implementer` is the type name of the most recent non-verifier subagent started in this session before the verifier.

Writes use `/bin/sh` with `mkdir -p` plus `cat >>` (O_APPEND), so two sessions writing at once do not overwrite each other. A failed write goes only to the debug log and does not affect the session.

## Verifier issue categories

To make verification outcomes countable, the verifier's prompt requires every issue to start with a category tag, chosen from this table:

| slug | Meaning |
| --- | --- |
| `no-real-path` | Only mock / fake / code reading, with no evidence of a run through a real provider or browser |
| `criteria-fail` | The behavior for an acceptance criterion does not actually hold |
| `test-fail` | The project's existing test / build / lint fails |
| `out-of-scope` | Changed files or behavior the task did not ask for |
| `uncommitted` | Not committed or not pushed to the place the task required |
| `false-claim` | The implementer's own claim (tested / verified / completed something) is contradicted by results the verifier ran |
| `other` | None of the above |

An issue gets only the single best-fitting tag; when both `false-claim` and another category apply, prefer `false-claim`. A slug not in the table is recorded as `other`.

## How the stats work

```bash
bash signals.sh <PROJECT_ROOT> [--days N]      # default: last 30 days, read-only
```

Tool failures:

- Only `tool` lines whose `cwd` is under the project root and that fall within the time window are used.
- Grouped by signature: tool + `kind` + Bash command head + normalized first line of the error. Normalization replaces quoted content, URLs, uuids, paths, long hex strings, and numbers with placeholders, then truncates to 80 characters, so "same error, different arguments" land in one group. The Bash command head strips prefixes such as `cd X &&`, environment variable assignments, and `sudo`; common subcommands (such as `git push`, `npm run`) are included.
- **Only groups that appear in 2 or more distinct sessions are printed.** Repeats within one session count once, because retries inside a session do not indicate a cross-session pattern.

Verifier records:

- First the distribution of conclusions (record count and session count per verdict).
- Then grouped by `issues[].cat`: each group shows the count, session count, first and last date, counts per `implementer`, and up to 3 sample issues. Groups with 2 or more sessions are marked with ★, which is the threshold for entering distill.

The script's comments list its known limitations: false merges (only failures that are just `Exit code N` get merged by command head), false splits (the same kind of error whose wording varies with arguments is split into several groups), and ordinary words containing `/` being wiped as paths. This is also why the output is only a lead.

## How to load it

The mod is a plain `.mjs` function-hooks module, packaged as a plugin, with no npm dependencies. A trial run applies only to the current session and installs nothing:

```bash
claude --plugin-dir <ai-kit>/mods                  # load every mod in the directory
claude --plugin-dir <ai-kit>/mods/turn-signals     # load just one
```

For everyday use, add `--plugin-dir` to your launch alias. Sessions started around the alias (such as the desktop app) will not load it.

Another mod in the same directory, `token-weather`, shows context usage above the input box (an icon, a percentage, and a sparkline of the last few turns); it is unrelated to the signal log.

## Gotchas

**`$.agent.list()` cannot see subagents dispatched by the Agent tool.** When adding verdict records, the first version used `$.agent.list()` inside the subagent's `turn.complete` to look up the type name by `agentId`, and the type declarations also list `AgentInfo.type`. At runtime it returned an empty array. The current approach: record the type name into `$.state` from the `agent_type` of `classic.SubagentStart` / `classic.SubagentStop`; take the answer text from the `answer` of the subagent's `turn.complete` (the `last_assistant_message` of `SubagentStop` was observed to be empty).

**All mock unit tests pass, but the real run writes no line.** For the problem above, all 10 unit tests that mocked `agent.list` passed; it only surfaced when a real verifier was dispatched with `claude -p` and the log had no verdict line. Conclusion: do not treat mock unit tests as the standard for mod changes; every change needs a real `claude -p` smoke run. This is exactly the situation the `no-real-path` category is meant to catch.

## Known limitations

- **Very little data so far**: the log has only a few days in it, and no conclusion has been drawn from the statistics yet. Whether this setup is useful depends on collecting enough data first.
- **The account identifier is inferred**: the plugin API does not expose account info, so it takes the last segment of `CLAUDE_CONFIG_DIR` and strips the leading dot (`~/.claude-2` is recorded as `claude-2`); if unset, it is `claude`.
- **`refused` cannot tell which kind of refusal it was**: separating "failed" from "refused" is inferred from observation. When a tool really runs and then fails, the engine emits `classic.PostToolUseFailure` first; when refused, it does not. So permission rules, a user clicking deny, and a hook deny all land in `refused`. Input-validation failures are presumed to land in `refused` too (not verified); a user clicking deny in the interactive UI has not been tested either.
- **It cannot see which rule refused**: `tool.check` fires only before the prompt decision and cannot see the user's final choice, so it is not used.
- **Interrupts are recognized only per turn**: only a whole turn ending as `aborted` is recognized; a single interrupted tool is recorded as `kind: "interrupted"`.
- **Verdict matching is loose**: the `VERDICT:` match has no word boundary (`VERDICT: PASSED` is recorded as PASS). `implementer` does not distinguish who started the subagent, and subagents started before the mod was loaded are not counted.
- **Works as usual under `claude -p`**: failure records, refusal records, turn summaries, and verdict lines were all observed being written.
- **Hot-reload safe**: each reload reruns `register` and `session.start`; `turn-signals` writes nothing in `session.start`, so a reload produces no duplicate lines.
