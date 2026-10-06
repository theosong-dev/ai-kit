#!/usr/bin/env bash
# signals.sh -- cross-session recurrence collector for /distill (reads the turn-signals log).
#
#     bash signals.sh <PROJECT_ROOT> [--days N]      # default: last 30 days
#
# Log: defaults to ~/.local/state/claude-insight/turn-signals.jsonl; override with TURN_SIGNALS_PATH
# (format: mods/README.md in the ai-kit repo). Read-only; never writes the log.
#
# What it does (fully deterministic; output is "leads", not "verdicts"):
#   1. Keep only type=="tool" rows whose cwd is the project root or below it (compared by path segment,
#      so /a/foo does not match /a/foo-bar)
#      and whose ts (UTC ISO) is not earlier than "now - N days". The project root is made absolute
#      and stripped of trailing slashes; its realpath is accepted too.
#   2. Group by signature: tool + kind + Bash command head + normalized first error line.
#   3. Print only groups seen in >=2 distinct sessions (repeats within one session count once),
#      sorted by session count desc, total count desc, latest time desc, signature asc.
#      Each group: total count, session count, first/last date, up to 3 samples (at most 1 per
#      session, the most recent).
#
# First error line: strip angle-bracket tags such as <tool_use_error>, skip blank lines and Bash's
# "Exit code N" line, take the first non-empty line; if none, use "Exit code N" itself.
# Normalization (in order):
#   - quoted content -> ...: "x" 'x' `x` “x” ‘x’ 「x」 『x』 (paired within one line)
#   - URL → <URL>;uuid → <UUID>
#   - paths -> <PATH>: tokens starting with / ~/ ./ ../, and relative paths containing / (e.g. src/a.ts)
#   - hex strings of >=7 chars containing a digit (commits, agentIds, ...) -> <HEX>; other numbers -> <N>
#   - collapse whitespace, keep the first 80 chars (the log already truncates errors at 200 chars;
#     a shorter cut reduces false splits caused by different truncation points)
# Bash command head: drop a leading `cd X &&` / `cd X;`, env assignments, and sudo/env/time/nohup/
#   command/timeout N prefixes,
#   then take the first word (basename for paths); the second word is included when it looks like a
#   lowercase subcommand ([a-z][a-z0-9-]*) and the first word is not on
#   the "takes arguments, not subcommands" list (ls cat echo ssh bash python3 ...), e.g. `git push`, `npm run`.
# Known limitations:
#   - False merges: the same error on different files / quoted content lands in one group (by design);
#     when the first error line is only "Exit code N", different failures of one command head merge.
#   - False splits: one error class whose wording varies with arguments (singular/plural, extra hint
#     sentences) splits into several groups;
#     so does an unlisted CLI whose second word is a plain argument (`foo bar` vs `foo baz`).
#   - Plain words containing / (and/or) are erased as paths; apostrophes (doesn't ... it's) are
#     treated as a pair of single quotes and the text between them is erased.
#   4. "verifier leads" section: type=="verdict" rows (verifier conclusions; same window and project filter),
#      first the verdict distribution (rows per verdict, session count), then every issue category
#      grouped by issues[].cat,
#      sorted by session count desc, row count desc, cat asc; each group: rows, sessions, first/last
#      date, count per implementer,
#      up to 3 samples (at most 1 per session, the most recent). Groups with >=2 sessions get ★ (the distill entry bar).
#      Unknown cat -> other; non-array issues / non-object elements are skipped. The last line
#      ("all projects") is not filtered by project.
#
# Bad rows (not JSON or not an object) are skipped and counted at the end; tool/verdict rows missing
# ts/session/cwd or with an unparseable ts are skipped and counted too.
# Missing log, empty log, no matching groups, or no python3: print one line and exit 0.
# Requires python3 (stdlib only). Compatible with the bash 3.2 shipped with macOS.

set -u

if ! command -v python3 >/dev/null 2>&1; then
  echo "(python3 not found; skipping signal log analysis)"
  exit 0
fi

LOG="${TURN_SIGNALS_PATH:-$HOME/.local/state/claude-insight/turn-signals.jsonl}"

PYTHONIOENCODING=utf-8 python3 - "$LOG" "$@" <<'PY'
import json, os, re, sys
from datetime import datetime, timedelta, timezone

def usage(msg):
    sys.stderr.write("signals.sh: %s\nusage: bash signals.sh <PROJECT_ROOT> [--days N]\n" % msg)
    sys.exit(2)

