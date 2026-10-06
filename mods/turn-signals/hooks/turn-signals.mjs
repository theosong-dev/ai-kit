// Turn Signals: a lean, cross-session signal log. One JSON line per tool call
// that failed or was refused, one per finished main-loop turn, and one per
// interrupted turn, plus one per finished turn of a `verifier` subagent
// (its verdict and tagged issues), appended to a single file both accounts
// share.
//
// Rules this module keeps:
// - every hook passes its event on unchanged (`next(e)`) and returns what
//   `next` resolved: it observes, never rewrites or blocks;
// - a failure to write is swallowed: the session never sees it;
// - nothing is written from session.start, so a hot reload (which runs
//   register and session.start again) writes no duplicate lines;
// - per-turn counters live in `$.state`, which a hot reload keeps.

import { update } from "claude-code";

const DEFAULT_PATH = "/.local/state/claude-insight/turn-signals.jsonl"; // under $HOME
const ERROR_CHARS = 200;
const COMMAND_CHARS = 120;
const EXEC_FAILED_KEEP = 50;
const WRITE_TIMEOUT_MS = 3_000;
const ISSUE_CHARS = 160;
const ISSUES_KEEP = 12;
const ISSUE_CATS = new Set([
  "no-real-path", "criteria-fail", "test-fail", "out-of-scope", "uncommitted", "false-claim", "other",
]);

const counts = { plugin: "turn-signals", key: "counts" };
const execFailed = { plugin: "turn-signals", key: "execFailed" };
const agentTypes = { plugin: "turn-signals", key: "agentTypes" };
const AGENTS_KEEP = 50;

export function register(on) {
  // The main loop's turn begins: its counters start over (a subagent's run
  // raises no turn.start).
  on("turn.start", async ($, e, next) => {
    await guard($, () => $.state.set(counts, { calls: 0, failures: 0 }));
    return next(e);
  });

  // Fires for a tool that ran and failed (or was interrupted), before the
  // tool.call chain resolves; a call refused before it ran never raises it.
  on("classic.PostToolUseFailure", async ($, e, next) => {
    await guard($, () =>
      update($, execFailed, (list) =>
        [...(list ?? []), { id: e.tool_use_id, isInterrupt: e.is_interrupt === true }].slice(-EXEC_FAILED_KEEP),
      ),
    );
    return next(e);
  });

  // A subagent's type is known only from these classic events: `$.agent.list()`
  // leaves out Agent-tool subagents. Start gives spawn order; Stop backs it up.
  on("classic.SubagentStart", async ($, e, next) => {
    await guard($, () => noteAgent($, e));
    return next(e);
  });
  on("classic.SubagentStop", async ($, e, next) => {
    await guard($, () => noteAgent($, e));
    return next(e);
  });

  on("tool.call", async ($, e, next) => {
    const result = await next(e);
    await guard($, () => afterToolCall($, e, result));
    return result;
  });

  on("turn.complete", async ($, e, next) => {
    const result = await next(e);
    if (!e.agentId) {
      await guard($, () => afterTurn($, e));
    } else {
      await guard($, () => afterSubagentTurn($, e));
    }
    return result;
  });
}

async function afterToolCall($, e, result) {
  const isMain = !e.agentId;
  const kind = await failureKind($, e, result);
  if (isMain) {
    await update($, counts, (c) => ({
      calls: (c?.calls ?? 0) + 1,
      failures: (c?.failures ?? 0) + (kind ? 1 : 0),
    }));
  }
  if (!kind) return;
  const message = result.deny ?? result.text ?? (typeof result.result === "string" ? result.result : "");
  const line = {
    type: "tool",
    kind,
    ...(await envelope($)),
    tool: e.tool,
    subagent: !isMain,
    ...(isMain ? {} : { agentId: e.agentId }),
    error: String(message).slice(0, ERROR_CHARS),
  };
  if (e.tool === "Bash" && typeof e.command === "string") {
    line.command = e.command.slice(0, COMMAND_CHARS);
  }
  await append($, line);
}

// "error": the tool ran and failed; "interrupted": it was stopped while
// running; "refused": it never ran (a permission rule or mode, the person's
// "no", a PreToolUse hook's deny, or a deny from a plugin beneath this one).
async function failureKind($, e, result) {
  if (result.deny !== undefined) return "refused";
  if (result.isError !== true) return undefined;
  const { value: list = [] } = await $.state.get(execFailed);
  const ran = list.find((f) => f.id === e.tool_use_id);
  if (!ran) return "refused";
  return ran.isInterrupt ? "interrupted" : "error";
}

async function afterTurn($, e) {
  const { value: c = { calls: 0, failures: 0 } } = await $.state.get(counts);
  await $.state.set(counts, { calls: 0, failures: 0 });
  const base = await envelope($);
  await append($, {
    type: "turn",
    ...base,
    reason: e.reason,
    durationMs: e.durationMs,
    tools: c.calls,
    failures: c.failures,
  });
  if (e.isAborted || e.reason === "aborted") {
    await append($, { type: "interrupt", ...base, durationMs: e.durationMs, tools: c.calls });
  }
}

