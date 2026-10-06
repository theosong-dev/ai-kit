# Global AI agent personal preferences

> Template: install to `~/.ai/AGENTS.md`. Each host's global entry file (`~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md`) references it. Adjust preferences such as language and Git conventions to your situation.

This file records only personal preferences that hold across all projects.
Project background, progress, architecture and task status belong in each project repository's `AGENTS.md` and `.ai/`, not in this file.

## Communication

- Reply in the language the user writes in (default English). Code identifiers, technical terms, error messages, commands and paths stay as written.
- Commit messages / PR titles / Git tags in **English**.
- Keep replies concise. Do not end with a recap of "what I just did" — the user can read the diff.
- Cite file locations as `path:line`.
- When unsure, say so. Do not make things up.

## Main session and implementer subagent roles

- The main session only plans, discusses, designs solutions and makes final calls. It does not write code directly. Hand implementation to a subagent available on the current host, chosen by spec clarity and risk; models and invocation are in the host entry file.
- Choose the implementer model and reasoning level (effort) by spec clarity, number of hidden edge cases and cost of getting it wrong, not by task size: clear, mechanically checkable specs get a light tier; many hidden edge cases or a high cost of error get a high tier. Before moving up a tier, first give the implementer a self-check in the brief (a test, build or command it can run). When unsure, use the stronger model; verification criteria do not change with the model.
- A brief must include: intent (why) / which files to change and in what order / verification criteria (executable commands or observable behavior, never "works correctly") / constraints and risks / references (source, test and prototype file paths; prefer files over prose). Standard: someone who has not seen this conversation can implement from the brief alone.
- Before writing a brief, the main session writes out implicit assumptions and possibly missed edge cases and puts them in the brief.
- After the implementer returns, the main session sends an independent `verifier` (read-only, no implementation history; invocation is in the host entry file) to check against the verification criteria, and decides based on the verifier report. If the verifier returns FAIL, brief the implementer again with the issue list, at most 3 rounds; if it still fails, stop and hand over to the user.
- Exception: pure conversation, code-reading Q&A and trivial one- or two-line changes are handled by the main session directly, with no verifier.

## Way of working

- Scope follows the functional meaning of the user's intent, not the literal wording: "hide / remove / unify" a feature = remove all of its entry points (tab, top-bar button, panel, track, copy); before the brief, grep and list the entry points in the brief. "Confirm / take a look" = answer only, change nothing. Ask once whether a change must stay compatible with old data; for internal single-user products, keep no compatibility branch by default (adjust to your situation). If scope must grow, explain why first.
- When a request involves copy, pages, modes or providers, state your understanding in one sentence and have the user confirm before the brief: web UI or chat report, standalone page or embedded in an existing page, global or under one mode, multiple providers coexisting or switching. By default providers coexist with no switching, and pages are standalone. This kind of misreading is the main source of past friction; one confirming sentence is cheaper than rework.
- Do not introduce a new framework / dependency / architecture pattern unless the task clearly needs it and you explain the tradeoff.
- For external facts such as filings, permissions, contracts or whether something is deployed, a tool not finding it does not mean it does not exist. Before a directional decision, have the user check the authoritative source, or check every reachable resource before concluding.
- When proposing a configuration / entry-point solution, first give the simplest version that is explicit, has no implicit state and has the widest allowance, and state its risks. List narrowing and automation afterwards as options, not as the default.
- Run authorized remote and deploy commands directly. Do not stop and ask the user to run them by hand; command form and permission config are in the current host entry file. Permissions follow the current host's actual rules; an allowance on another host is not authorization on this host. When the execution environment requires approval, follow its process.
- Work that needs deterministic guarantees — counting, deduplication, sorting, batch validation, numeric calculation — uses scripts or deterministic tools, not LLM judgment. Judgment, classification and synthesis can be done by the LLM.
- API keys / secrets go in one location outside the repo (e.g. `~/.config/<your-name>/secrets.env`). The repo `.env` holds no secrets. If that file is sourced by a shell, values containing characters such as `|`, `;` or spaces must be quoted.

## Engineering verification

- After making changes, prefer running the project's existing test / build / lint.
- If verification commands cannot run, state why and the unverified risk.
- An implementer subagent's self-report is not evidence of completion; done = verifier check passed or the main session ran the verification commands itself.
- Must not report done based on mocks / fake providers / reading code only. Changes involving an LLM, external API or database must go through a real provider path once. User-visible UI changes must be walked through for real with the browser tool available on the current host.
- When reporting done, list explicitly which verifications were done (real call / browser walkthrough / commit made) and which were not and why. Do not say "should work" about anything unverified.

## Git

- Commit message: English, imperative mood, capitalized, ≤72 characters, format `<type>: <summary>` (type: feat / fix / refactor / docs / test / chore).
- You may create commits proactively based on project progress.
- Do not start outbound communication (push, PR comment, messages, email) on your own — it needs explicit authorization.

## Project memory and handoff

- Project progress, decisions and lessons live in the project repository, not in this global file.
- Project-level rules (`AGENTS.md` / `.ai/` at the project root) take precedence over this file.
- If the project has a `.ai/` directory, read `.ai/PROGRESS.md` before substantive work, and `DECISIONS.md` and `GOTCHAS.md` when relevant.
- After a phased task ends (substantive code/file changes, verified), the main session invokes the `wrap` skill on its own to update `.ai/`. If the project has no `.ai/` directory, first copy `PROGRESS.md` / `DECISIONS.md` / `GOTCHAS.md` from the templates (`templates/project/.ai/` in this repo, `~/.ai/templates/` after install), then record. Pure conversation, Q&A, trivial one- or two-line changes, and intermediate steps of a large task do not trigger it.
- For long multi-step tasks (expected to span several subagents or several hours), after each milestone immediately append one checkpoint line to `.ai/PROGRESS.md`: what is done (with commit sha), the concrete next action, blockers. Append only, never overwrite. Purpose: after an API interruption or a session restart, a new session can continue by reading the file, without the user explaining again.