log = sys.argv[1]
args = sys.argv[2:]
root_arg, days = None, 30
i = 0
while i < len(args):
    a = args[i]
    if a == "--days":
        if i + 1 >= len(args):
            usage("--days requires a value")
        v = args[i + 1]
        if not re.fullmatch(r"[0-9]+", v) or int(v) <= 0:
            usage("--days requires a positive integer, got %r" % v)
        days = min(int(v), 36500); i += 2; continue
    if a.startswith("--days="):
        v = a.split("=", 1)[1]
        if not re.fullmatch(r"[0-9]+", v) or int(v) <= 0:
            usage("--days requires a positive integer, got %r" % v)
        days = min(int(v), 36500); i += 1; continue
    if root_arg is None:
        root_arg = a; i += 1; continue
    usage("unexpected argument %r" % a)
if root_arg is None:
    root_arg = "."

def norm_dir(p):
    p = os.path.normpath(os.path.abspath(os.path.expanduser(p)))
    return p

roots = {norm_dir(root_arg), os.path.realpath(norm_dir(root_arg))}

def in_project(cwd):
    c = os.path.normpath(cwd)
    for r in roots:
        if r == "/":
            if c.startswith("/"):
                return True
        elif c == r or c.startswith(r + "/"):
            return True
    return False

if not os.path.isfile(log):
    print("(no signal log: %s does not exist; skipping)" % log)
    sys.exit(0)
if os.path.getsize(log) == 0:
    print("(signal log is empty: %s; skipping)" % log)
    sys.exit(0)

now = datetime.now(timezone.utc)
cutoff = now - timedelta(days=days)

def parse_ts(s):
    if not isinstance(s, str) or not s:
        return None
    try:
        t = datetime.fromisoformat(s.replace("Z", "+00:00"))
    except ValueError:
        return None
    if t.tzinfo is None:
        t = t.replace(tzinfo=timezone.utc)
    return t.astimezone(timezone.utc)

EXIT_RE = re.compile(r"^Exit code -?\d+$")

TAG_RE = re.compile(r"</?[A-Za-z_][\w-]*>")

def first_line(err):
    lines = [TAG_RE.sub("", l).strip() for l in err.splitlines()]
    lines = [l for l in lines if l]
    for l in lines:
        if not EXIT_RE.match(l):
            return l
    return lines[0] if lines else ""

QUOTES = [('"', '"'), ("'", "'"), ("`", "`"), ("“", "”"), ("‘", "’"),
          ("「", "」"), ("『", "』")]

def normalize(s):
    s = s[:2000]  # the writer already truncates to 200 chars; guard again so hand-edited or corrupt overlong rows cannot slow the regexes
    for o, c in QUOTES:
        s = re.sub(re.escape(o) + r"[^" + re.escape(o + c) + r"\n]*" + re.escape(c), o + "…" + c, s)
    s = re.sub(r"[A-Za-z][A-Za-z0-9+.-]*://\S+", "<URL>", s)
    s = re.sub(r"\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b", "<UUID>", s)
    s = re.sub(r"(?<![\w<])(?:~|\.{1,2})?/[^\s:;,()\[\]{}\"'`]*", "<PATH>", s)
    s = re.sub(r"(?<![\w<])[\w.-]+/[\w./-]+", "<PATH>", s)
    s = re.sub(r"\b(?=[0-9a-fA-F]*\d)(?=[0-9a-fA-F]*[a-fA-F])[0-9a-fA-F]{7,}\b", "<HEX>", s)
    s = re.sub(r"\d+(?:\.\d+)*", "<N>", s)
    s = re.sub(r"\s+", " ", s).strip()
    return s[:80]

PREFIX_WORDS = {"sudo", "env", "time", "nohup", "command", "exec"}
ARG_TAKING = {"ls", "cat", "echo", "printf", "cd", "rm", "rmdir", "mkdir", "cp", "mv", "ln", "touch",
              "chmod", "chown", "grep", "rg", "egrep", "fgrep", "find", "fd", "sed", "awk", "head", "tail",
              "wc", "sort", "uniq", "cut", "tr", "xargs", "test", "sleep", "which", "type", "open",
              "curl", "wget", "ssh", "scp", "rsync", "bash", "sh", "zsh", "source", "export", "python",
              "python3", "node", "deno", "ruby", "perl", "diff", "file", "stat", "du", "df", "tee",
              "kill", "pkill", "killall", "ps", "jq", "less", "more", "man", "tar", "zip", "unzip",
              "osascript", "say", "date", "read", "eval"}

