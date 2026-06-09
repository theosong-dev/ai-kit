# AI 项目协作工具包

跨 AI 工具的工程记忆体系。AI 工具(Claude Code / Codex / Cursor…)可以换,项目记忆不丢。

## 设计原则

- **工具适配层最薄,项目事实层最厚。** 真正的资产是 `.ai/` 里的 markdown,与任何 AI 工具解耦。
- **AGENTS.md 当主入口**,跨工具开放标准。`CLAUDE.md` 是指向它的 symlink,零重复、零漂移。
- **单一事实源贯穿项目级与全局级。** 项目级 `CLAUDE.md → AGENTS.md`;全局级 `~/.claude/CLAUDE.md`、`~/.codex/AGENTS.md → ~/.ai/AGENTS.md`。
- **起步只要 3 个记忆文件**,不预防性建文件,用两周后再按需扩展。

## 安装(新机器)

```bash
git clone https://github.com/atopsnow/ai-kit.git ~/Projects/ai-kit
bash ~/Projects/ai-kit/install.sh
```

`install.sh` 幂等,可重复运行,做三件事:

1. 把 `source .../shell/ai-kit.sh` 接入你的 `~/.zshrc` 或 `~/.bashrc`(已接入则跳过)。
2. 铺设全局 `~/.ai/AGENTS.md`(不存在才从模板建),并建 `~/.claude/CLAUDE.md`、`~/.codex/AGENTS.md` 指向它的软链接。
3. 安装 wrap skill 到 `~/.claude/skills/wrap/`(`--no-skill` 可跳过)。

装完开新终端(或 `source` 对应 rc 文件),即可用 `newproj` / `initai` / `checkgit`。
然后编辑 `~/.ai/AGENTS.md` 填入你的全局个人偏好。

> 绝不覆盖已存在的 `~/.ai/AGENTS.md` 与已正确的软链接;遇到真实文件只警告不动手。

## 平台支持

| 平台 | 说明 |
|---|---|
| macOS / Linux | 原生 bash/zsh,完整支持 |
| Windows | 经 WSL 或 Git Bash 运行(Git Bash 需 `git config --global core.symlinks true`) |

原生 PowerShell / cmd 不支持(symlink 需管理员或开发者模式)。若 symlink 不可用,
install.sh 会自动退化为复制并打印警告——此时全局文件不再随源同步,需手动维护。

## 文件说明

| 文件 | 作用 | 更新频率 |
|---|---|---|
| `AGENTS.md` | 项目工作协议 + 构建命令。所有 agent 入口 | 低,稳定 |
| `CLAUDE.md` | → symlink 指向 AGENTS.md | 不手动改 |
| `.ai/PROGRESS.md` | 进度 + 任务清单。跨会话 handoff 主文件 | 高,每次会话 |
| `.ai/DECISIONS.md` | 决策日志,只增不改 | 有决策时 |
| `.ai/GOTCHAS.md` | 踩坑记录,只增不改 | 踩坑时 |

## 在新项目里启用

安装后,在任意项目根目录运行:

```bash
initai          # 在已存在的项目补铺 .ai 体系(不碰 git)
```

或新建工程(建目录 + git init + .gitignore + .ai 体系):

```bash
newproj my-robot                  # 在默认父目录($HOME/Projects 或 $AI_KIT_PROJECTS_DIR)下创建
newproj my-robot ~/Projects/work  # 指定父目录
```

脚本幂等,已存在的文件会跳过。运行后编辑 `AGENTS.md` 填入项目简介和构建命令。

## 日常用法

**会话开头:**
> 读 .ai/PROGRESS.md,告诉我上次到哪了,以及接下来建议做什么。

**会话结束前:**
> /wrap

(或不依赖 skill,直接说:更新 .ai/PROGRESS.md;有决策或踩坑同步更新 DECISIONS / GOTCHAS。)

## wrap skill(仅 Claude Code)

`install.sh` 默认已把 `scripts/wrap-skill-SKILL.md` 装到 `~/.claude/skills/wrap/SKILL.md`。
跳过用 `bash install.sh --no-skill`。

skill 是 Claude Code 机制,不跨工具。收尾协议的事实源在 AGENTS.md「项目记忆协议」段——
Codex 等其他工具读 AGENTS.md 即可执行同样流程,只是没有 /wrap 这个快捷触发。

## 全局个人偏好

`.ai/` 是**项目级**记忆。你的**跨项目个人偏好**放在全局单一事实源 `~/.ai/AGENTS.md`,
各工具的全局配置文件由 install.sh 建为指向它的软链接:

- `~/.claude/CLAUDE.md` → `~/.ai/AGENTS.md`(Claude Code 全局)
- `~/.codex/AGENTS.md` → `~/.ai/AGENTS.md`(Codex 全局)

只放跨项目偏好,不放任何具体项目信息。改一处,所有工具同步生效。
