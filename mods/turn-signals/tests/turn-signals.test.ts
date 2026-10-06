import { describe, expect, mock, test } from "claude-code/testing";

const NOW = Date.parse("2026-10-03T12:00:00.000Z");
const PATH = "/tmp/turn-signals-test/signals.jsonl";

type Write = { argv: readonly string[]; stdin?: string };

// Stands for the engine and the host: session facts, and process.run, which
// records each append instead of running a shell (the test kit runs none).
function engine(on: any, opts: { failWrite?: "throw" | "exit"; agents?: { id: string; type: string }[] } = {}) {
  const writes: Write[] = [];
  mock.clock(on, { now: NOW });
  mock.env(on, { TURN_SIGNALS_PATH: PATH, CLAUDE_CONFIG_DIR: "/Users/me/.claude-2", HOME: "/Users/me" });
  on("session.id", () => ({ value: "sess-1" }));
  on("session.cwd", () => ({ value: "/work" }));
  on("classic.PostToolUseFailure", () => ({})); // no settings hook beneath
  const debug: string[] = [];
  on("ui.log", ($: any, e: any) => {
    debug.push(e.text);
    return { value: undefined };
  });
  on("turn.start", ($: any, e: any) => ({ turnId: e.turnId }));
  on("turn.complete", () => ({ text: "" }));
  on("classic.SubagentStart", () => ({}));
  on("classic.SubagentStop", () => ({}));
  on("process.run", ($: any, e: any) => {
    if (opts.failWrite === "throw") throw new Error("EACCES: permission denied");
    writes.push({ argv: e.argv, stdin: e.init?.stdin });
    return {
      value: {
        exitCode: opts.failWrite === "exit" ? 1 : 0,
        stdout: "",
        stderr: opts.failWrite === "exit" ? "mkdir: read-only file system" : "",
        isStdoutTruncated: false,
        isStderrTruncated: false,
      },
    };
  });
  const lines = () => writes.map((w) => JSON.parse(w.stdin ?? "null"));
  return { writes, lines, debug };
}

