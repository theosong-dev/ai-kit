#!/usr/bin/env bash
# signals.sh —— /distill 的跨会话重复线索收集器(读 turn-signals 信号日志)。
#
#     bash signals.sh <PROJECT_ROOT> [--days N]      # 默认最近 30 天
#
# 日志:默认 ~/.local/state/claude-insight/turn-signals.jsonl,可用环境变量 TURN_SIGNALS_PATH 覆盖
# (格式见 ai-kit 仓库 mods/README.md)。只读,不写日志。
#
# 做什么(全部确定性完成,输出是"线索"不是"判定"):
#   1. 只取 type=="tool" 的行;cwd 等于项目根或在其下(按路径段比较,/a/foo 不匹配 /a/foo-bar);
#      ts(UTC ISO)不早于"现在 - N 天"。项目根先转绝对路径并去尾部斜杠,另外也接受其 realpath。
#   2. 按签名分组:tool + kind + Bash 的命令头 + 归一化后的错误首行。
#   3. 只输出出现在 ≥2 个不同 session 的组(同一 session 重复多少次都只算 1),
#      按 session 数降序、总次数降序、最近时间降序、签名字典序排。
#      每组:总次数、session 数、首末日期、最多 3 条样例(每个 session 至多 1 条,取最近的)。
#
# 错误首行:先去掉 <tool_use_error> 这类尖括号标签,跳过空行和 Bash 的 "Exit code N" 行,取第一条有内容的行;都没有就用 "Exit code N" 本身。
# 归一化(按顺序):
#   - 引号内容 → … :"x" 'x' `x` “x” ‘x’ 「x」 『x』 (同一行内配对)
#   - URL → <URL>;uuid → <UUID>
#   - 路径 → <PATH>:以 / ~/ ./ ../ 开头的串,及含 / 的相对路径串(如 src/a.ts)
#   - 含数字的 ≥7 位十六进制串(commit、agentId 等)→ <HEX>;其余数字 → <N>
#   - 压缩空白,截前 80 字符(日志本身把 error 截在 200 字符,截短可减少因截断点不同造成的误分)
# Bash 命令头:去掉开头的 `cd X &&` / `cd X;`、环境变量赋值、sudo/env/time/nohup/command/timeout N 前缀,
#   取第一个词(路径取 basename);第二个词是纯小写子命令形式([a-z][a-z0-9-]*)且第一个词不在
#   "后面跟参数而非子命令"的名单(ls cat echo ssh bash python3 …)里时,一并计入,如 `git push`、`npm run`。
# 已知局限:
#   - 误并:不同文件 / 不同引号内容的同类错误会落进一组(这正是目的);错误首行只有 "Exit code N"
#     时,同一命令头的不同失败会合在一起。
#   - 误分:同一类错误措辞随参数变化而结构不同(如单复数、附带的提示句不同)时会分成多组;
#     名单外的 CLI 第二个词若是普通参数(如 `foo bar` vs `foo baz`)也会分组。
#   - 含 / 的普通词(and/or)会被当成路径抹掉;英文撇号(doesn't … it's)会被当成一对单引号抹掉中间内容。
#   4. 「verifier 验收线索」节:取 type=="verdict" 的行(verifier 结论,时间窗口与项目过滤同上),
#      先打结论分布(各 verdict 条数、会话数),再按 issues[].cat 分组列出所有有问题的类别,
#      按 会话数降序、条数降序、cat 字典序 排;每组:条数、会话数、首末日期、按 implementer 计数、
#      最多 3 条样例(每个 session 至多 1 条,取最近的)。会话数 ≥2 的组标 ★(distill 进入门槛)。
#      cat 不在枚举内归 other;issues 非数组 / 元素非对象跳过。末行「全部项目合计」不过滤项目。
#
# 坏行(非 JSON 或非对象)跳过并在末尾报数;tool/verdict 行缺 ts/session/cwd 或 ts 无法解析也跳过并报数。
# 日志不存在、为空、无符合条件的组、找不到 python3:各打印一行说明,退出码 0。
# 依赖:python3(标准库)。兼容 macOS 自带 bash 3.2。

set -u

if ! command -v python3 >/dev/null 2>&1; then
  echo "(未找到 python3,跳过信号日志分析)"
  exit 0
fi

LOG="${TURN_SIGNALS_PATH:-$HOME/.local/state/claude-insight/turn-signals.jsonl}"

PYTHONIOENCODING=utf-8 python3 - "$LOG" "$@" <<'PY'
import json, os, re, sys
from datetime import datetime, timedelta, timezone

def usage(msg):
    sys.stderr.write("signals.sh: %s\n用法: bash signals.sh <PROJECT_ROOT> [--days N]\n" % msg)
    sys.exit(2)

