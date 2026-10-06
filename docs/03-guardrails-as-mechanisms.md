# Guardrails as Mechanisms: What a Mechanism Can Block, Don't Write as a Prompt Rule

English | [简体中文](zh-CN/03-护栏机制化.md)

## Core judgment

Rules in prompts have a fundamental problem: **nothing errors when no one enforces them.** If the model forgets "run tests before committing" one time, nothing reminds you; you only find the problem at some later point. Mechanisms such as hooks and permission config are executed by the host and do not depend on the model remembering.

So first decide the shape of a constraint, then decide where it goes:

| Shape of the constraint | Where it goes |
|---|---|
| "Every time X, do Y" | hook |
| "Do not do X" | permission config (`permissions.deny`) or PreToolUse interception |
| Something that needs judgment to carry out | text rule (`AGENTS.md` / skill) |

Text rules are reserved for things that truly need judgment. Anything that can be written as "on A, do B" can basically be handed to a mechanism.

## `guard.sh`: PreToolUse interception

`guard.sh` is a global PreToolUse hook. It reads the hook JSON from stdin and makes a deterministic decision on Bash commands; exit 2 blocks the call and returns the explanation on stderr to the model.

It blocks these:

- **Force-pushing to main / master.** `--force`, single-dash flag clusters containing `f` (`-f`, `-uf`), and refspecs starting with `+` all count as force pushes; `--force-with-lease` does not. The target branch is the destination side of an explicit refspec, or the current branch when there is none.
- **Skipping hooks**: `--no-verify` on git commit / push / merge, and `-n` on git commit.
- **Dangerous recursive deletes**: targets `/`, `.`, `..`, `*`, `/*`, `~`, `$HOME`, or the git repository root.
- **Recursive deletion of the `.next` build directory** (including variants with a `.next-` prefix), because a dev server may be using it.
- **Destructive git history / working-tree commands**: `git reset` with `--hard`, and `git clean` with `--force` or a flag cluster containing `f`. `git reset --soft`, `git clean -n`, `git stash`, and the like are not blocked.

A few design trade-offs:

- A command is split into segments at unquoted newlines and `&&` `||` `;` `|`, and each segment is judged on its own; tokenization uses Python's `shlex`, so content inside quotes is a single argument and does not take part in matching (`git commit -m "fix: handle -n flag"` is allowed).
- Each segment carries an "effective working directory": `cd <path>` affects the segments after it, while `git -C <path>` affects only that one invocation.
- A command that cannot be parsed falls back to whitespace splitting, and when the repository cannot be located, a force push without an explicit refspec is blocked outright: **when uncertain, lean toward blocking**.
- If parsing the hook JSON fails, the command is allowed through (fail-open), because `permissions.deny` is the second layer.

### How to test

`guard_test.sh` feeds crafted hook JSON to `guard.sh` and asserts the exit code:

```bash
bash claude/hooks/guard_test.sh
```

Before changing `guard.sh`, first add a test case that fails, then make it pass after the change. The cost of a wrong blocking rule is either blocking normal work or letting a dangerous command through; both deserve a test.

### Known false positives

`guard.sh` scans by argv token and does not distinguish "the command to execute" from "a string passed to a child process or written into a file". For example, running an end-to-end test in Bash with `claude -p "...--no-verify..."`, or using a heredoc to write text that mentions this flag into a document, will be blocked. The direction is a false positive (blocking a legitimate command) rather than a miss, which is a design trade-off. When it happens, use a way that does not go through Bash arguments (for example, write the document with a file-editing tool).

## `session-start.sh`: not relying on the model to read proactively

The project convention is "read `.ai/PROGRESS.md` before starting work", but that is still a text rule. `session-start.sh` turns it into a SessionStart hook: when the current repository has `.ai/PROGRESS.md`, it automatically injects the last 60 lines of it, plus `git status -sb` and the 5 most recent commits. A repository without `.ai/` exits immediately and produces no output.

## Lessons on permission allowances

- **For tools that need a long-term allowance, use `permissions.allow`.** The allow decision comes before the auto classifier. Do not try to get around a block by changing prompt wording; the next time you phrase it differently, it will be blocked again.
- **For the kinds of operations the auto classifier blocks consistently, don't try them yourself first.** In practice the consistently blocked ones are: reading or writing browser cookies / login state / credential sync; cloning and running third-party code, opening Chrome remote debugging; writing to user-level config (such as shell config or the global agent-rules directory). When you hit one of these, give the user a pasteable command to run themselves, and read the tool's `--help` first to confirm the input format. Retrying only wastes rounds.
- **If a subagent was denied and asks the main session to do it instead, the main session does not do it for them.** A denial is the permission system's decision, and having a different executor get around it makes the block meaningless. The right thing is to report the denied operation and the reason to the user.

## A correction that appears twice: fix it by level

When the same kind of correction appears twice, treat it as a class of problem rather than reminding verbally once more. Fix it by the following levels, using a higher one whenever possible:

1. **Eliminate it structurally**: make the error impossible, for example by removing an easily misused interface or changing the directory structure.
2. **Automated check**: hook, lint, interception script. The error message states **what to use instead**, not just "not allowed", so the model can correct itself on seeing the error.
3. **Test**: write this error as a test case that fails.
4. **Documentation rule last**: write it into `AGENTS.md` or a skill.

These levels follow the same idea as the routing table of `/distill` in `01-two-loop-memory.md`: the lower you go, the more it depends on the model's self-discipline; the higher you go, the less it does.

## How to use it in this repo

- `claude/hooks/guard.sh`, `claude/hooks/guard_test.sh`: the PreToolUse interception script and its test.
- `claude/hooks/session-start.sh`: the SessionStart injection script.
- Copy them to `~/.claude/hooks/`, and register the matching `PreToolUse` (matcher `Bash`) and `SessionStart` hooks in Claude Code's `settings.json`.
- `skills/distill/`: use it when deciding whether an experience should land in a hook, a permission, or a text rule.

## Limitations

- `guard.sh` only checks Bash commands and does not cover write operations from other tools; it is a guardrail, not a sandbox.
- The false-positive problem is currently handled by working around it; no change has been made to "distinguish commands from string contents".