describe("turn-signals", () => {
  test("a failed Bash call is recorded, then the turn summary", async ($, on) => {
    const { writes, lines } = engine(on);
    // The tool calls beneath the mod: Bash fails after running (the engine
    // raises PostToolUseFailure first), Read succeeds.
    on("tool.call", async (_: any, e: any) => {
      if (e.tool === "Bash") {
        await $.classic.PostToolUseFailure({
          tool_name: "Bash",
          tool_input: { command: e.command },
          tool_use_id: e.tool_use_id,
          error: "Exit code 2",
          is_interrupt: false,
        } as any);
        return { isError: true, result: "Error: Exit code 2", text: "Exit code 2\nls: /nonexistent-dir-xyz: No such file or directory" };
      }
      return { result: { ok: true }, text: "ok" };
    });

    await $.turn.start({ text: "go", turnId: "t1" });
    const bash = await $.tool.call({ tool: "Bash", command: "ls /nonexistent-dir-xyz", description: "list" } as any);
    expect(bash.isError).toBe(true); // passed on unchanged
    await $.tool.call({ tool: "Read", file_path: "/work/a.txt" } as any);
    await $.turn.complete({ reason: "answer", answer: "done", durationMs: 1234, isAborted: false, turnId: "t1" } as any);

    expect(writes.every((w) => w.argv.at(-1) === PATH)).toBe(true);
    const [tool, turn, ...rest] = lines();
    expect(rest).toEqual([]);
    expect(tool).toEqual({
      type: "tool",
      kind: "error",
      ts: "2026-10-03T12:00:00.000Z",
      session: "sess-1",
      cwd: "/work",
      account: "claude-2",
      tool: "Bash",
      subagent: false,
      error: "Exit code 2\nls: /nonexistent-dir-xyz: No such file or directory",
      command: "ls /nonexistent-dir-xyz",
    });
    expect(turn).toEqual({
      type: "turn",
      ts: "2026-10-03T12:00:00.000Z",
      session: "sess-1",
      cwd: "/work",
      account: "claude-2",
      reason: "answer",
      durationMs: 1234,
      tools: 2,
      failures: 1,
    });
  });

  test("a call refused before it ran is 'refused'; long text is cut", async ($, on) => {
    const { lines } = engine(on);
    const long = "Permission to use Write has been denied. " + "x".repeat(400);
    on("tool.call", () => ({ isError: true, result: "Error: " + long, text: long }));

    await $.turn.start({ text: "go", turnId: "t1" });
    await $.tool.call({ tool: "Write", file_path: "/work/b.txt", content: "hi" } as any);
    await $.turn.complete({ reason: "answer", answer: "", durationMs: 5, isAborted: false, turnId: "t1" } as any);

    const [tool, turn] = lines();
    expect(tool.kind).toBe("refused");
    expect(tool.tool).toBe("Write");
    expect(tool.error.length).toBe(200);
    expect(tool.command).toBeUndefined();
    expect(turn.failures).toBe(1);
  });

  test("an interrupted turn writes its summary and an interrupt line", async ($, on) => {
    const { lines } = engine(on);
    on("tool.call", () => ({ result: {}, text: "ok" }));
    await $.turn.start({ text: "go", turnId: "t1" });
    await $.tool.call({ tool: "Read", file_path: "/work/a.txt" } as any);
    await $.turn.complete({ reason: "aborted", answer: "", durationMs: 900, isAborted: true, turnId: "t1" } as any);
    const [turn, interrupt] = lines();
    expect(turn).toMatchObject({ type: "turn", reason: "aborted", tools: 1, failures: 0 });
    expect(interrupt).toMatchObject({ type: "interrupt", session: "sess-1", durationMs: 900, tools: 1 });
  });

  test("successful calls write nothing until the turn ends; subagent turns write no summary", async ($, on) => {
    const { lines } = engine(on);
    on("tool.call", () => ({ result: {}, text: "ok" }));
    await $.turn.start({ text: "go", turnId: "t1" });
    await $.tool.call({ tool: "Read", file_path: "/work/a.txt" } as any);
    expect(lines()).toEqual([]);
    await $.turn.complete({ reason: "answer", answer: "", durationMs: 1, isAborted: false, turnId: "t9", agentId: "agent-1" } as any);
    expect(lines()).toEqual([]);
  });

  for (const failWrite of ["throw", "exit"] as const) {
    test(`a write that fails (${failWrite}) never reaches the session`, async ($, on) => {
      const { debug } = engine(on, { failWrite });
      const answer = { isError: true, result: "Error: boom", text: "boom" } as const;
      on("tool.call", async (_: any, e: any) => {
        await $.classic.PostToolUseFailure({ tool_name: e.tool, tool_input: {}, tool_use_id: e.tool_use_id, error: "boom" } as any);
        return answer;
      });
      await $.turn.start({ text: "go", turnId: "t1" });
      const result = await $.tool.call({ tool: "Bash", command: "false", description: "fail" } as any);
      expect(result.isError).toBe(true);
      expect(result.text).toBe("boom");
      const done = await $.turn.complete({ reason: "answer", answer: "a", durationMs: 1, isAborted: false, turnId: "t1" } as any);
      expect(done.text).toBe("");
      // The failure was met and swallowed: only the debug log heard of it.
      expect(debug.some((t) => t.startsWith("turn-signals: "))).toBe(true);
    });
  }
  const AGENTS = [
    { id: "a-impl", type: "opus-implementer" },
    { id: "a-ver", type: "verifier" },
    { id: "a-other", type: "Explore" },
    { id: "a-plug", type: "lab:verifier" },
  ];
  const finish = ($: any, agentId: string, answer: unknown) =>
    $.turn.complete({ reason: "answer", answer, durationMs: 1, isAborted: false, turnId: "s1", agentId } as any);

  test("a verifier's FAIL is recorded with its tagged issues and the implementer before it", async ($, on) => {
    const { lines } = engine(on, { agents: AGENTS });
    for (const a of AGENTS) await $.classic.SubagentStart({ agent_id: a.id, agent_type: a.type } as any);
    const answer = [
      "Brief asked for `VERDICT: PASS | FAIL | PASS-WITH-NOTES`.",
      "- [no-real-path] only the **mock** run was shown",
      "2. **[test-fail]** `npm test` fails on case 3",
      "- [x] done item",
      "See [the docs](https://example.com) and [N] notes.",
      "",
      "**VERDICT: FAIL**",
    ].join("\n");
    await finish($, "a-ver", answer);
    expect(lines()).toEqual([
      {
        type: "verdict",
        ts: "2026-10-03T12:00:00.000Z",
        session: "sess-1",
        cwd: "/work",
        account: "claude-2",
        agentId: "a-ver",
        implementer: "opus-implementer",
        verdict: "FAIL",
        issues: [
          { cat: "no-real-path", text: "only the mock run was shown" },
          { cat: "test-fail", text: "`npm test` fails on case 3" },
        ],
      },
    ]);
  });

  test("PASS-WITH-NOTES stays itself; an unknown slug is 'other'; a plugin verifier counts", async ($, on) => {
    const { lines } = engine(on, { agents: AGENTS });
    for (const a of AGENTS) await $.classic.SubagentStart({ agent_id: a.id, agent_type: a.type } as any);
    await finish($, "a-plug", "1) [style-nit] naming is loose\nVERDICT: `PASS-WITH-NOTES`");
    const [line] = lines();
    expect(line.verdict).toBe("PASS-WITH-NOTES");
    expect(line.issues).toEqual([{ cat: "other", text: "naming is loose" }]);
    expect(line.implementer).toBe("Explore");
  });

  // The engine refuses a turn.complete with no string `answer` before any
  // hook sees it, so the empty answer stands for "nothing said" here.
  test("no VERDICT line, or an empty answer, is UNKNOWN; no implementer before it, no field", async ($, on) => {
    const { lines } = engine(on, { agents: [{ id: "a-ver", type: "verifier" }] });
    for (const a of [{ id: "a-ver", type: "verifier" }]) await $.classic.SubagentStart({ agent_id: a.id, agent_type: a.type } as any);
    await finish($, "a-ver", "ran out of turns");
    await finish($, "a-ver", "");
    const got = lines();
    expect(got.length).toBe(2);
    for (const l of got) {
      expect(l.verdict).toBe("UNKNOWN");
      expect(l.issues).toEqual([]);
      expect("implementer" in l).toBe(false);
    }
  });

  test("a non-verifier subagent's turn writes nothing; the main loop's turn line is unchanged", async ($, on) => {
    const { lines } = engine(on, { agents: AGENTS });
    for (const a of AGENTS) await $.classic.SubagentStart({ agent_id: a.id, agent_type: a.type } as any);
    await $.turn.start({ text: "go", turnId: "t1" });
    await finish($, "a-impl", "VERDICT: PASS");
    await finish($, "a-other", "VERDICT: FAIL");
    expect(lines()).toEqual([]);
    await $.turn.complete({ reason: "answer", answer: "VERDICT: PASS", durationMs: 7, isAborted: false, turnId: "t1" } as any);
    expect(lines().map((l: any) => l.type)).toEqual(["turn"]);
  });
});
