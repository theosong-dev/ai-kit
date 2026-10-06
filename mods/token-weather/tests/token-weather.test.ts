import { describe, expect, test } from "claude-code/testing";

const BAND = (bodyColumns: number, hasSurvey = false) =>
  ({
    plugin: "token-weather",
    surface: "terminal",
    component: "AbovePrompt",
    props: { hasSurvey, isWorking: false, maxRows: 10, bodyColumns },
  }) as any;

// What the engine draws when the mod passes: an empty marker Box to find by key.
const ENGINE_BAND = ($: any, e: any) => {
  const { Box } = $.ui.resolve(e);
  return Box({ key: "engine" });
};

describe("token-weather", () => {
  test("the band walks through all five tiers with trend text", async ($, on) => {
    // Hooks registered here sit beneath the mod and stand for Claude Code.
    let tokens = 36_100;
    on("session.start", ($, e) => ({ cwd: e.cwd }));
    on("session.usage", () => ({
      value: {
        startedAt: 0,
        rateLimits: [],
        context: { tokens, window: 200_000, percent: Math.round(tokens / 2_000) },
      },
    }));
    on("turn.complete", () => ({ text: "" }));

    await $.session.start({ surface: "terminal", isInteractive: true, cwd: "/work" } as any);
    const ui = await $.ui.mount(BAND(120));
    expect(await ui.find({ type: "Text", text: /Clear/ })).toBeDefined();
    expect(await ui.find({ type: "Text", text: /18% of context/ })).toBeDefined();

    const turn = async (t: number) => {
      tokens = t;
      await $.turn.complete({ reason: "answer", answer: "ok", durationMs: 1 } as any);
    };

    await turn(80_000); // 40%
    expect(await ui.find({ type: "Text", text: /Cloudy/ })).toBeDefined();
    expect(await ui.find({ type: "Text", text: /▲ \+43\.9k last turn/ })).toBeDefined();

    await turn(134_400); // 67%
    expect(await ui.find({ type: "Text", text: /Showers/ })).toBeDefined();
    expect(await ui.find({ type: "Text", text: /67% of context/ })).toBeDefined();

    await turn(170_000); // 85%
    expect(await ui.find({ type: "Text", text: /Storm/ })).toBeDefined();

    await turn(190_000); // 95%
    expect(await ui.find({ type: "Text", text: /Compact soon/ })).toBeDefined();
    expect(await ui.find({ type: "Text", text: /190k \/ 200k/ })).toBeDefined();

    await turn(190_000);
    expect(await ui.find({ type: "Text", text: /steady/ })).toBeDefined();

    await turn(60_000); // after a compaction: 30%, falling
    expect(await ui.find({ type: "Text", text: /Cloudy/ })).toBeDefined();
    expect(await ui.find({ type: "Text", text: /▼ 130k last turn/ })).toBeDefined();
    await ui.unmount();
  });

  test("tier boundaries: 25 is Cloudy, 24 is Clear, 90 is Compact soon", async ($, on) => {
    let percent = 24;
    on("session.start", ($, e) => ({ cwd: e.cwd }));
    on("session.usage", () => ({
      value: { startedAt: 0, rateLimits: [], context: { tokens: percent * 2_000, window: 200_000, percent } },
    }));
    on("turn.complete", () => ({ text: "" }));
    await $.session.start({ surface: "terminal", isInteractive: true, cwd: "/work" } as any);
    const ui = await $.ui.mount(BAND(120));
    expect(await ui.find({ type: "Text", text: /Clear/ })).toBeDefined();
    for (const [p, word] of [[25, /Cloudy/], [50, /Showers/], [75, /Storm/], [90, /Compact soon/]] as const) {
      percent = p;
      await $.turn.complete({ reason: "answer", answer: "", durationMs: 1 } as any);
      expect(await ui.find({ type: "Text", text: word })).toBeDefined();
    }
    await ui.unmount();
  });

  test("subagent turns, missing window, narrow band and surveys", async ($, on) => {
    let tokens = 20_000;
    let window: number | undefined = 200_000;
    on("session.start", ($, e) => ({ cwd: e.cwd }));
    on("session.usage", () => ({ value: { startedAt: 0, rateLimits: [], context: { tokens, window } } }));
    on("turn.complete", () => ({ text: "" }));
    on("ui.render", ENGINE_BAND); // stands for what the engine draws when the mod yields

    await $.session.start({ surface: "terminal", isInteractive: true, cwd: "/work" } as any);

    // A subagent's turn is not a reading.
    tokens = 150_000;
    await $.turn.complete({ reason: "answer", answer: "", durationMs: 1, agentId: "a1" } as any);
    let ui = await $.ui.mount(BAND(120));
    expect(await ui.find({ type: "Text", text: /10% of context/ })).toBeDefined();
    expect(await ui.find({ type: "Text", text: /▲|▼|steady/ })).toBeUndefined();
    await ui.unmount();

    // No window, no reading: the band still shows the last one.
    window = undefined;
    await $.turn.complete({ reason: "answer", answer: "", durationMs: 1 } as any);
    ui = await $.ui.mount(BAND(120));
    expect(await ui.find({ type: "Text", text: /10% of context/ })).toBeDefined();
    await ui.unmount();

    // Narrow: no sparkline, no trend, no forecast word.
    ui = await $.ui.mount(BAND(40));
    expect(await ui.find({ type: "Text", text: /10%/ })).toBeDefined();
    expect(await ui.find({ type: "Text", text: /last turns/ })).toBeUndefined();
    expect(await ui.find({ type: "Text", text: /Clear/ })).toBeUndefined();
    await ui.unmount();

    // A survey holds the band: the mod yields.
    ui = await $.ui.mount(BAND(120, true));
    expect(await ui.find({ type: "Text", text: /of context/ })).toBeUndefined();
    expect(await ui.find({ key: "engine" })).toBeDefined();
    await ui.unmount();
  });

  test("no reading yet draws nothing", async ($, on) => {
    on("session.start", ($, e) => ({ cwd: e.cwd }));
    on("session.usage", () => ({ value: { startedAt: 0, rateLimits: [], context: {} } }) as any);
    on("ui.render", ENGINE_BAND);
    await $.session.start({ surface: "terminal", isInteractive: true, cwd: "/work" } as any);
    const ui = await $.ui.mount(BAND(120));
    expect(await ui.find({ type: "Text", text: /of context/ })).toBeUndefined();
    expect(await ui.find({ key: "engine" })).toBeDefined();
    await ui.unmount();
  });
});
