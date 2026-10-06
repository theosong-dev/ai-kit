# Claude Code mods 范例

两个可运行的 mod（以 plugin 形式打包、跑在 Claude Code 会话里的 JS 钩子模块），基于 Claude Code 2.1.288 的 function hooks API 编写，纯 `.mjs`，没有 npm 依赖。只是范例，装不装由你决定。

| mod | 做什么 | 显示位置 |
| --- | --- | --- |
| `token-weather` | 上下文占用的「天气预报」：图标 + 百分比 + tokens/window；宽度 ≥60 列时再加最近 12 轮的 sparkline 和上一轮增减。阈值 25/50/75/90 分五档 | 输入框上方（`AbovePrompt`） |
| `turn-signals` | 往一个跨会话、跨账号的 JSONL 文件里追加精简信号：工具失败或被拒绝、每轮摘要、用户中断。方便以后扫「同一个错在多个会话里重复出现」 | 不显示，只写文件 |

## 试用（只对本次会话生效，不安装）

```bash
claude --plugin-dir ./mods          # 整个文件夹:逐个加载子目录里的 mod
claude --plugin-dir ./mods/token-weather   # 或只加载一个
```

日常全局使用(两个账号共用本仓这一份源码,不安装):在 `~/.zshrc` 的 `claude` / `claude-2` alias 上加 `--plugin-dir <ai-kit 路径>/mods`。绕过 alias 启动的会话(如桌面端)不会加载。

第一次加载时 Claude Code 会在每个 mod 下生成 `.claude-plugin/types/`（API 类型声明，已在 `.gitignore` 里）和 `tsconfig.json`。

检查与测试：

```bash
claude plugin validate ./mods/token-weather    # 单个 mod
claude plugin validate ./mods                  # marketplace
claude plugin test ./mods/turn-signals
```

## 安装

`mods/` 本身是一个本地 marketplace（`mods/.claude-plugin/marketplace.json`，名为 `claude-insight-mods`）：

```bash
claude plugin marketplace add <ai-kit 路径>/mods
claude plugin install token-weather@claude-insight-mods
```

plugin 装在当前账号的配置目录里。两个账号（`~/.claude` 和 `~/.claude-2`）要分别装一次：第二个账号用 `CLAUDE_CONFIG_DIR=~/.claude-2 claude plugin ...` 再跑一遍。

## turn-signals 的记录格式

默认写到 `~/.local/state/claude-insight/turn-signals.jsonl`，两个账号共用这一个文件，目录不存在会自动创建。用环境变量 `TURN_SIGNALS_PATH` 可以换路径（测试就是这么做的）。每条一行 JSON：

```json
{"type":"tool","kind":"error","ts":"…","session":"…","cwd":"…","account":"claude-2","tool":"Bash","subagent":false,"error":"Exit code 2\n…","command":"ls /nonexistent-dir-xyz"}
{"type":"turn","ts":"…","session":"…","cwd":"…","account":"claude-2","reason":"answer","durationMs":6134,"tools":1,"failures":1}
{"type":"interrupt","ts":"…","session":"…","cwd":"…","account":"claude-2","durationMs":900,"tools":1}
{"type":"verdict","ts":"…","session":"…","cwd":"…","account":"claude-2","agentId":"…","implementer":"opus-implementer","verdict":"FAIL","issues":[{"cat":"no-real-path","text":"…"}]}
```

- `kind`：`error` 表示工具跑了但报错，`interrupted` 表示运行中被打断，`refused` 表示根本没跑（被权限规则或模式拒绝、用户点了拒绝、PreToolUse hook deny）。`error` 截前 200 字符，Bash 另记 `command` 前 120 字符；subagent 里的调用带 `subagent: true` 和 `agentId`。
- `turn`：只给主循环的轮记摘要。`reason` 是 `answer` / `aborted` / `refusal` / `error`，`tools` 和 `failures` 只统计主循环自己的工具调用。
- `interrupt`：轮以 `reason: "aborted"` 结束（用户按 Esc 中断）时多记一条。
- `verdict`：类型名（最后一段）是 `verifier` 的 subagent 每结束一轮记一条，其他 subagent 不记。`verdict` 取回答里**最后一处** `VERDICT: PASS-WITH-NOTES|PASS|FAIL`（容忍 `**`、反引号），没有就是 `UNKNOWN`。`issues` 取形如 `- [slug] 正文` 的行（列表前缀和 `**` 可有可无），slug 不在 `no-real-path` `criteria-fail` `test-fail` `out-of-scope` `uncommitted` `false-claim` `other` 里的记为 `other`；`[x]`、`[N]`、markdown 链接不算；正文截前 160 字符，最多 12 条。`implementer` 是本会话里在这个 verifier 之前启动的、最近的一个非 verifier subagent 的类型名，没有就不带这个字段。
- 写文件用 `/bin/sh` 做 `mkdir -p` 加 `cat >>`（O_APPEND），两个会话同时写也不会互相覆盖。写失败只记到 debug 日志，不影响会话。钩子都把事件原样 `next(e)` 传下去。

