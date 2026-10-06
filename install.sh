#!/usr/bin/env bash
# install.sh —— ai-kit 一键部署到新机器(macOS 实测;Linux / WSL / Git Bash 未测)
#
# 用法: bash install.sh [--dry-run] [--no-skill] [--no-claude] [--no-codex] [-h|--help]
#
# 总原则:任何已存在的目标(文件、目录、软链接,含悬空软链接)一律不覆盖、不写穿、不删除。
# 幂等:可重复运行,第二次不会产生 create / link / write。
# 不执行任何 git 操作,不修改 ~/.claude/settings.json。

set -e

DRY_RUN=0; INSTALL_SKILL=1; INSTALL_CLAUDE=1; INSTALL_CODEX=1
usage() { echo "用法: bash install.sh [--dry-run] [--no-skill] [--no-claude] [--no-codex] [-h|--help]"; }
for arg in "$@"; do
  case "$arg" in
    --dry-run)   DRY_RUN=1 ;;
    --no-skill)  INSTALL_SKILL=0 ;;
    --no-claude) INSTALL_CLAUDE=0 ;;
    --no-codex)  INSTALL_CODEX=0 ;;
    -h|--help)   usage; exit 0 ;;
    *) echo "未知参数: $arg"; usage; exit 1 ;;
  esac
done

AI_KIT_DIR="$(cd "$(dirname "$0")" && pwd)"
echo "ai-kit 根目录: $AI_KIT_DIR"
if [ "$DRY_RUN" -eq 1 ]; then echo "(dry-run:只打印将做什么,不写任何东西)"; fi

act() { if [ "$DRY_RUN" -eq 1 ]; then echo "[dry-run] $*"; else echo "$*"; fi; }
exists() { [ -e "$1" ] || [ -L "$1" ]; }

# copy_if_absent <src> <dst> [exec] —— 不存在才复制;存在则 ok / skip + diff 提示
copy_if_absent() {
  local src="$1" dst="$2" mode="$3"
  if [ ! -f "$src" ]; then echo "warn   源缺失,跳过:$src"; return 0; fi
  if exists "$dst"; then
    if [ -f "$dst" ] && cmp -s "$src" "$dst"; then
      echo "ok     $dst"
    else
      echo "skip   $dst 已存在且与模板不同,未覆盖。对比: diff \"$src\" \"$dst\""
    fi
    return 0
  fi
  if [ "$DRY_RUN" -eq 0 ]; then
    mkdir -p "$(dirname "$dst")"
    cp "$src" "$dst"
    if [ "$mode" = "exec" ]; then chmod +x "$dst"; fi
  fi
  act "create $dst"
}

# link_dir <src> <dst> —— 目录软链接;软链接不可用时退化为 cp -R
link_dir() {
  local src="$1" dst="$2"
  if exists "$dst"; then
    if [ -L "$dst" ] && { [ "$(readlink "$dst")" = "$src" ] || [ "$dst" -ef "$src" ]; }; then
      echo "ok     $dst -> $src"
    else
      echo "skip   $dst 已存在(真实目录或指向别处),未改动。对比: diff -r \"$src\" \"$dst\""
    fi
    return 0
  fi
  if [ "$DRY_RUN" -eq 1 ]; then act "link   $dst -> $src"; return 0; fi
  mkdir -p "$(dirname "$dst")"
  ln -s "$src" "$dst" 2>/dev/null || true
  if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
    echo "link   $dst -> $src"
  else
    if [ -L "$dst" ]; then rm -f "$dst"; fi   # 只清理本步刚建出的坏链接(上面已确认原先不存在)
    cp -R "$src" "$dst"
    echo "warn   软链接不可用,已退化为复制:$dst(不会随仓库更新)"
  fi
}

# ---- 1. shell 集成 ----
SOURCE_LINE="[ -f \"$AI_KIT_DIR/shell/ai-kit.sh\" ] && source \"$AI_KIT_DIR/shell/ai-kit.sh\""
pick_rc() {
  case "${SHELL##*/}" in
    zsh) echo "$HOME/.zshrc" ;;
    bash) if [ -f "$HOME/.bashrc" ]; then echo "$HOME/.bashrc"; else echo "$HOME/.bash_profile"; fi ;;
    *) if [ -n "$ZSH_VERSION" ]; then echo "$HOME/.zshrc"; else echo "$HOME/.bashrc"; fi ;;
  esac
}
RC_FILE="$(pick_rc)"
if [ -f "$RC_FILE" ] && grep -qF "shell/ai-kit.sh" "$RC_FILE"; then
  echo "skip   $RC_FILE 已接入 ai-kit.sh"
