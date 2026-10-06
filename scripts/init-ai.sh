#!/bin/bash
# init-ai.sh —— 在当前项目铺设跨工具 AI 协作体系
# 用法:在项目根目录运行 `bash init-ai.sh`
# 幂等:已存在的文件不会被覆盖。

set -e

TEMPLATE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/templates/project"

for f in AGENTS.md .ai/PROGRESS.md .ai/DECISIONS.md .ai/GOTCHAS.md; do
  if [ ! -f "$TEMPLATE_DIR/$f" ]; then
    echo "error  模板缺失: $TEMPLATE_DIR/$f(请确认 ai-kit 仓库完整)" >&2
    exit 1
  fi
done

mkdir -p .ai

# 复制模板,已存在则跳过
copy_if_absent() {
  local src="$1" dst="$2"
  if [ -e "$dst" ]; then
    echo "skip   $dst (已存在)"
  else
    cp "$src" "$dst"
    echo "create $dst"
  fi
}

copy_if_absent "$TEMPLATE_DIR/AGENTS.md"          "AGENTS.md"
copy_if_absent "$TEMPLATE_DIR/.ai/PROGRESS.md"    ".ai/PROGRESS.md"
copy_if_absent "$TEMPLATE_DIR/.ai/DECISIONS.md"   ".ai/DECISIONS.md"
copy_if_absent "$TEMPLATE_DIR/.ai/GOTCHAS.md"     ".ai/GOTCHAS.md"

# CLAUDE.md 指向 AGENTS.md 的 symlink
if [ -e "CLAUDE.md" ] || [ -L "CLAUDE.md" ]; then
  echo "skip   CLAUDE.md (已存在)"
else
  ln -s AGENTS.md CLAUDE.md
  echo "link   CLAUDE.md -> AGENTS.md"
fi

echo ""
echo "完成。下一步:编辑 AGENTS.md 填入项目简介和构建命令。"