// Records a subagent's `{id, type}` once, in spawn order (SubagentStart
// first; SubagentStop only adds one whose start was missed).
async function noteAgent($, e) {
  if (typeof e.agent_id !== "string" || typeof e.agent_type !== "string") return;
  await update($, agentTypes, (list) => {
    const l = list ?? [];
    if (l.some((a) => a.id === e.agent_id)) return l;
    return [...l, { id: e.agent_id, type: e.agent_type }].slice(-AGENTS_KEEP);
  });
}

// A subagent's turn ended: only a verifier's is recorded. Its type comes
// from the SubagentStart/Stop record (SubagentStop fires before this).
async function afterSubagentTurn($, e) {
  const { value: agents = [] } = await $.state.get(agentTypes);
  const at = agents.findIndex((a) => a.id === e.agentId);
  if (at < 0 || !isVerifier(agents[at].type)) return;
  // The list carries no spawn time; its order is taken as spawn order.
  const before = agents.slice(0, at).filter((a) => typeof a.type === "string" && !isVerifier(a.type));
  const implementer = before.length > 0 ? before[before.length - 1].type : undefined;
  const answer = typeof e.answer === "string" ? e.answer : "";
  await append($, {
    type: "verdict",
    ...(await envelope($)),
    agentId: e.agentId,
    ...(implementer ? { implementer } : {}),
    verdict: parseVerdict(answer),
    issues: parseIssues(answer),
  });
}

// `verifier`, or a plugin's `<plugin>:verifier`.
function isVerifier(type) {
  return typeof type === "string" && type.split(":").pop() === "verifier";
}

// The last `VERDICT: X` wins: an answer may quote the brief's template line
// (`VERDICT: PASS | FAIL | PASS-WITH-NOTES`) before its own.
function parseVerdict(answer) {
  const re = /VERDICT[*`\s]*:[*`\s]*(PASS-WITH-NOTES|PASS|FAIL)/g;
  let verdict = "UNKNOWN";
  for (const m of answer.matchAll(re)) verdict = m[1];
  return verdict;
}

// Lines like `- [no-real-path] text`, `1. **[test-fail]** text`: an optional
// list marker, optional `**`, then a lowercase slug in brackets. A slug off
// the list counts as `other`; `[x]`, `[N]` or `[link](url)` is no issue.
function parseIssues(answer) {
  const re = /^\s*(?:[-*]\s+|\d+[.)、]\s*)?(?:\*\*)?\[([a-z][a-z-]*)\](?!\()(?:\*\*)?(.*)$/;
  const issues = [];
  for (const line of answer.split(/\r?\n/)) {
    if (issues.length >= ISSUES_KEEP) break;
    const m = re.exec(line);
    if (!m || m[1].length < 2) continue;
    const cat = ISSUE_CATS.has(m[1]) ? m[1] : "other";
    const text = m[2].replace(/\*\*/g, "").trim().slice(0, ISSUE_CHARS);
    issues.push({ cat, text });
  }
  return issues;
}

async function envelope($) {
  const [now, session, cwd, account] = await Promise.all([
    $.clock.now(),
    $.session.id(),
    $.session.cwd(),
    accountLabel($),
  ]);
  return { ts: new Date(now).toISOString(), session, cwd, ...(account ? { account } : {}) };
}

// The plugin API carries no account, so it is named after the configuration
// directory: CLAUDE_CONFIG_DIR's last segment without its leading dot
// (~/.claude-2 -> "claude-2"); unset, Claude Code uses ~/.claude.
async function accountLabel($) {
  const dir = await $.env.get("CLAUDE_CONFIG_DIR");
  if (dir === undefined || dir === "") return "claude";
  const base = dir.replace(/[\\/]+$/, "").split(/[\\/]/).pop() ?? "";
  const name = base.replace(/^\./, "");
  return name === "" ? undefined : name;
}

async function logPath($) {
  const override = await $.env.get("TURN_SIGNALS_PATH");
  if (override) return override;
  const home = await $.env.get("HOME");
  return home ? home + DEFAULT_PATH : undefined;
}

// One line, appended with O_APPEND by the shell, so two sessions (or two
// accounts) writing at once never clobber each other; the folder is made
// when missing. `$.fs.write` would replace the whole file instead.
async function append($, record) {
  const path = await logPath($);
  if (!path) return;
  const { exitCode, stderr } = await $.process.run(
    ["/bin/sh", "-c", 'mkdir -p "$(dirname "$1")" && cat >> "$1"', "turn-signals", path],
    { stdin: JSON.stringify(record) + "\n", timeoutMs: WRITE_TIMEOUT_MS },
  );
  if (exitCode !== 0) throw new Error(`append exited ${exitCode}: ${stderr.slice(0, 200)}`);
}

// Runs `work`, swallowing anything it throws: a signal lost is better than a
// session disturbed. The reason goes to the debug log only.
async function guard($, work) {
  try {
    await work();
  } catch (err) {
    try {
      $.ui.log(`turn-signals: ${String(err?.message ?? err).slice(0, 200)}`, { to: "debug" });
    } catch {
      // nothing left to do
    }
  }
}
