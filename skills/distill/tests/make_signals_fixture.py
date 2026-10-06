#!/usr/bin/env python3
"""生成 signals.sh 的回归 fixture(时间戳相对当前时间,不会随日期过期)。

    python3 make_signals_fixture.py <OUT.jsonl> <PROJECT_ROOT>

然后:TURN_SIGNALS_PATH=<OUT.jsonl> bash ../scripts/signals.sh <PROJECT_ROOT>
期望结果见 tests.md「signals.sh 回归」。只写 OUT,不碰真实日志。
"""
import json, sys
from datetime import datetime, timedelta, timezone

out, root = sys.argv[1], sys.argv[2].rstrip("/")
now = datetime.now(timezone.utc)
S = ["%d111aaaa-0000-4000-8000-00000000000%d" % (i, i) for i in range(10)]   # 前 8 位各不相同

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
# A. 同类 Bash 失败跨 3 个 session(S1 两次、S3 在子目录且来自 subagent、S2 带 cd 前缀)→ 应输出,会话 3 次数 4
lines.append(tool(S[1], 2, root, "Bash", "error", 'Exit code 2\n"/nonexistent-a": No such file or directory (os error 2)', "ls /nonexistent-a"))
lines.append(tool(S[1], 2, root, "Bash", "error", 'Exit code 2\n"/tmp/zz-9": No such file or directory (os error 2)', "ls /tmp/zz-9", minute=5))
lines.append(tool(S[2], 5, root, "Bash", "error", 'Exit code 2\n"./build/out": No such file or directory (os error 2)', "cd /Users/x/proj && ls ./build/out"))
lines.append(tool(S[3], 1, root + "/docs", "Bash", "error", 'Exit code 2\n"/var/x 77": No such file or directory (os error 2)', "ls '/var/x 77'",
                  subagent=True, agentId="a163a201c35e1517e"))
# B. 同类失败只在 1 个 session 重复多次 → 不应输出
for k in range(4):
    lines.append(tool(S[4], 3, root, "Bash", "error", "Exit code 1\nerror: failed to push some refs to 'origin%d'" % k, "git push origin main", minute=k))
# C. 别的项目的行(同 A 的错误,跨 2 个 session)→ 不应输出
lines.append(tool(S[5], 2, "/Users/x/other", "Bash", "error", 'Exit code 2\n"/q": No such file or directory (os error 2)', "ls /q"))
lines.append(tool(S[6], 2, "/Users/x/other", "Bash", "error", 'Exit code 2\n"/r": No such file or directory (os error 2)', "ls /r"))
# D. 前缀相似的另一个项目路径(root-bar),跨 2 个 session 的独立错误 → 不应输出
lines.append(tool(S[7], 2, root + "-bar", "Bash", "error", "Exit code 1\nERR_PNPM_NO_SCRIPT Missing script: build", "pnpm build"))
lines.append(tool(S[8], 2, root + "-bar/sub", "Bash", "error", "Exit code 1\nERR_PNPM_NO_SCRIPT Missing script: build", "pnpm build"))
# E. 超出时间窗(35/40 天前,跨 2 个 session)→ 默认 30 天不输出;--days 60 时输出
lines.append(tool(S[1], 40, root, "Read", "error", "<tool_use_error>File does not exist. Note: your current working directory is /a/b.</tool_use_error>"))
lines.append(tool(S[2], 35, root, "Read", "error", "<tool_use_error>File does not exist. Note: your current working directory is /c/d.</tool_use_error>"))
# F. 坏 JSON
lines.append('{"type":"tool","kind":"error", this is not json')
# G. refused 跨 2 个 session → 应输出
lines.append(tool(S[2], 4, root, "Bash", "refused", "Permission to use Bash with command rm -rf /tmp/build-123 has been denied.", "rm -rf /tmp/build-123"))
lines.append(tool(S[3], 1, root, "Bash", "refused", "Permission to use Bash with command rm -rf ./dist has been denied.", "rm -rf ./dist", minute=3))
# H. 含换行和中文的 error,引号内容不同、跨 2 个 session → 应合成一组输出
lines.append(tool(S[1], 6, root, "Edit", "error", "<tool_use_error>找不到要替换的字符串「旧文本 1」\n第二行:\"说明\"</tool_use_error>"))
lines.append(tool(S[3], 3, root, "Edit", "error", "<tool_use_error>找不到要替换的字符串「另一段 22」\n别的说明</tool_use_error>"))
# L. Bash 缺 command 字段的 interrupted,跨 2 个 session → 应输出(无命令头)
lines.append(tool(S[1], 1, root, "Bash", "interrupted", "Interrupted by user"))
lines.append(tool(S[2], 1, root, "Bash", "interrupted", "Interrupted by user"))
# J. turn / interrupt 行 → 忽略
lines.append(json.dumps({"type": "turn", "ts": ts(1), "session": S[1], "cwd": root, "reason": "answer", "durationMs": 10, "tools": 1, "failures": 1}))
lines.append(json.dumps({"type": "interrupt", "ts": ts(1), "session": S[2], "cwd": root, "durationMs": 9, "tools": 1}))
# K. tool 行缺 session → 计入跳过
lines.append(json.dumps({"type": "tool", "kind": "error", "ts": ts(1), "cwd": root, "tool": "Bash", "error": "x"}))
# L. verdict 行(verifier 结论)
def verdict(sess, days_ago, cwd, vd, issues, impl=None, minute=0):
    r = {"type": "verdict", "ts": ts(days_ago, minute), "session": sess, "cwd": cwd, "account": "claude-2",
         "agentId": "a1b2c3d4e5f6", "verdict": vd, "issues": issues}
    if impl:
        r["implementer"] = impl
    return json.dumps(r, ensure_ascii=False)
