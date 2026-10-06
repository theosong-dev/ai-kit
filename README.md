# ai-kit

给 AI coding agent(Claude Code、Codex)用的工程协作工具包:项目记忆模板、收尾与蒸馏 skill、分档实施 agent 与独立验收 agent、护栏 hook、状态显示 mod,以及背后的经验文档。

## 解决什么问题

- **换工具、换会话就丢记忆。** 用项目内 `.ai/` 文件记录进度、决策、踩坑,Claude Code 与 Codex 读同一份。
- **agent 说「做完了」不可信。** 实施交给 subagent,验收交给不带实施历史、只读的 verifier。
- **同样的错反复犯。** 踩坑先记进 `.ai/GOTCHAS.md`,攒够了用 `/distill` 提炼成规则;能用 hook 拦的不写成提示词。

## 仓库内容

| 目录 / 文件 | 是什么 | 装到哪 |
|---|---|---|
| `templates/global/AGENTS.md` | 跨工具共享的个人偏好 | `~/.ai/AGENTS.md` |
| `templates/global/claude-CLAUDE.md` | Claude Code 全局入口 | `~/.claude/CLAUDE.md` |
| `templates/global/codex-AGENTS.md` | Codex 全局入口 | `~/.codex/AGENTS.md` |
| `templates/project/` | 项目 `AGENTS.md` 与 `.ai/` 三个记忆文件模板 | `.ai/` 三个文件复制到 `~/.ai/templates/`;项目里由 `initai` 生成 |
| `skills/wrap`、`skills/distill` | 会话收尾;经验蒸馏成规则 | `~/.agents/skills/<名>` 软链接到仓库;`~/.claude/skills/<名>`、`~/.codex/skills/<名>` 软链接到 `~/.agents/skills/<名>` |
| `claude/agents/` | 四档实施 agent 与 `verifier` | 复制到 `~/.claude/agents/` |
| `claude/hooks/` | `guard.sh`(危险命令护栏)、`session-start.sh`(注入进度);`guard_test.sh` 是测试 | 除 `*_test.sh` 外复制到 `~/.claude/hooks/` 并加可执行位 |
| `claude/settings-snippet.json` | 注册上述 hook 的片段 | 不自动安装,手动合并进 `~/.claude/settings.json` |
| `mods/` | Claude Code 插件 `token-weather`、`turn-signals` | 不安装,用 `--plugin-dir` 加载 |
| `docs/` | 经验文档 | 不安装 |
| `scripts/`、`shell/` | `init-ai.sh`、`newproj.sh`;`shell/ai-kit.sh` 提供 `initai` / `newproj` / `checkgit` | shell rc 里追加一行 source `shell/ai-kit.sh` |
| `tests/` | `install_test.sh`,在临时假 HOME 下测试安装 | 不安装 |

## 安装

```bash
git clone https://github.com/atopsnow/ai-kit.git ~/Projects/ai-kit
cd ~/Projects/ai-kit
bash install.sh --dry-run   # 只打印将做什么
bash install.sh
```

| 参数 | 作用 |
|---|---|
| `--dry-run` | 只打印,不写任何东西 |
| `--no-skill` | 不装 `wrap` / `distill` |
| `--no-claude` | 不复制 `claude/agents`、`claude/hooks` |
| `--no-codex` | 不写 `~/.codex/AGENTS.md`,不建 `~/.codex/skills/` 软链接 |

**不覆盖任何已存在的文件**(含真实目录、悬空软链接)。遇到已存在的目标只输出一行:

- `ok`:内容一致,或软链接已指向同一位置(相对路径软链接也算)。
- `skip ... 对比: diff ...`:内容不同或指向别处,未改动;按提示的 `diff` 自行比较、手动合并。
- `create` / `link` / `write`:本次新建文件、软链接,或往 shell rc 追加 source 行。

可重复运行,第二次不再出现 `create` / `link` / `write`。不做 git 操作,不改 `~/.claude/settings.json`。

安装后手动做:

1. 开新终端或 `source` 你的 shell rc。
2. 编辑 `~/.ai/AGENTS.md`,填入自己的偏好。
3. 把 `claude/settings-snippet.json` 的 `hooks` 合并进 `~/.claude/settings.json`。
4. mods:`claude --plugin-dir <ai-kit>/mods`,详见 `mods/README.md`。

## 从旧版 ai-kit 升级

旧版把 `~/.claude/CLAUDE.md`、`~/.codex/AGENTS.md` 软链接到 `~/.ai/AGENTS.md`。新版是「共享偏好 + 每个宿主一个入口文件」:`~/.ai/AGENTS.md` 只放共享偏好,两个入口文件各自独立、先引用共享文件再补充本工具配置。

`install.sh` 不动旧软链接,只打印 `note`。迁移:

```bash
rm ~/.claude/CLAUDE.md ~/.codex/AGENTS.md   # 只删软链接
bash install.sh                             # 从模板生成入口文件
```

再把 `~/.ai/AGENTS.md` 里只属于某个工具的内容移到对应入口文件。旧版重装会覆盖 wrap skill 的问题已修:已存在的 skill 目录一律不动。

## 在项目里启用

- `initai`:在当前项目生成 `AGENTS.md`、`CLAUDE.md -> AGENTS.md` 软链接和 `.ai/PROGRESS.md`、`DECISIONS.md`、`GOTCHAS.md`,已存在的跳过。
- `newproj <项目名> [父目录]`:建目录、`git init`、`.gitignore`、上述文件,结束后停在新目录。父目录默认 `$AI_KIT_PROJECTS_DIR`,未设置时 `~/Projects`。
- `checkgit [目录]`:列出该目录下未 `git init` 的子项目。

## 日常用法

- 会话开头读 `.ai/PROGRESS.md`;注册了 SessionStart hook 则自动注入。
- 结束前 `/wrap`:更新进度与下一步,有决策或踩坑时同步 `DECISIONS.md` / `GOTCHAS.md`。
- 积累后 `/distill`:把重复或代价高的坑提炼成规则,放到共享规则、skill 或 hook 中的一处,并删掉过时规则。

主会话只做规划、派单、验收;实施按难度派给某一档实施 agent,完成后派 `verifier`,只给它任务要求、diff 和验收标准。理由见 `docs/02-主会话与实施分工.md`。

## 经验文档

| 文件 | 内容 |
|---|---|
| `docs/01-双层记忆循环.md` | 项目记忆怎么不丢、不膨胀、变成规则 |
| `docs/02-主会话与实施分工.md` | 规划、派单、验收分开做 |
| `docs/03-护栏机制化.md` | 能用机制拦的,不写成提示词规则 |
| `docs/04-信号日志与验收统计.md` | 跨会话记录失败与验收结论 |
| `docs/05-Claude-Code-多账号.md` | 同一台 Mac 上两个账号互不串 |
| `docs/06-让模型输出更好读.md` | 让模型的输出更好读:速查 |

## 平台支持与已知限制

- 已测:macOS。`bash tests/install_test.sh` 在 macOS bash 3.2 与 bash 5.x 下通过(只用临时假 HOME)。
- 未测:Linux、Windows、WSL、Git Bash。
- 软链接不可用时退化为复制(不随仓库更新),该分支未实际触发过。
- Codex 侧只有入口模板和共享 skill;`claude/agents`、`claude/hooks`、`mods/` 仅 Claude Code。
