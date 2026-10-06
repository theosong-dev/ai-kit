#!/usr/bin/env python3
"""Generate the regression fixture for signals.sh (timestamps are relative to now, so it never goes stale).

    python3 make_signals_fixture.py <OUT.jsonl> <PROJECT_ROOT>

Then: TURN_SIGNALS_PATH=<OUT.jsonl> bash ../scripts/signals.sh <PROJECT_ROOT>
Expected results: see "signals.sh regression" in tests.md. Writes only OUT; never touches the real log.
"""
import json, sys
from datetime import datetime, timedelta, timezone

out, root = sys.argv[1], sys.argv[2].rstrip("/")
now = datetime.now(timezone.utc)
S = ["%d111aaaa-0000-4000-8000-00000000000%d" % (i, i) for i in range(10)]   # first 8 chars all distinct

def ts(days_ago, minute=0):
    return (now - timedelta(days=days_ago, minutes=minute)).strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"

def tool(sess, days_ago, cwd, tool_name, kind, error, command=None, minute=0, **extra):
    r = {"type": "tool", "kind": kind, "ts": ts(days_ago, minute), "session": sess, "cwd": cwd,
         "account": "claude-2", "tool": tool_name, "subagent": False, "error": error}
    if command is not None:
        r["command"] = command
    r.update(extra)
    return json.dumps(r, ensure_ascii=False)

lines = []
# A. Same Bash failure across 3 sessions (S1 twice, S3 in a subdir from a subagent, S2 with a cd prefix) -> printed, sessions 3, count 4
lines.append(tool(S[1], 2, root, "Bash", "error", 'Exit code 2\n"/nonexistent-a": No such file or directory (os error 2)', "ls /nonexistent-a"))
lines.append(tool(S[1], 2, root, "Bash", "error", 'Exit code 2\n"/tmp/zz-9": No such file or directory (os error 2)', "ls /tmp/zz-9", minute=5))
lines.append(tool(S[2], 5, root, "Bash", "error", 'Exit code 2\n"./build/out": No such file or directory (os error 2)', "cd /Users/x/proj && ls ./build/out"))
lines.append(tool(S[3], 1, root + "/docs", "Bash", "error", 'Exit code 2\n"/var/x 77": No such file or directory (os error 2)', "ls '/var/x 77'",
                  subagent=True, agentId="a163a201c35e1517e"))
# B. Same failure repeated within only 1 session -> not printed
for k in range(4):
    lines.append(tool(S[4], 3, root, "Bash", "error", "Exit code 1\nerror: failed to push some refs to 'origin%d'" % k, "git push origin main", minute=k))
