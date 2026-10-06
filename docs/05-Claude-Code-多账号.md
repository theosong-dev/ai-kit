# Claude Code 多账号

目标：同一台 Mac 上并存两个 Claude 账号，会话、记忆、凭据、浏览器互不串。

以下结论在 macOS + Claude Code 2.1.274 上实际搭建验证过；未验证的点单列在最后。

## 结论

- 用 `CLAUDE_CONFIG_DIR` 给每个账号一个独立配置目录，用 alias 区分入口。这是官方文档(`env-vars` 页)给的做法。
- CLI 没有内置账号切换，只有 `/logout` + `/login`。在同一个配置目录里来回登录，会把历史、自动 memory、claude.ai 连接器混在一起，不推荐。
- Chrome 集成按 **claude.ai 账号**配对，不是按机器。第二个账号要用浏览器，就必须有第二个 Chrome profile。

## 目录结构

| 项 | 默认账号 | 第二账号 |
|---|---|---|
| 入口 | `claude` | `claude-2`(`~/.zshrc`：`alias claude-2="CLAUDE_CONFIG_DIR=$HOME/.claude-2 claude"`) |
| 配置目录 | `~/.claude` + `~/.claude.json` | `~/.claude-2`(`.claude.json` 在目录**里面**) |
| Keychain 条目 | `Claude Code-credentials` | `Claude Code-credentials-<后缀>`(按目录自动加后缀) |
| Chrome profile | `Default` | 另建一个(如 `Profile 3`) |

`~/.claude-2` 内部分三类：

- **软链接共享**(链接到 `~/.claude` 同名项)：`agents/`、`hooks/`、`CLAUDE.md`、状态行脚本；`skills/` 下逐个 skill 链接到真实目录。改一处两边生效。
- **不链接 `skills/synced`**：那是跟 claude.ai 账号绑定的同步目录。
- **`settings.json` 复制一份，不链接**：Claude Code 会写回它，可能把链接冲掉；两个账号的权限放行、MCP 也可能想分开设。hook 里写的绝对路径(如 `~/.claude/hooks/guard.sh`)不用改。
- **天然隔离、不要共享**：`.claude.json`(账号、用户级 MCP、项目信任)、`projects/`(会话 + 自动 memory)、`plugins/`、`history.jsonl`。

一个前提让这件事很便宜：如果 skills 正文和全局规则本来就放在宿主配置目录之外(比如 `~/.agents/skills`、`~/.ai/AGENTS.md`)，`~/.claude` 里多是软链接，第二个目录的复用成本就很低。共享资产不住在宿主配置目录里，这个布局在多账号场景下会再得到一次回报。

## 搭建步骤

1. 建目录与软链接、复制 `settings.json`、加 alias。
2. `CLAUDE_CONFIG_DIR=~/.claude-2 claude auth status`，确认 `configDirectory` 指向新目录且 `loggedIn: false`(没串到旧登录)。
3. 运行 `claude-2`，`/login` 第二个账号。
4. 验证并存：`security dump-keychain | grep '"svce"<blob>="Claude Code'` 出现两条；两边 `claude auth status` 都是 `loggedIn: true`，订阅类型各自正确。
5. 新目录下重装需要的 plugin(`settings.json` 写了启用，但 plugin 本体按配置目录存放)；claude.ai 连接器(Gmail / Drive / Notion 等)按需在新账号重新授权。

## Chrome

- 依据：文档说 API key / `setup-token` 登录时 Chrome 集成被关闭，因为「the browser extension can't authenticate with those credentials」；连接经云端桥接 `bridge.claudeusercontent.com`。实测也印证了：默认账号的会话里 `list_connected_browsers` 只看得到自己 profile 的扩展，看不到第二账号配对的那个。
- 做法：Chrome 头像 → 添加 → 不登录 Google 继续 → 命名并换主题色；在新窗口登录第二账号的 claude.ai，重装 Claude in Chrome 扩展(扩展按 profile 安装)；Cmd+Q 重启 Chrome；`claude-2 --chrome` 后在 `/chrome` 里 Select browser，按需设 "Enabled by default"。
- 对应 profile 的窗口没开，就等于该账号没有可连的浏览器，会报 "Browser extension is not connected"，不会退而用另一个 profile。命令行拉起指定 profile：

  ```bash
  open -na "Google Chrome" --args --profile-directory="Profile 3"   # claude-2
  open -na "Google Chrome" --args --profile-directory="Default"     # 默认账号
  ```

- native host 配置(`~/Library/Application Support/Google/Chrome/NativeMessagingHosts/com.anthropic.claude_code_browser_extension.json`)全机器只有一份，两个配置目录会轮流改写它的 `path`。两边包装脚本内容相同(`exec claude --chrome-native-host`)，互相覆盖不影响使用；某一边提示未连接时 `/chrome` → Reconnect extension。

## 隔离不到的部分

- `~/.zshrc` 里的 token、其他密钥文件、ssh 别名对两个账号同样可见。需要不同的 GitHub 身份时，要在入口处一并切换。
- 自动 memory 在配置目录的 `projects/` 下，换账号打开同一仓库看不到对方的 memory。要跨账号延续的内容写进仓库里(如 `.ai/`)。
- 桌面 App、claude.ai/code 网页各自独立登录，同一时间只能一个账号，不受 `CLAUDE_CONFIG_DIR` 影响。VS Code 扩展支持该变量(工作区 `terminal.integrated.env.osx`)。

## 放弃的方案

- 按工作目录自动切换账号(包一层 `claude()` 函数判断 `$PWD`)：选择只用两个 alias，显式、没有隐式状态。
- 两个账号共用一个 Chrome profile：按账号配对的机制下要么连不上，要么得在扩展里来回登录，而且 cookie 不隔离。

## 未验证

- 软链接的 `agents/`、`hooks/` 在 `claude-2` 会话里是否全部正常加载(使用上没发现问题，但未逐项确认)。
- 后台 daemon(`~/.claude/daemon`)在两个配置目录并存时的行为。
- Claude Code 在 Chrome 未运行时是否会自动拉起(按文档排错步骤推断不会)。
