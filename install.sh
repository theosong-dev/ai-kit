#!/usr/bin/env bash
# install.sh —— ai-kit 一键部署到新机器(macOS / Linux / WSL / Git Bash)
#
# 用法:
#   bash install.sh            # 全装(含 wrap skill)
#   bash install.sh --no-skill # 跳过 wrap skill
#
# 幂等:可重复运行。已存在的文件 / 软链接 / rc 行一律跳过,绝不覆盖你的真实文件。
# 不执行任何 git 操作。

set -e

INSTALL_SKILL=1
for arg in "$@"; do
  case "$arg" in
    --no-skill) INSTALL_SKILL=0 ;;
    *) echo "未知参数: $arg"; echo "用法: bash install.sh [--no-skill]"; exit 1 ;;
  esac
done

AI_KIT_DIR="$(cd "$(dirname "$0")" && pwd)"
echo "ai-kit 根目录: $AI_KIT_DIR"

# ============================================================
# link_or_warn <src> <dst> —— 幂等建软链接,带退化与保护
# ============================================================
link_or_warn() {
  local src="$1" dst="$2"
  if [ -L "$dst" ]; then
    if [ "$(readlink "$dst")" = "$src" ]; then
      echo "ok     $dst -> $src"
      return 0
    fi
    echo "warn   $dst 已是软链接但指向别处($(readlink "$dst")),未改动,请手动确认"
    return 0
  fi
  if [ -e "$dst" ]; then
    echo "warn   $dst 是真实文件(非软链接),未覆盖。如需统一到单一源请手动处理"
    return 0
  fi
  ln -s "$src" "$dst" 2>/dev/null || true
  if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
    echo "link   $dst -> $src"
  else
    rm -f "$dst" 2>/dev/null || true
    cp "$src" "$dst"
    echo "warn   软链接不可用,已退化为复制:$dst(本平台不支持 symlink,内容不会随源同步)"
  fi
}

# ============================================================
# 1. shell 集成 —— 往 rc 文件幂等写入 source 行
# ============================================================
SOURCE_LINE="[ -f \"$AI_KIT_DIR/shell/ai-kit.sh\" ] && source \"$AI_KIT_DIR/shell/ai-kit.sh\""

pick_rc() {
  case "${SHELL##*/}" in
    zsh) echo "$HOME/.zshrc" ;;
    bash)
      if [ -f "$HOME/.bashrc" ]; then echo "$HOME/.bashrc"; else echo "$HOME/.bash_profile"; fi ;;
    *)
      if [ -n "$ZSH_VERSION" ]; then echo "$HOME/.zshrc"; else echo "$HOME/.bashrc"; fi ;;
  esac
}

RC_FILE="$(pick_rc)"
touch "$RC_FILE"
if grep -qF "shell/ai-kit.sh" "$RC_FILE"; then
  echo "skip   $RC_FILE 已接入 ai-kit.sh"
else
  printf '\n# ai-kit\n%s\n' "$SOURCE_LINE" >> "$RC_FILE"
  echo "write  $RC_FILE 已加入 source 行"
fi

# ============================================================
# 2. 全局 ~/.ai/AGENTS.md 单一源 + 软链接
# ============================================================
mkdir -p "$HOME/.ai" "$HOME/.claude" "$HOME/.codex"
if [ -e "$HOME/.ai/AGENTS.md" ]; then
  echo "skip   ~/.ai/AGENTS.md(已存在,未覆盖)"
else
  cp "$AI_KIT_DIR/templates/global-AGENTS.md" "$HOME/.ai/AGENTS.md"
  echo "create ~/.ai/AGENTS.md(骨架模板,请填入你的偏好)"
fi
link_or_warn "$HOME/.ai/AGENTS.md" "$HOME/.claude/CLAUDE.md"
link_or_warn "$HOME/.ai/AGENTS.md" "$HOME/.codex/AGENTS.md"

# ============================================================
# 3. wrap skill(Claude Code 专属,默认装,--no-skill 跳过)
# ============================================================
if [ "$INSTALL_SKILL" -eq 1 ]; then
  mkdir -p "$HOME/.claude/skills/wrap"
  cp "$AI_KIT_DIR/scripts/wrap-skill-SKILL.md" "$HOME/.claude/skills/wrap/SKILL.md"
  echo "ok     wrap skill -> ~/.claude/skills/wrap/SKILL.md"
else
  echo "skip   wrap skill(--no-skill)"
fi

# ============================================================
# 4. 收尾
# ============================================================
echo ""
echo "=============================================="
echo "ai-kit 安装完成。"
echo "下一步:"
echo "  1. 开新终端,或运行: source $RC_FILE"
echo "  2. 编辑 ~/.ai/AGENTS.md 填入你的全局个人偏好"
echo "  3. 在任意项目根目录运行 initai,或用 newproj <名> 新建项目"
echo "=============================================="