# L1. no-real-path 跨 2 个 session(S1 两条:带 implementer;S2 一条在子目录、不带 implementer)→ ★,条数 3 · 会话 2
lines.append(verdict(S[1], 3, root, "FAIL", [{"cat": "no-real-path", "text": "只跑了 mock provider"},
                                             {"cat": "test-fail", "text": "npm test 2 failed"}], "opus-implementer"))
lines.append(verdict(S[1], 2, root, "FAIL", [{"cat": "no-real-path", "text": "未在浏览器走通"}], "opus-implementer"))
lines.append(verdict(S[2], 1, root + "/docs", "PASS-WITH-NOTES", [{"cat": "no-real-path", "text": "只读了代码"}]))
# L2. PASS 且空 issues;非枚举 cat → other;结构不对的元素跳过;issues 非数组
lines.append(verdict(S[3], 1, root, "PASS", [], "sonnet-implementer"))
lines.append(verdict(S[3], 1, root, "FAIL", [{"cat": "made-up", "text": "奇怪类别"}, "not-a-dict", 7], "sonnet-implementer", minute=5))
lines.append(json.dumps({"type": "verdict", "ts": ts(1), "session": S[4], "cwd": root, "verdict": "UNKNOWN", "issues": "bad"}))
# L3. 窗口外旧行(40 天前)→ 不计
lines.append(verdict(S[2], 40, root, "FAIL", [{"cat": "uncommitted", "text": "旧"}]))
# L4. 其他项目 cwd → 只进「全部项目合计」
lines.append(verdict(S[5], 2, "/Users/x/other", "FAIL", [{"cat": "no-real-path", "text": "别处 mock"}]))
lines.append(verdict(S[6], 2, "/Users/x/other", "FAIL", [{"cat": "false-claim", "text": "自称已测"}]))
# L5. 缺 ts 的坏 verdict 行 → 计入跳过
lines.append(json.dumps({"type": "verdict", "session": S[1], "cwd": root, "verdict": "FAIL", "issues": []}))
# 空行 → 忽略
lines.append("")

with open(out, "w", encoding="utf-8") as f:
    f.write("\n".join(lines) + "\n")
