# Claude Code 分流与验收

仅在当前宿主是 Claude Code 时读取。

- 生命周期动作:按现有配置使用 `settings.json` 的 hooks,或宿主支持的 skill / agent frontmatter hooks。
- 禁止操作:评估 `permissions.deny` 或 `PreToolUse` hook;现有 `~/.claude/hooks/guard.sh` 可作为参考,先读实现再修改。不能假定文本规则能阻断工具。
- 文件类型条件:可用 `.claude/rules/*.md` 的 `paths:`;目录要求优先共享子目录 `AGENTS.md`,确保 Claude 对应入口会读取它,必要时用子目录 `CLAUDE.md` 引用。
- 权限配置仅在 Claude Code 生效;不要转换为 Codex 的已授权声明。
- 信号日志追查原始会话记录(步骤 2):路径是 `<配置目录>/projects/<会话 cwd 里的 / 等非字母数字字符换成 ->/<session id>.jsonl`,配置目录是 `~/.claude` 或 `CLAUDE_CONFIG_DIR`;日志的 `account` 字段即配置目录名去掉开头的点(`claude-2` → `~/.claude-2`)。subagent 的记录在 `<session id>/subagents/agent-<agentId>.jsonl`。signals.sh 只给 session id 前 8 位,用 `ls <配置目录>/projects/*/<前8位>*.jsonl` 定位;只 grep 失败的命令或报错文本看前后片段,不通读。
- 具体 schema/版本能力以本机 CLI 与当前官方说明为准。配置变更后用真实触发和匹配/不匹配命令案例验证;需要重载则重开会话,可用 `/doctor` 辅助诊断,但其通过不能代替拦截行为验证。没有执行的检查明确列为未验证。