# C. Rows from another project (same error as A, across 2 sessions) -> not printed
lines.append(tool(S[5], 2, "/Users/x/other", "Bash", "error", 'Exit code 2\n"/q": No such file or directory (os error 2)', "ls /q"))
lines.append(tool(S[6], 2, "/Users/x/other", "Bash", "error", 'Exit code 2\n"/r": No such file or directory (os error 2)', "ls /r"))
# D. Another project path sharing the prefix (root-bar), separate error across 2 sessions -> not printed
lines.append(tool(S[7], 2, root + "-bar", "Bash", "error", "Exit code 1\nERR_PNPM_NO_SCRIPT Missing script: build", "pnpm build"))
lines.append(tool(S[8], 2, root + "-bar/sub", "Bash", "error", "Exit code 1\nERR_PNPM_NO_SCRIPT Missing script: build", "pnpm build"))
# E. Outside the window (35/40 days ago, across 2 sessions) -> not printed with the default 30 days; printed with --days 60
lines.append(tool(S[1], 40, root, "Read", "error", "<tool_use_error>File does not exist. Note: your current working directory is /a/b.</tool_use_error>"))
lines.append(tool(S[2], 35, root, "Read", "error", "<tool_use_error>File does not exist. Note: your current working directory is /c/d.</tool_use_error>"))
# F. Bad JSON
lines.append('{"type":"tool","kind":"error", this is not json')
# G. refused across 2 sessions -> printed
lines.append(tool(S[2], 4, root, "Bash", "refused", "Permission to use Bash with command rm -rf /tmp/build-123 has been denied.", "rm -rf /tmp/build-123"))
lines.append(tool(S[3], 1, root, "Bash", "refused", "Permission to use Bash with command rm -rf ./dist has been denied.", "rm -rf ./dist", minute=3))
# H. Errors with newlines and CJK text, different quoted content, across 2 sessions -> merged into one printed group
lines.append(tool(S[1], 6, root, "Edit", "error", "<tool_use_error>找不到要替换的字符串「旧文本 1」\n第二行:\"说明\"</tool_use_error>"))
lines.append(tool(S[3], 3, root, "Edit", "error", "<tool_use_error>找不到要替换的字符串「另一段 22」\n别的说明</tool_use_error>"))
# L. Bash interrupted rows without a command field, across 2 sessions -> printed (no command head)
lines.append(tool(S[1], 1, root, "Bash", "interrupted", "Interrupted by user"))
lines.append(tool(S[2], 1, root, "Bash", "interrupted", "Interrupted by user"))
# J. turn / interrupt rows -> ignored
lines.append(json.dumps({"type": "turn", "ts": ts(1), "session": S[1], "cwd": root, "reason": "answer", "durationMs": 10, "tools": 1, "failures": 1}))
lines.append(json.dumps({"type": "interrupt", "ts": ts(1), "session": S[2], "cwd": root, "durationMs": 9, "tools": 1}))
# K. tool row missing session -> counted as skipped
lines.append(json.dumps({"type": "tool", "kind": "error", "ts": ts(1), "cwd": root, "tool": "Bash", "error": "x"}))
# L. verdict rows (verifier conclusions)
def verdict(sess, days_ago, cwd, vd, issues, impl=None, minute=0):
    r = {"type": "verdict", "ts": ts(days_ago, minute), "session": sess, "cwd": cwd, "account": "claude-2",
         "agentId": "a1b2c3d4e5f6", "verdict": vd, "issues": issues}
    if impl:
        r["implementer"] = impl
    return json.dumps(r, ensure_ascii=False)
# L1. no-real-path across 2 sessions (S1 twice, with implementer; S2 once in a subdir, no implementer) -> ★, rows 3 · sessions 2
lines.append(verdict(S[1], 3, root, "FAIL", [{"cat": "no-real-path", "text": "只跑了 mock provider"},
                                             {"cat": "test-fail", "text": "npm test 2 failed"}], "opus-implementer"))
lines.append(verdict(S[1], 2, root, "FAIL", [{"cat": "no-real-path", "text": "未在浏览器走通"}], "opus-implementer"))
lines.append(verdict(S[2], 1, root + "/docs", "PASS-WITH-NOTES", [{"cat": "no-real-path", "text": "只读了代码"}]))
# L2. PASS with empty issues; unknown cat -> other; malformed elements skipped; non-array issues
lines.append(verdict(S[3], 1, root, "PASS", [], "sonnet-implementer"))
lines.append(verdict(S[3], 1, root, "FAIL", [{"cat": "made-up", "text": "奇怪类别"}, "not-a-dict", 7], "sonnet-implementer", minute=5))
lines.append(json.dumps({"type": "verdict", "ts": ts(1), "session": S[4], "cwd": root, "verdict": "UNKNOWN", "issues": "bad"}))
# L3. Old row outside the window (40 days ago) -> not counted
lines.append(verdict(S[2], 40, root, "FAIL", [{"cat": "uncommitted", "text": "旧"}]))
# L4. cwd in another project -> only in the "all projects" line
lines.append(verdict(S[5], 2, "/Users/x/other", "FAIL", [{"cat": "no-real-path", "text": "别处 mock"}]))
lines.append(verdict(S[6], 2, "/Users/x/other", "FAIL", [{"cat": "false-claim", "text": "自称已测"}]))
# L5. Bad verdict row missing ts -> counted as skipped
lines.append(json.dumps({"type": "verdict", "session": S[1], "cwd": root, "verdict": "FAIL", "issues": []}))
# Blank line -> ignored
lines.append("")

with open(out, "w", encoding="utf-8") as f:
    f.write("\n".join(lines) + "\n")
