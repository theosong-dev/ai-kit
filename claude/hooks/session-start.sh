#!/bin/bash
# SessionStart hook: 有 .ai/ 的仓库自动注入 PROGRESS.md 尾部 + git 状态,不依赖模型主动读。
[ -f .ai/PROGRESS.md ] || exit 0
echo "## .ai/PROGRESS.md (tail 60)"
tail -n 60 .ai/PROGRESS.md
echo
echo "## git"
git status -sb 2>/dev/null
git log --oneline -5 2>/dev/null
exit 0
