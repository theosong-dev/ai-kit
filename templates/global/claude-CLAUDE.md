# Claude Code 全局入口

> 模板:安装到 `~/.claude/CLAUDE.md`。下列 agent(`*-implementer*`、`verifier`)和 hook 由 ai-kit 安装到 `~/.claude/`。

开始工作前先读取 `~/.ai/AGENTS.md`,遵守其中共享偏好和工作协议;本文件补充 Claude Code 的执行配置。项目规则仍按共享协议优先。

## 实施与验收

- 主会话的模型与 effort 在 `settings.json` 中设定(按自己情况选)。主会话只做规划、派单、验收,实施派 subagent。
- effort 只能写在 agent 文件 frontmatter 里,派单时无法临时指定,所以按档位拆成多个 agent,派单时选名字。effort 买的是验证量和 edge case 覆盖,治不了方向错;选档看隐藏 edge case 多不多、改错代价高不高,不看任务大小:
  - `sonnet-implementer`(`model: sonnet`,`effort: medium`):方案完全明确、单文件或少量文件的机械任务。
  - `opus-implementer`(`model: opus`,`effort: medium`):方案清楚但跨文件、需读较多上下文的常规实施。拿不准时用这个。
  - `opus-implementer-high`(`effort: high`):方案留有判断空间、需权衡实现路径、改错代价较高。
  - `opus-implementer-xhigh`(`effort: xhigh`):非显而易见 bug、并发/一致性问题、核心路径重构。只在明确困难的任务上用;同一问题失败两次就回主会话重新定方案,不再加档。
- 升档之前先在派单里给实施者自检手段(能跑的测试、构建或命令):一次检查只花一轮,升档是每轮都多想。
- 所有实施 agent 完成后都过 verifier。
- 验收使用 `~/.claude/agents/verifier.md`,只读,不带实施历史;只给任务要求、待验收 diff/文件和验收标准。
- 用户可见的界面改动用 `claude-in-chrome` 在浏览器实际走通。

## 远程与部署

- `ssh / scp / rsync` 和各仓库 deploy 脚本的放行规则写在 `~/.claude/settings.json` 的 `permissions.allow`,以实际配置为准;新增部署脚本时把对应规则补进同一文件。
- ssh 用 `ssh <alias> '<cmd>'`(别名在 `~/.ssh/config`),不写 `ssh -o … user@IP`;部署脚本直接调用,不加 `cd` 前缀,便于放行规则匹配。

## auto 分类器

- 分类器稳定拦三类:读写浏览器 cookie / 登录态 / 凭据同步;clone 并运行第三方代码、开 Chrome remote debugging;往 `~/.ai` `~/.zshrc` 等用户配置写入,以及改 `~/.claude/agents/*.md` 的 frontmatter(正文可直接改)。遇到这三类不要先自己试,直接把可粘贴的命令给用户用 `!` 跑,并先读 `--help` 确认输入格式。
- 需要长期放行的工具走 `permissions.allow`(allow 先于分类器),不改 prompt 绕。

## 共享 skills

- `wrap`、`distill` 共用 `~/.agents/skills/` 下正文。按本次读取的 `SKILL.md` 所在目录定位脚本,显式传目标项目根;不依赖宿主环境变量。
- 更新这些文件后,已读过旧内容的会话应重读对应文件,或在新会话使用。