log = sys.argv[1]
args = sys.argv[2:]
root_arg, days = None, 30
i = 0
while i < len(args):
    a = args[i]
    if a == "--days":
        if i + 1 >= len(args):
            usage("--days 缺少参数")
        v = args[i + 1]
        if not re.fullmatch(r"[0-9]+", v) or int(v) <= 0:
            usage("--days 需要正整数,收到 %r" % v)
        days = min(int(v), 36500); i += 2; continue
    if a.startswith("--days="):
        v = a.split("=", 1)[1]
        if not re.fullmatch(r"[0-9]+", v) or int(v) <= 0:
            usage("--days 需要正整数,收到 %r" % v)
        days = min(int(v), 36500); i += 1; continue
    if root_arg is None:
        root_arg = a; i += 1; continue
    usage("多余参数 %r" % a)
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
    print("(无信号日志:%s 不存在,跳过)" % log)
    sys.exit(0)
if os.path.getsize(log) == 0:
    print("(信号日志为空:%s,跳过)" % log)
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
    s = s[:2000]  # 写入端已截到 200 字符;这里再兜一道,防手工或损坏日志的超长行拖慢正则
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
verdicts = []      # 本项目窗口内 (verdict, session)
proj_issues = []   # 本项目窗口内 issue
all_issues = []    # 全部项目窗口内 issue

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
            parts.append("非 JSON %d 行" % bad_json)
        if bad_fields:
            parts.append("tool/verdict 行缺 ts/session/cwd 或 ts 无法解析 %d 行" % bad_fields)
        print("(跳过坏行:%s)" % ",".join(parts))

hits = []
for key, rows in groups.items():
    sessions = {r["session"] for r in rows}
    if len(sessions) >= 2:
        last = max(r["ts"] for r in rows)
        hits.append((-len(sessions), -len(rows), -last.timestamp(), key, rows, sessions))
hits.sort(key=lambda h: (h[0], h[1], h[2], h[3]))

window = "最近 %d 天(UTC %s 起)" % (days, cutoff.strftime("%Y-%m-%d %H:%M"))
print("==================================================")
print(" distill signals report(跨会话重复线索,非判定)")
print(" root: %s" % " | ".join(sorted(roots)))
print(" log : %s" % log)
print(" 窗口: %s" % window)
print("==================================================")

if not hits:
    print("(无跨 ≥2 个会话的同类工具失败;窗口内本项目 tool 行 %d 条,%d 个会话,%d 组)"
          % (tool_rows, len({r["session"] for rs in groups.values() for r in rs}), len(groups)))
else:
    print("groups: %d(仅列出现在 ≥2 个不同 session 的组)" % len(hits))
for n, (_, _, _, key, rows, sessions) in enumerate(hits, 1):
    tool, kind, head, sig = key
    rows = sorted(rows, key=lambda r: r["ts"])
    first, last = rows[0]["ts"], rows[-1]["ts"]
    sub = sum(1 for r in rows if r["subagent"])
    title = "%s · %s" % (tool, kind) + (" · $ %s" % head if head else "")
    print()
    print("[%d] %s" % (n, title))
    print("    签名: %s" % (sig or "(无错误文本)"))
    print("    次数 %d · 会话 %d · %s ~ %s%s" % (len(rows), len(sessions), first.strftime("%Y-%m-%d"),
          last.strftime("%Y-%m-%d"), (" · 其中 subagent %d 次" % sub) if sub else ""))
    latest = {}
    for r in rows:
        latest[r["session"]] = r          # rows 已按时间升序,留下每个 session 最近一条
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

print("---------------- verifier 验收线索 ----------------")
if not verdicts:
    print("(窗口内本项目无 verifier 结论记录)")
else:
    vc = {}
    for vd, _ in verdicts:
        vc[vd] = vc.get(vd, 0) + 1
    order = ["PASS", "PASS-WITH-NOTES", "FAIL", "UNKNOWN"]
    keys = [k for k in order if k in vc] + sorted(k for k in vc if k not in order)
    print("结论 %d 条(%s)· 会话 %d" % (len(verdicts), " · ".join("%s %d" % (k, vc[k]) for k in keys),
          len({s for _, s in verdicts})))
    cs = cat_stats(proj_issues)
    vhits = sorted(cs.items(), key=lambda kv: (-len({r["session"] for r in kv[1]}), -len(kv[1]), kv[0]))
    if not vhits:
        print("(本项目结论中无问题条目)")
    for n, (cat, rows) in enumerate(vhits, 1):
        rows = sorted(rows, key=lambda r: r["ts"])
        sessions = {r["session"] for r in rows}
        mark = " ★ 跨会话重复" if len(sessions) >= 2 else ""
        print()
        print("[V%d] %s%s" % (n, cat, mark))
        imp = {}
        for r in rows:
            if r["impl"]:
                imp[r["impl"]] = imp.get(r["impl"], 0) + 1
        imp_s = (" · 实施者: " + " · ".join("%s %d" % (k, imp[k]) for k in sorted(imp, key=lambda k: (-imp[k], k)))) if imp else ""
        print("    条数 %d · 会话 %d · %s ~ %s%s" % (len(rows), len(sessions), rows[0]["ts"].strftime("%Y-%m-%d"),
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
    print("全部项目合计(不过滤项目):" + " · ".join("%s %d条/%d会话" % (c, len(rs), len({r["session"] for r in rs}))
          for c, rs in items))
print()
report_skips()
PY
