# Main Session and Implementers: Planning, Briefing, and Verification Kept Separate

English | [简体中文](zh-CN/02-主会话与实施分工.md)

The approach in one sentence: **the main session only plans, briefs, and verifies; implementation goes to a subagent, and verification goes to another subagent that carries no implementation history.**

## Why split

**The main session's context is reserved for judgment.** Implementation produces a lot of intermediate output from reading files, running commands, and editing code. If all of it piles up in the main session, context fills with detail and direction-setting later gets harder to see clearly. With implementation in a subagent, the main session gets back only the conclusion.

**The implementer's self-report cannot be trusted.** When the agent that wrote the code says "tests pass" or "no problems", that does not mean they really pass. This is not an attitude problem: someone inside the same context has a hard time finding their own blind spots. So verification must be done by a different agent, and it must not be shown the implementation process, so that it does not follow the implementer's line of thought.

## Briefing

### Write the implicit assumptions and edge cases before the brief

Before writing the brief, the main session lists the implicit assumptions the change depends on (for example "this field is never null", "this endpoint is only called after login") and the likely edge cases. A lot of rework is not because the implementer lacks ability, but because these things exist only in the main session's head and never made it into the brief.

### Five elements

1. **Intent**: what to achieve, and why.
2. **Which files to change, in what order.**
3. **Executable acceptance criteria**: commands that can be run and behavior that can be observed, not "the feature works".
4. **Constraints and risks**: what must not be touched, where mistakes are likely.
5. **Reference files**: related implementations, similar existing code.

The test: **someone who has not seen this conversation can complete the implementation from this brief alone.** If they cannot, the brief is still missing something.

## Four implementer agents, tiered by effort

Effort can only be written in the agent file's frontmatter and cannot be set ad hoc when briefing, so the agents are split by tier and you pick one by name when briefing:

| agent | model / effort | When to use |
|---|---|---|
| `sonnet-implementer` | sonnet / medium | Mechanical tasks with a fully clear plan, in one file or a few files |
| `opus-implementer` | opus / medium | Routine implementation with a clear plan but spanning files or needing more context to read. Use this when unsure |
| `opus-implementer-high` | opus / high | The plan leaves room for judgment, implementation paths need weighing, and a wrong change is costly |
| `opus-implementer-xhigh` | opus / xhigh | Non-obvious bugs, concurrency / consistency problems, core-path refactors |

### What to look at when choosing a tier

Effort buys **verification volume and edge-case coverage**; it cannot fix a wrong direction. So choosing a tier depends on two things: **how many hidden edge cases there are, and how costly a wrong change is**; not on task size. A large but purely mechanical migration is fine on a low tier; a three-line concurrency fix may need the highest tier.

### Give a self-check before moving up a tier

Before thinking of moving up a tier, first give the implementer a self-check in the brief: a test, build, or command it can run. **A check costs one round; moving up a tier means thinking harder in every round.** Most cases of "the low tier can't do it" happen because the implementer has no way to know it got something wrong, not because it did not think hard enough.

### Two failures means back to the main session

If the same problem fails twice, go back to the main session and re-decide the plan instead of moving up another tier. Two misses usually mean the plan itself is wrong, and a higher tier would only execute the wrong plan more diligently.

## Independent verifier

After the implementer agent returns, the main session dispatches the `verifier` for verification. Its design:

- **Read-only**: it changes no files.
- **No implementation history**: it receives only three things: the original brief, the diff / files to verify, and the acceptance criteria.
- **Its stance is to find evidence that overturns "done"**, not to confirm it. The implementer saying "tests pass" does not count; anything the verifier did not run itself is UNVERIFIED, not PASS.
- For each acceptance criterion it runs the corresponding command or observes the corresponding behavior itself, and gives **PASS / FAIL / UNVERIFIED** item by item; UNVERIFIED must say why it could not be verified.
- Issues it finds carry a category tag, so that you can later count which kinds of problems keep recurring (see the input to `/distill` in `01-two-loop-memory.md`).
- At most 3 rounds of implementation → verification. Beyond that, go back to the main session and look at the plan again.

## No reporting done on the basis of mocks

Passing unit tests does not mean the feature works, especially when the tests mock out external dependencies. The rules:

- If a change touches an **LLM / external API / database**, it must go through one real path; running only mocks or a fake provider does not count. If that cannot be run, mark it UNVERIFIED and say what is missing.
- For **user-visible UI changes**, walk through them in a real browser, with a screenshot or page text as evidence.
- When reporting done, **list which verifications were done and which were not**. For verifications not done, state why instead of leaving them out.

A real example: when adding a logging feature to a plugin, the code relied on a list API provided by the host to look up subagent types. The type declarations looked fine, and unit tests mocked this API, with all 10 cases passing. But after running once with the real command, there was not a single record in the log. Adding diagnostic output revealed that at real runtime this API returns an empty array and does not include subagents dispatched through the Agent tool at all. The mock returned "the data that should exist according to the declarations", while the real environment gave something else. Only a smoke run could find this problem. The convention since then: changes to this kind of plugin are not judged by mock unit tests, and the brief must include an acceptance command that runs for real.

## How to use it in this repo

- `claude/agents/`: the four implementer agents (`sonnet-implementer.md`, `opus-implementer.md`, `opus-implementer-high.md`, `opus-implementer-xhigh.md`) and `verifier.md`. Copy them to `~/.claude/agents/` to brief by name in Claude Code.
- The implementer agent bodies fix a return format with five sections: `Changed files`, `Verification commands and key raw output`, `Deviations` (from the brief), `Not done and why`, and `Decision notes` (approaches considered but not adopted). This spares the main session from re-reading the implementation process, and gives the verifier something it can check item by item.
- The main session itself can run at a lower effort, because it only plans and judges; the heavy work is in the subagents.

## Limitations

- The tier boundaries are judgment from experience; there has been no systematic comparison of the same task across tiers.
- The verifier's category-tag statistics depend on the signal log accumulating, and there is little data so far.