def cmd_head(cmd):
    if not isinstance(cmd, str) or not cmd.strip():
        return ""
    s = cmd.strip()
    for _ in range(5):
        m = re.match(r"cd\s+(?:\"[^\"]*\"|'[^']*'|\S+)\s*(?:&&|;)\s*", s)
        if not m:
            break
        s = s[m.end():]
    words = s.split()
    while words:
        w = words[0]
        if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*=\S*", w) or w in PREFIX_WORDS:
            words.pop(0); continue
        if w == "timeout":
            words.pop(0)
            if words and re.fullmatch(r"[0-9.]+[smhd]?", words[0]):
                words.pop(0)
            continue
        break
    if not words:
        return ""
    w1 = words[0].lstrip("({").strip("\"'")
    w1 = os.path.basename(w1) or w1
    if len(words) > 1 and w1 not in ARG_TAKING and re.fullmatch(r"[a-z][a-z0-9-]*", words[1]):
        return w1 + " " + words[1]
    return w1

def clip(s, n):
    s = re.sub(r"\s*\n\s*", " ⏎ ", s.strip())
    s = re.sub(r"[ \t]+", " ", s)
    return s if len(s) <= n else s[:n - 1] + "…"

bad_json = 0
bad_fields = 0
tool_rows = 0
groups = {}
CATS = ("no-real-path", "criteria-fail", "test-fail", "out-of-scope", "uncommitted", "false-claim", "other")
verdicts = []      # (verdict, session) for this project within the window
proj_issues = []   # issues for this project within the window
all_issues = []    # issues for all projects within the window

with open(log, "r", encoding="utf-8", errors="replace") as f:
    for raw in f:
        if not raw.strip():
            continue
        try:
            rec = json.loads(raw)
        except ValueError:
            bad_json += 1
            continue
        if not isinstance(rec, dict):
            bad_json += 1
            continue
        if rec.get("type") == "verdict":
            ts = parse_ts(rec.get("ts"))
            sess, cwd = rec.get("session"), rec.get("cwd")
            if ts is None or not isinstance(sess, str) or not sess or not isinstance(cwd, str) or not cwd:
                bad_fields += 1
                continue
            if ts < cutoff:
                continue
            impl = rec.get("implementer") if isinstance(rec.get("implementer"), str) and rec.get("implementer") else None
            vd = str(rec.get("verdict") or "UNKNOWN")
            issues = rec.get("issues") if isinstance(rec.get("issues"), list) else []
            v_issues = []
            for it in issues:
                if not isinstance(it, dict):
                    continue
                cat = it.get("cat") if it.get("cat") in CATS else "other"
                text = it.get("text") if isinstance(it.get("text"), str) else ""
                v_issues.append({"ts": ts, "session": sess, "verdict": vd, "impl": impl, "cat": cat, "text": text})
            all_issues.extend(v_issues)
            if in_project(cwd):
                verdicts.append((vd, sess))
                proj_issues.extend(v_issues)
            continue
        if rec.get("type") != "tool":
            continue
        ts = parse_ts(rec.get("ts"))
        sess, cwd = rec.get("session"), rec.get("cwd")
        if ts is None or not isinstance(sess, str) or not sess or not isinstance(cwd, str) or not cwd:
            bad_fields += 1
            continue
        if ts < cutoff or not in_project(cwd):
            continue
        tool_rows += 1
        tool = str(rec.get("tool") or "?")
        kind = str(rec.get("kind") or "?")
        err = rec.get("error") if isinstance(rec.get("error"), str) else ""
        cmd = rec.get("command") if isinstance(rec.get("command"), str) else ""
        head = cmd_head(cmd) if tool == "Bash" else ""
        fl = first_line(err)
        key = (tool, kind, head, normalize(fl))
        g = groups.setdefault(key, [])
        g.append({"ts": ts, "session": sess, "account": rec.get("account"),
                  "subagent": rec.get("subagent") is True, "agentId": rec.get("agentId"),
                  "cmd": cmd, "err": fl})

def report_skips():
    if bad_json or bad_fields:
        parts = []
        if bad_json:
            parts.append("%d non-JSON rows" % bad_json)
        if bad_fields:
            parts.append("%d tool/verdict rows missing ts/session/cwd or with unparseable ts" % bad_fields)
        print("(skipped bad rows: %s)" % "; ".join(parts))

hits = []
for key, rows in groups.items():
    sessions = {r["session"] for r in rows}
    if len(sessions) >= 2:
        last = max(r["ts"] for r in rows)
        hits.append((-len(sessions), -len(rows), -last.timestamp(), key, rows, sessions))
hits.sort(key=lambda h: (h[0], h[1], h[2], h[3]))

