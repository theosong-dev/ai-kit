// Token Weather: a live forecast of the context window, above the prompt.
// Based on the official "Getting started with Claude Code mods" walkthrough.

const HISTORY = 12;
const WIDE = 60; // below this many columns the band drops the sparkline and trend
const BARS = "▁▂▃▄▅▆▇█";
const FORECAST = [
  { upTo: 25, icon: "☀", word: "Clear", color: "yellow" },
  { upTo: 50, icon: "☁", word: "Cloudy", color: "cyan" },
  { upTo: 75, icon: "☂", word: "Showers", color: "blue" },
  { upTo: 90, icon: "☇", word: "Storm", color: "magenta" },
  { upTo: Infinity, icon: "↯", word: "Compact soon", color: "red" },
];

// Held by the host, so the history survives a hot reload of this file.
const readings = { plugin: "token-weather", key: "readings" };

export function register(on) {
  on("session.start", async ($, e, next) => {
    const result = await next(e);
    await takeReading($);
    return result;
  });

  on("turn.complete", async ($, e, next) => {
    const result = await next(e);
    if (!e.agentId) {
      await takeReading($); // main-loop turns only, not subagents
    }
    return result;
  });

  on("ui.render", { component: "AbovePrompt" }, async ($, e, next) => {
    const { value: history = [] } = await $.state.get(readings);
    if (e.props.hasSurvey || history.length === 0) {
      return next(e);
    }
    const { Box, Text } = $.ui.resolve(e);
    return band(Box, Text, history, e.props.bodyColumns);
  });
}

async function takeReading($) {
  const { context } = await $.session.usage();
  if (!context?.window) return; // no window, no reading
  const tokens = context.tokens ?? 0;
  const percent = context.percent ?? Math.round((tokens / context.window) * 100);
  const { value: history = [] } = await $.state.get(readings);
  await $.state.set(
    readings,
    [...history, { tokens, window: context.window, percent }].slice(-HISTORY),
  );
}

function forecastFor(percent) {
  return FORECAST.find((b) => percent < b.upTo);
}

function band(Box, Text, history, columns) {
  const now = history[history.length - 1];
  const f = forecastFor(now.percent);
  const isWide = columns >= WIDE;
  const cut = "truncate-end"; // a narrow band is cut, never wrapped onto a second row
  const parts = [
    Text({ key: "sky", color: f.color, bold: true, wrap: cut, children: isWide ? `${f.icon}  ${f.word}` : f.icon }),
    Text({ key: "pct", wrap: cut, children: isWide ? `  ${now.percent}% of context` : ` ${now.percent}%` }),
    Text({ key: "tok", dimColor: true, wrap: cut, children: `  ${short(now.tokens)} / ${short(now.window)}` }),
  ];
  if (isWide) {
    parts.push(Text({ key: "label", dimColor: true, children: "   last turns " }));
    parts.push(Text({ key: "spark", color: f.color, children: sparkline(history) }));
    if (history.length > 1) {
      parts.push(Text({ key: "trend", dimColor: true, children: trend(history) }));
    }
  }
  return Box({ flexDirection: "row", flexWrap: "nowrap", overflow: "hidden", paddingX: 1, children: parts });
}

function sparkline(history) {
  const top = Math.max(...history.map((r) => r.tokens), 1);
  return history.map((r) => BARS[Math.floor((r.tokens / top) * (BARS.length - 1))]).join("");
}

function trend(history) {
  const delta = history[history.length - 1].tokens - history[history.length - 2].tokens;
  if (delta === 0) return "  steady";
  return delta > 0 ? `  ▲ +${short(delta)} last turn` : `  ▼ ${short(-delta)} last turn`;
}

function short(n) {
  if (n >= 1_000_000) return `${+(n / 1_000_000).toFixed(1)}M`;
  if (n >= 1_000) return `${+(n / 1_000).toFixed(1)}k`;
  return String(n);
}
