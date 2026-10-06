#!/usr/bin/env bash
# ai-kit.sh -- shell functions for AI-assisted project work (bash + zsh)
#
# Do not copy this file into your rc file.
# install.sh adds one line to ~/.zshrc or ~/.bashrc that sources this file.
# This file is the single source of truth; the rc file is only a thin hook.

# ---- paths: the ai-kit root is located relative to this file, nothing to fill in ----
if [ -n "$ZSH_VERSION" ]; then
  # zsh: ${(%):-%x} gives the path of the file being sourced
  AI_KIT_DIR="${${(%):-%x}:A:h:h}"
else
  # bash and compatible shells
  AI_KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi
export AI_KIT_DIR

# ============================================================
# newproj <name> [parent-dir]
#   single entry point for a new project: mkdir + git init + .gitignore + .ai files.
#   Leaves you in the new project dir. Parent defaults to $AI_KIT_PROJECTS_DIR or ~/Projects.
# ============================================================
newproj() {
  if [ -z "$1" ]; then
    echo "Usage: newproj <name> [parent-dir]"
    return 1
  fi
  bash "$AI_KIT_DIR/scripts/newproj.sh" "$@" || return 1
  # the script cd-s in a subprocess, which does not affect this shell; cd again here
  local parent="${2:-${AI_KIT_PROJECTS_DIR:-$HOME/Projects}}"
  cd "$parent/$1" 2>/dev/null || true
}

# ============================================================
# initai
#   add the .ai files to an existing project (no mkdir, no git).
# ============================================================
initai() {
  bash "$AI_KIT_DIR/scripts/init-ai.sh"
}

# ============================================================
# checkgit [dir]
#   list subdirectories that are not git repos yet. Defaults to $AI_KIT_PROJECTS_DIR or ~/Projects.
# ============================================================
checkgit() {
  local base="${1:-${AI_KIT_PROJECTS_DIR:-$HOME/Projects}}"
  local found=0 dir
  [ -n "$ZSH_VERSION" ] && setopt localoptions nullglob
  for dir in "$base"/*/; do
    [ -d "$dir" ] || continue
    if [ ! -d "$dir/.git" ]; then
      echo "not a git repo: $dir"
      found=1
    fi
  done
  [ "$found" -eq 0 ] && echo "all are git repos: $base"
}