window = "last %d days (since %s UTC)" % (days, cutoff.strftime("%Y-%m-%d %H:%M"))
print("==================================================")
print(" distill signals report (cross-session recurrence leads, not verdicts)")
print(" root: %s" % " | ".join(sorted(roots)))
print(" log : %s" % log)
print(" window: %s" % window)
print("==================================================")

if not hits:
    print("(no tool failure recurs across >=2 sessions; this project in window: %d tool rows, %d sessions, %d groups)"
          % (tool_rows, len({r["session"] for rs in groups.values() for r in rs}), len(groups)))
else:
    print("groups: %d (only groups seen in >=2 distinct sessions)" % len(hits))
for n, (_, _, _, key, rows, sessions) in enumerate(hits, 1):
    tool, kind, head, sig = key
    rows = sorted(rows, key=lambda r: r["ts"])
    first, last = rows[0]["ts"], rows[-1]["ts"]
    sub = sum(1 for r in rows if r["subagent"])
    title = "%s · %s" % (tool, kind) + (" · $ %s" % head if head else "")
    print()
    print("[%d] %s" % (n, title))
    print("    signature: %s" % (sig or "(no error text)"))
    print("    count %d · sessions %d · %s ~ %s%s" % (len(rows), len(sessions), first.strftime("%Y-%m-%d"),
          last.strftime("%Y-%m-%d"), (" · subagent %d" % sub) if sub else ""))
    latest = {}
    for r in rows:
        latest[r["session"]] = r          # rows are sorted by time asc, so this keeps the latest row per session
    samples = sorted(latest.values(), key=lambda r: (r["ts"], r["session"]), reverse=True)[:3]
    for r in samples:
        who = r["session"][:8]
        if r["account"]:
            who += " " + str(r["account"])
        if r["subagent"]:
            who += " subagent" + ((" " + str(r["agentId"])) if r["agentId"] else "")
        text = ("$ " + clip(r["cmd"], 60) + " → " if r["cmd"] else "") + clip(r["err"], 80)
        print("    - %s %s | %s" % (r["ts"].strftime("%Y-%m-%d"), who, text))

if hits:
    print()

def cat_stats(issues):
    out = {}
    for r in issues:
        out.setdefault(r["cat"], []).append(r)
    return out

print("---------------- verifier leads ----------------")
if not verdicts:
    print("(no verifier verdicts for this project in the window)")
else:
    vc = {}
    for vd, _ in verdicts:
        vc[vd] = vc.get(vd, 0) + 1
    order = ["PASS", "PASS-WITH-NOTES", "FAIL", "UNKNOWN"]
    keys = [k for k in order if k in vc] + sorted(k for k in vc if k not in order)
    print("verdicts %d (%s) · sessions %d" % (len(verdicts), " · ".join("%s %d" % (k, vc[k]) for k in keys),
          len({s for _, s in verdicts})))
    cs = cat_stats(proj_issues)
    vhits = sorted(cs.items(), key=lambda kv: (-len({r["session"] for r in kv[1]}), -len(kv[1]), kv[0]))
    if not vhits:
        print("(no issues in this project's verdicts)")
    for n, (cat, rows) in enumerate(vhits, 1):
        rows = sorted(rows, key=lambda r: r["ts"])
        sessions = {r["session"] for r in rows}
        mark = " ★ recurs across sessions" if len(sessions) >= 2 else ""
        print()
        print("[V%d] %s%s" % (n, cat, mark))
        imp = {}
        for r in rows:
            if r["impl"]:
                imp[r["impl"]] = imp.get(r["impl"], 0) + 1
        imp_s = (" · implementers: " + " · ".join("%s %d" % (k, imp[k]) for k in sorted(imp, key=lambda k: (-imp[k], k)))) if imp else ""
        print("    rows %d · sessions %d · %s ~ %s%s" % (len(rows), len(sessions), rows[0]["ts"].strftime("%Y-%m-%d"),
              rows[-1]["ts"].strftime("%Y-%m-%d"), imp_s))
        latest = {}
        for r in rows:
            latest[r["session"]] = r
        for r in sorted(latest.values(), key=lambda r: (r["ts"], r["session"]), reverse=True)[:3]:
            print("    - %s %s %s | %s" % (r["ts"].strftime("%Y-%m-%d"), r["session"][:8], r["verdict"], clip(r["text"], 100)))
    print()
acs = cat_stats(all_issues)
if acs:
    items = sorted(acs.items(), key=lambda kv: (-len({r["session"] for r in kv[1]}), -len(kv[1]), kv[0]))
    print("all projects (not filtered by project): " + " · ".join("%s %d rows/%d sessions" % (c, len(rs), len({r["session"] for r in rs}))
          for c, rs in items))
print()
report_skips()
PY
