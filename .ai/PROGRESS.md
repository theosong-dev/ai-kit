# 项目进度

> 跨会话 handoff 主文件。每次会话开头读它,结束前更新它。
> 最后更新:2026-10-06
>
> **体积上限(/wrap 用 `wc -l` / `grep -c` 强制,不靠目测):**
> 全文 ≤ 120 行;「当前状态」≤ 10 行;「进度日志」只留最近 10 条。
> 超限:把「进度日志」多出的条目**追加**到 `.ai/archive/PROGRESS-YYYY-MM.md`
> (按归档时年月命名,目录不存在就建),原文进 archive,本文件只留压缩后的一行。
> 结构固定为下面六段,发现漂移(多余的顶层日期小节等)先归位再更新。
> 理由:这是每次会话开头都读的 handoff 文件,体积直接吃 context;历史细节 git log 和 archive 里都有。

## 当前状态

- 2026-10-06 从 6 月的「三文件模板 + wrap」升级为完整工具包:新增 `templates/`(project / global 模板)、`skills/`(wrap、distill)、`claude/`(实施分档 agents、verifier、hooks、settings 片段)、`mods/`、`docs/`。
- 全局入口改为「`~/.ai/AGENTS.md` 共享偏好 + 每宿主薄入口」;仓库根 `AGENTS.md` / `.ai/` 改为本仓库自己的真实记忆。
- 未在新机器上做端到端实装验证;Windows / Git Bash 未测。

## 下一步

- 在一台干净机器(或全新临时 HOME)上按 README 端到端走一遍安装,确认 Claude Code 与 Codex 都能读到入口、wrap / distill 可用。
- 在 Windows / Git Bash 下验证 `install.sh` 的软链接与路径处理,不行就在 README 标明不支持。

## 任务清单

- [x] 模板搬进 `templates/`,仓库根改为真实记忆
- [x] 全局模板去私有化(共享偏好 + Claude / Codex 入口)
- [ ] 新机器端到端实装验证
- [ ] Windows / Git Bash 验证

## 遗留 / 待澄清

## 用户纠正（待蒸馏）

## 进度日志

- 2026-10-06 —— 升级为完整工具包:模板迁入 templates/,全局入口拆成共享偏好 + 每宿主薄入口,补齐仓库自身记忆