else
  if [ "$DRY_RUN" -eq 0 ]; then printf '\n# ai-kit\n%s\n' "$SOURCE_LINE" >> "$RC_FILE"; fi
  act "write  $RC_FILE 加入 source 行"
fi

# ---- 2. 全局入口文件(各自独立,不存在才从模板复制) ----
T="$AI_KIT_DIR/templates"
global_entry() {   # <src> <dst>
  local src="$1" dst="$2"
  if [ -L "$dst" ] && { [ "$(readlink "$dst")" = "$HOME/.ai/AGENTS.md" ] || [ "$dst" -ef "$HOME/.ai/AGENTS.md" ]; }; then
    echo "note   $dst 是指向 ~/.ai/AGENTS.md 的软链接(旧版 ai-kit 布局),未改动。"
    echo "       新布局下它是独立入口文件;如需迁移:rm \"$dst\" 后重跑 install.sh"
    return 0
  fi
  copy_if_absent "$src" "$dst"
}
copy_if_absent "$T/global/AGENTS.md" "$HOME/.ai/AGENTS.md"
global_entry "$T/global/claude-CLAUDE.md" "$HOME/.claude/CLAUDE.md"
if [ "$INSTALL_CODEX" -eq 1 ]; then global_entry "$T/global/codex-AGENTS.md" "$HOME/.codex/AGENTS.md"; fi
for f in PROGRESS DECISIONS GOTCHAS; do
  copy_if_absent "$T/project/.ai/$f.md" "$HOME/.ai/templates/$f.md"
done

# ---- 3. skills:~/.agents/skills/<n> 软链到仓库;Claude / Codex 再软链到 ~/.agents ----
if [ "$INSTALL_SKILL" -eq 0 ]; then
  echo "skip   skills(--no-skill)"
elif [ ! -d "$AI_KIT_DIR/skills" ]; then
  echo "warn   源缺失,跳过:$AI_KIT_DIR/skills"
else
  for d in "$AI_KIT_DIR/skills"/*/; do
    [ -d "$d" ] || continue
    n="$(basename "$d")"
    shared="$HOME/.agents/skills/$n"
    link_dir "$AI_KIT_DIR/skills/$n" "$shared"
    link_dir "$shared" "$HOME/.claude/skills/$n"
    if [ "$INSTALL_CODEX" -eq 1 ]; then link_dir "$shared" "$HOME/.codex/skills/$n"; fi
  done
fi

# ---- 4. Claude 资产:agents / hooks(不存在才复制,不改 settings.json) ----
if [ "$INSTALL_CLAUDE" -eq 0 ]; then
  echo "skip   claude agents / hooks(--no-claude)"
else
  for sub in agents:md hooks:sh; do
    dir="${sub%%:*}"; ext="${sub##*:}"
    if [ ! -d "$AI_KIT_DIR/claude/$dir" ]; then echo "warn   源缺失,跳过:$AI_KIT_DIR/claude/$dir"; continue; fi
    for f in "$AI_KIT_DIR/claude/$dir"/*."$ext"; do
      [ -f "$f" ] || continue
      case "$(basename "$f")" in *_test.sh) continue ;; esac   # 测试脚本不安装
      mode=""; if [ "$dir" = hooks ]; then mode=exec; fi
      copy_if_absent "$f" "$HOME/.claude/$dir/$(basename "$f")" "$mode"
    done
  done
fi

# ---- 5. 收尾 ----
echo ""
echo "=============================================="
echo "ai-kit 安装完成。下一步:"
echo "  1. 开新终端,或运行: source \"$RC_FILE\""
echo "  2. 编辑 ~/.ai/AGENTS.md 填入你的全局个人偏好"
echo "  3. hook 需要在 ~/.claude/settings.json 注册(本脚本不修改它),片段见:"
echo "       $AI_KIT_DIR/claude/settings-snippet.json"
echo "  4. mods 用法: claude --plugin-dir \"$AI_KIT_DIR/mods\""
echo "  5. 在任意项目根目录运行 initai,或用 newproj <名> 新建项目"
echo "=============================================="