## 已知限制

- **两个 mod 不能同时画 `AbovePrompt`**：这块区域是一条钩子链，最外层的插件一旦返回自己的 tree，链就结束了。用两个探针 plugin 在真实交互会话里实测过：只显示先加载的那个（排在前面的 `--plugin-dir`），换顺序就换成另一个。曾做过的 `usage-meter` 因此改用 `$.ui.status` 状态行，后来发现它和已有的 `statusline-command.sh` 内容重复、且插件状态行固定带 `⚠ <插件名>:` 前缀，已删除（2026-10-03）。
- **账号标识是推断出来的**：plugin API 里没有账号或套餐信息，所以取 `CLAUDE_CONFIG_DIR` 最后一段并去掉开头的点（`~/.claude-2` → `claude-2`）；没设这个变量就是默认的 `~/.claude` → `claude`。不显示套餐（max/pro）。
- `token-weather`：新会话还没发请求时显示 `0 / window`（官方文章原样行为）；拿不到 `context.window` 时不记读数；subagent 的轮不计。
- `turn-signals`：
  - 区分「失败」和「被拒绝」是靠观察推出来的：实测工具真跑了又失败时，引擎会先发 `classic.PostToolUseFailure` 再让 `tool.call` 返回 `isError`；被权限拒绝时 `tool.call` 也返回 `isError`，但不发 `PostToolUseFailure`。所以 `refused` 里分不出到底是哪种拒绝（权限规则/模式、用户点拒绝、hook deny）。另外，输入校验失败这类没执行就报错的情况，推测也会落进 `refused`，没有验证。用户在交互界面里点「拒绝」这一条也没有实测。
  - 没有「哪条规则拒绝的」：`tool.check` 只在弹窗决定之前触发，看不到用户最后的选择，所以没用它。
  - 中断只认整轮以 `aborted` 结束的情况。单个工具被打断记作 `kind: "interrupted"`。
  - 非交互模式（`claude -p`）下照常工作，已实测：失败记录、拒绝记录和轮摘要都会写。`-p` 下 UI 不显示（`$.ui.status` 在 headless 会话里只进 debug 日志），对 `turn-signals` 没影响。
  - `verdict` 行：`$.agent.list()` 不含 Agent 工具派出的 subagent（实测返回空数组），所以类型名改由 `classic.SubagentStart` / `classic.SubagentStop` 的 `agent_type` 记进 `$.state`（最多留 50 条）；回答文本取 subagent 的 `turn.complete` 的 `answer`（`SubagentStop` 的 `last_assistant_message` 实测为空）。2026-10-06 实测：`claude -p` 下 verifier 报 PASS、报 FAIL 带 `[criteria-fail]` 各写出一行，派 `general-purpose` 不写，先派 `general-purpose` 再派 verifier 时带 `"implementer":"general-purpose"`；交互会话里后台运行的 verifier 也照常写。`implementer` 不区分是谁启动的，mod 加载之前启动的 subagent 不计入。`VERDICT:` 的匹配没有词边界（`VERDICT: PASSED` 会记成 PASS）。`answer` 不是字符串的情况在代码里按空串处理，但测试框架会在钩子之前拦掉这种输入，所以没测到。
- 热重载：每次重载都会重跑 `register` 和 `session.start`。需要持久的数据（读数历史、每轮计数）都放在 `$.state`；`turn-signals` 在 `session.start` 里什么都不写，所以重载不会产生重复行。
