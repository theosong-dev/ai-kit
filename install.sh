#!/usr/bin/env bash
# install.sh -- one-shot ai-kit setup for a new machine (tested on macOS; Linux / WSL / Git Bash untested)
#
# Usage: bash install.sh [--dry-run] [--lang en|zh-CN] [--no-skill] [--no-claude] [--no-codex] [-h|--help]
#
# Rule: any existing target (file, directory, symlink, including dangling symlinks) is never
# overwritten, written through, or deleted.
# Idempotent: a second run produces no create / link / write.
# Runs no git commands and never touches ~/.claude/settings.json.
# --lang zh-CN takes templates / skills / agents from zh-CN/ (hooks are shared).

set -e

DRY_RUN=0; INSTALL_SKILL=1; INSTALL_CLAUDE=1; INSTALL_CODEX=1; LANG_OPT=en
usage() { echo "Usage: bash install.sh [--dry-run] [--lang en|zh-CN] [--no-skill] [--no-claude] [--no-codex] [-h|--help]"; }
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run)   DRY_RUN=1 ;;
    --no-skill)  INSTALL_SKILL=0 ;;
    --no-claude) INSTALL_CLAUDE=0 ;;
    --no-codex)  INSTALL_CODEX=0 ;;
    --lang)
      if [ $# -lt 2 ] || [ -z "$2" ]; then echo "error  --lang needs a value (en or zh-CN)"; usage; exit 1; fi
      LANG_OPT="$2"; shift ;;
    --lang=*)    LANG_OPT="${1#--lang=}" ;;
    -h|--help)   usage; exit 0 ;;
    *) echo "error  unknown argument: $1"; usage; exit 1 ;;
  esac
  shift
done
case "$LANG_OPT" in
  en|zh-CN) ;;
  *) echo "error  unsupported --lang: $LANG_OPT (use en or zh-CN)"; exit 1 ;;
esac

AI_KIT_DIR="$(cd "$(dirname "$0")" && pwd)"
echo "ai-kit root: $AI_KIT_DIR"
echo "language: $LANG_OPT"
if [ "$DRY_RUN" -eq 1 ]; then echo "(dry-run: only printing what would be done; nothing is written)"; fi

act() { if [ "$DRY_RUN" -eq 1 ]; then echo "[dry-run] $*"; else echo "$*"; fi; }
exists() { [ -e "$1" ] || [ -L "$1" ]; }

