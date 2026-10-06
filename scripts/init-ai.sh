#!/bin/bash
# init-ai.sh -- set up the cross-tool AI collaboration files in the current project
# Usage: run `bash init-ai.sh` in the project root
# Idempotent: existing files are never overwritten.
# AI_KIT_LANG=zh-CN picks the templates under zh-CN/templates/project.

set -e

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ "${AI_KIT_LANG:-}" = "zh-CN" ]; then
  TEMPLATE_DIR="$KIT_DIR/zh-CN/templates/project"
else
  TEMPLATE_DIR="$KIT_DIR/templates/project"
fi

for f in AGENTS.md .ai/PROGRESS.md .ai/DECISIONS.md .ai/GOTCHAS.md; do
  if [ ! -f "$TEMPLATE_DIR/$f" ]; then
    echo "error  template missing: $TEMPLATE_DIR/$f (check that the ai-kit repo is complete)" >&2
    exit 1
  fi
done

mkdir -p .ai

# copy a template; skip if the target exists
copy_if_absent() {
  local src="$1" dst="$2"
  if [ -e "$dst" ]; then
    echo "skip   $dst (exists)"
  else
    cp "$src" "$dst"
    echo "create $dst"
  fi
}

copy_if_absent "$TEMPLATE_DIR/AGENTS.md"          "AGENTS.md"
copy_if_absent "$TEMPLATE_DIR/.ai/PROGRESS.md"    ".ai/PROGRESS.md"
copy_if_absent "$TEMPLATE_DIR/.ai/DECISIONS.md"   ".ai/DECISIONS.md"
copy_if_absent "$TEMPLATE_DIR/.ai/GOTCHAS.md"     ".ai/GOTCHAS.md"

# CLAUDE.md is a symlink to AGENTS.md
if [ -e "CLAUDE.md" ] || [ -L "CLAUDE.md" ]; then
  echo "skip   CLAUDE.md (exists)"
else
  ln -s AGENTS.md CLAUDE.md
  echo "link   CLAUDE.md -> AGENTS.md"
fi

echo ""
echo "Done. Next: edit AGENTS.md with the project overview and build commands."