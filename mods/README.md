# Claude Code mods examples

English | [简体中文](README.zh-CN.md)

Two working mods (JS hook modules packaged as plugins and run inside a Claude Code session), written against the function hooks API of Claude Code 2.1.288. Plain `.mjs`, no npm dependencies. They are only examples; whether to install them is up to you.

| mod | What it does | Where it shows |
| --- | --- | --- |
| `token-weather` | A "weather forecast" for context usage: icon + percentage + tokens/window; when the width is ≥60 columns it also adds a sparkline of the last 12 turns and the change since the previous turn. Thresholds 25/50/75/90 give five levels | Above the prompt box (`AbovePrompt`) |
| `turn-signals` | Appends compact signals to one cross-session, cross-account JSONL file: tool failures or refusals, a per-turn summary, user interrupts. Makes it easy to later scan for "the same error recurring across several sessions" | Not shown, file only |

## Try it (this session only, no install)

```bash
claude --plugin-dir ./mods          # whole folder: loads each mod in the subdirectories
claude --plugin-dir ./mods/token-weather   # or load just one
```

For everyday global use (both accounts share this one copy of the source, nothing installed): add `--plugin-dir <ai-kit path>/mods` to the `claude` / `claude-2` aliases in `~/.zshrc`. Sessions started without going through the alias (such as the desktop app) will not load it.

On first load, Claude Code generates `.claude-plugin/types/` (API type declarations, already in `.gitignore`) and `tsconfig.json` under each mod.

Checks and tests:

```bash
claude plugin validate ./mods/token-weather    # a single mod
claude plugin validate ./mods                  # the marketplace
claude plugin test ./mods/turn-signals
```

## Install

`mods/` itself is a local marketplace (`mods/.claude-plugin/marketplace.json`, named `claude-insight-mods`):

```bash
claude plugin marketplace add <ai-kit path>/mods
claude plugin install token-weather@claude-insight-mods
```

Plugins are installed into the current account's config directory. The two accounts (`~/.claude` and `~/.claude-2`) each need their own install: for the second account, run the same commands again with `CLAUDE_CONFIG_DIR=~/.claude-2 claude plugin ...`.

## turn-signals record format

By default it writes to `~/.local/state/claude-insight/turn-signals.jsonl`, one file shared by both accounts; the directory is created if missing. Set the environment variable `TURN_SIGNALS_PATH` to change the path (the tests do exactly this). Each record is one line of JSON:

```json
{"type":"tool","kind":"error","ts":"…","session":"…","cwd":"…","account":"claude-2","tool":"Bash","subagent":false,"error":"Exit code 2\n…","command":"ls /nonexistent-dir-xyz"}
{"type":"turn","ts":"…","session":"…","cwd":"…","account":"claude-2","reason":"answer","durationMs":6134,"tools":1,"failures":1}
{"type":"interrupt","ts":"…","session":"…","cwd":"…","account":"claude-2","durationMs":900,"tools":1}
{"type":"verdict","ts":"…","session":"…","cwd":"…","account":"claude-2","agentId":"…","implementer":"opus-implementer","verdict":"FAIL","issues":[{"cat":"no-real-path","text":"…"}]}
```

- `kind`: `error` means the tool ran but reported an error, `interrupted` means it was interrupted mid-run, `refused` means it never ran (denied by a permission rule or mode, the user clicked deny, or a PreToolUse hook denied it). `error` is truncated to 200 characters; for Bash the first 120 characters of `command` are also recorded; calls made inside a subagent carry `subagent: true` and `agentId`.
- `turn`: a summary is recorded only for turns of the main loop. `reason` is `answer` / `aborted` / `refusal` / `error`; `tools` and `failures` count only the main loop's own tool calls.
- `interrupt`: one extra record when a turn ends with `reason: "aborted"` (the user pressed Esc).
- `verdict`: one record each time a subagent whose type name (last segment) is `verifier` finishes a turn; other subagents are not recorded. `verdict` takes the **last** `VERDICT: PASS-WITH-NOTES|PASS|FAIL` in the answer (tolerating `**` and backticks), or `UNKNOWN` if there is none. `issues` takes lines shaped like `- [slug] body` (list prefix and `**` optional); a slug not in `no-real-path` `criteria-fail` `test-fail` `out-of-scope` `uncommitted` `false-claim` `other` is recorded as `other`; `[x]`, `[N]` and markdown links do not count; the body is truncated to 160 characters, at most 12 entries. `implementer` is the type name of the most recent non-verifier subagent started in this session before this verifier; if there is none, the field is omitted.
- Writing uses `/bin/sh` for `mkdir -p` plus `cat >>` (O_APPEND), so two sessions writing at once do not overwrite each other. A failed write is only logged to the debug log and does not affect the session. Every hook passes the event on unchanged with `next(e)`.