# copy_if_absent <src> <dst> [exec] -- copy only if absent; otherwise ok / skip + diff hint
copy_if_absent() {
  local src="$1" dst="$2" mode="$3"
  if [ ! -f "$src" ]; then echo "warn   source missing, skipped: $src"; return 0; fi
  if exists "$dst"; then
    if [ -f "$dst" ] && cmp -s "$src" "$dst"; then
      echo "ok     $dst"
    else
      echo "skip   $dst exists and differs from the template; not overwritten. Compare: diff \"$src\" \"$dst\""
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

# link_dir <src> <dst> -- directory symlink; falls back to cp -R if symlinks are unavailable
link_dir() {
  local src="$1" dst="$2"
  if exists "$dst"; then
    if [ -L "$dst" ] && { [ "$(readlink "$dst")" = "$src" ] || [ "$dst" -ef "$src" ]; }; then
      echo "ok     $dst -> $src"
    else
      echo "skip   $dst exists (real directory or points elsewhere); left unchanged. Compare: diff -r \"$src\" \"$dst\""
    fi
    return 0
  fi
  if [ "$DRY_RUN" -eq 1 ]; then act "link   $dst -> $src"; return 0; fi
  mkdir -p "$(dirname "$dst")"
  ln -s "$src" "$dst" 2>/dev/null || true
  if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
    echo "link   $dst -> $src"
  else
    if [ -L "$dst" ]; then rm -f "$dst"; fi   # only remove the broken link this step just created (confirmed absent above)
    cp -R "$src" "$dst"
    echo "warn   symlinks unavailable, copied instead: $dst (will not follow repo updates)"
  fi
}

# ---- 0. language sources (fall back to defaults when a language dir is missing) ----
L="$AI_KIT_DIR/zh-CN"
pick_src() {   # <default dir> <language dir> -> sets SRC
  SRC="$1"
  if [ "$LANG_OPT" = en ]; then return 0; fi
  if [ -d "$2" ]; then SRC="$2"; else echo "warn   $LANG_OPT source missing: $2; falling back to $1"; fi
}
pick_src "$AI_KIT_DIR/templates" "$L/templates"; T="$SRC"
pick_src "$AI_KIT_DIR/skills" "$L/skills"; SKILL_SRC="$SRC"
pick_src "$AI_KIT_DIR/claude/agents" "$L/claude/agents"; AGENTS_SRC="$SRC"

# ---- 1. shell integration ----
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
  echo "skip   $RC_FILE already sources ai-kit.sh"
  RC_FRESH=0
else
  RC_FRESH=1; LANG_LINE=""
  if [ "$LANG_OPT" != en ]; then LANG_LINE="export AI_KIT_LANG=$LANG_OPT"; fi
  if [ "$DRY_RUN" -eq 0 ]; then
    if [ -n "$LANG_LINE" ]; then printf '\n# ai-kit\n%s\n%s\n' "$LANG_LINE" "$SOURCE_LINE" >> "$RC_FILE"
    else printf '\n# ai-kit\n%s\n' "$SOURCE_LINE" >> "$RC_FILE"; fi
  fi
  if [ -n "$LANG_LINE" ]; then act "write  $RC_FILE add: $LANG_LINE"; fi
  act "write  $RC_FILE add source line"
fi

# ---- 2. global entry files (independent; copied from templates only if absent) ----
global_entry() {   # <src> <dst>
  local src="$1" dst="$2"
  if [ -L "$dst" ] && { [ "$(readlink "$dst")" = "$HOME/.ai/AGENTS.md" ] || [ "$dst" -ef "$HOME/.ai/AGENTS.md" ]; }; then
    echo "note   $dst is a symlink to ~/.ai/AGENTS.md (old ai-kit layout); left unchanged."
    echo "       In the new layout it is a standalone entry file; to migrate: rm \"$dst\" and rerun install.sh"
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

# ---- 3. skills: ~/.agents/skills/<n> links into the repo; Claude / Codex link to ~/.agents ----
if [ "$INSTALL_SKILL" -eq 0 ]; then
  echo "skip   skills (--no-skill)"
elif [ ! -d "$AI_KIT_DIR/skills" ]; then
  echo "warn   source missing, skipped: $AI_KIT_DIR/skills"
else
  for d in "$AI_KIT_DIR/skills"/*/; do
    [ -d "$d" ] || continue
    n="$(basename "$d")"
    shared="$HOME/.agents/skills/$n"
    src="$SKILL_SRC/$n"
    if [ ! -d "$src" ]; then
      echo "note   $LANG_OPT skill missing: $src; using $AI_KIT_DIR/skills/$n"
      src="$AI_KIT_DIR/skills/$n"
    fi
    link_dir "$src" "$shared"
    link_dir "$shared" "$HOME/.claude/skills/$n"
    if [ "$INSTALL_CODEX" -eq 1 ]; then link_dir "$shared" "$HOME/.codex/skills/$n"; fi
  done
fi

# ---- 4. Claude assets: agents / hooks (copied only if absent; settings.json untouched) ----
if [ "$INSTALL_CLAUDE" -eq 0 ]; then
  echo "skip   claude agents / hooks (--no-claude)"
else
  for sub in agents:md hooks:sh; do
    dir="${sub%%:*}"; ext="${sub##*:}"
    if [ "$dir" = agents ]; then sdir="$AGENTS_SRC"; else sdir="$AI_KIT_DIR/claude/hooks"; fi   # hooks are shared
    if [ ! -d "$sdir" ]; then echo "warn   source missing, skipped: $sdir"; continue; fi
    for f in "$sdir"/*."$ext"; do
      [ -f "$f" ] || continue
      case "$(basename "$f")" in *_test.sh) continue ;; esac   # test scripts are not installed
      mode=""; if [ "$dir" = hooks ]; then mode=exec; fi
      copy_if_absent "$f" "$HOME/.claude/$dir/$(basename "$f")" "$mode"
    done
  done
fi

# ---- 5. wrap-up ----
echo ""
echo "=============================================="
echo "ai-kit install finished. Next steps:"
echo "  1. Open a new terminal, or run: source \"$RC_FILE\""
echo "  2. Edit ~/.ai/AGENTS.md with your global personal preferences"
echo "  3. Hooks must be registered in ~/.claude/settings.json (this script does not edit it); snippet:"
echo "       $AI_KIT_DIR/claude/settings-snippet.json"
echo "  4. Mods: claude --plugin-dir \"$AI_KIT_DIR/mods\""
echo "  5. Run initai in any project root, or newproj <name> to create a project"
if [ "$LANG_OPT" != en ] && [ "$RC_FRESH" -eq 0 ]; then
  echo "  6. $RC_FILE was already set up and was not changed. For $LANG_OPT project templates,"
  echo "     add this line above the ai-kit source line: export AI_KIT_LANG=$LANG_OPT"
fi
echo "=============================================="