## Known limitations

- **Two mods cannot both draw `AbovePrompt`**: this area is a hook chain, and once the outermost plugin returns its own tree the chain ends. Tested in a real interactive session with two probe plugins: only the one loaded first (the earlier `--plugin-dir`) is shown, and swapping the order swaps which one wins. The `usage-meter` mod that was once built therefore switched to the `$.ui.status` status line; it was later found to duplicate the existing `statusline-command.sh` and to always carry a `⚠ <plugin name>:` prefix on plugin status lines, so it was removed (2026-10-03).
- **The account label is inferred**: the plugin API has no account or plan information, so it takes the last segment of `CLAUDE_CONFIG_DIR` with the leading dot removed (`~/.claude-2` → `claude-2`); if the variable is unset it is the default `~/.claude` → `claude`. The plan (max/pro) is not shown.
- `token-weather`: a new session that has not sent a request yet shows `0 / window` (behavior as in the official article); when `context.window` is unavailable no reading is recorded; subagent turns are not counted.
- `turn-signals`:
  - Telling "failed" from "refused" is inferred from observation: when a tool actually ran and failed, the engine was observed to emit `classic.PostToolUseFailure` first and then have `tool.call` return `isError`; when denied by permissions, `tool.call` also returns `isError` but no `PostToolUseFailure` is emitted. So within `refused` the kind of refusal cannot be told apart (permission rule/mode, user clicked deny, hook deny). In addition, cases that error without executing, such as input validation failures, are presumed to also land in `refused`; this has not been verified. The user clicking "deny" in the interactive UI has not been tested either.
  - There is no "which rule denied it": `tool.check` fires only before the prompt decision and cannot see the user's final choice, so it is not used.
  - Interrupts are recognized only when the whole turn ends with `aborted`. A single interrupted tool is recorded as `kind: "interrupted"`.
  - Works as usual in non-interactive mode (`claude -p`), tested: failure records, refusal records and turn summaries are all written. Under `-p` the UI is not shown (`$.ui.status` goes only to the debug log in a headless session), which does not affect `turn-signals`.
  - `verdict` rows: `$.agent.list()` does not include subagents dispatched by the Agent tool (tested: it returns an empty array), so the type name is instead recorded into `$.state` from the `agent_type` of `classic.SubagentStart` / `classic.SubagentStop` (at most 50 entries kept); the answer text is taken from the `answer` of the subagent's `turn.complete` (the `last_assistant_message` of `SubagentStop` was observed to be empty). Tested on 2026-10-06: under `claude -p`, a verifier reporting PASS and one reporting FAIL with `[criteria-fail]` each wrote a row, dispatching `general-purpose` wrote none, and dispatching `general-purpose` before a verifier produced `"implementer":"general-purpose"`; a verifier running in the background in an interactive session also wrote as usual. `implementer` does not distinguish who started it, and subagents started before the mod was loaded are not counted. The `VERDICT:` match has no word boundary (`VERDICT: PASSED` is recorded as PASS). An `answer` that is not a string is treated as an empty string in the code, but the test framework intercepts such input before the hook, so this was not exercised by tests.
- Hot reload: every reload reruns `register` and `session.start`. Data that must persist (reading history, per-turn counters) is kept in `$.state`; `turn-signals` writes nothing in `session.start`, so a reload does not produce duplicate rows.
