#!/usr/bin/env bash
# ai-kit.sh —— AI 工程协作工具的 shell 函数集(bash + zsh 通用)
#
# 不要把本文件内容拷进 rc 文件。
# install.sh 会自动在你的 ~/.zshrc 或 ~/.bashrc 写入一行 source 本文件。
# 逻辑的唯一事实源是本文件;rc 文件只做薄接入层。

# ---- 路径配置:本文件相对自身定位 ai-kit 根目录,无需手填 ----
if [ -n "$ZSH_VERSION" ]; then
  # zsh: ${(%):-%x} 取「当前被 source 的文件路径」
  AI_KIT_DIR="${${(%):-%x}:A:h:h}"
else
  # bash 及兼容 shell
  AI_KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi
export AI_KIT_DIR

# ============================================================
# newproj <项目名> [父目录]
#   新建工程统一入口:建目录 + git init + .gitignore + .ai 体系。
#   跑完自动停在新项目目录里。父目录默认 $AI_KIT_PROJECTS_DIR 或 ~/Projects。
# ============================================================
newproj() {
  if [ -z "$1" ]; then
    echo "用法: newproj <项目名> [父目录]"
    return 1
  fi
  bash "$AI_KIT_DIR/scripts/newproj.sh" "$@" || return 1
  # 脚本在子进程里 cd 不影响当前 shell,这里再 cd 一次
  local parent="${2:-${AI_KIT_PROJECTS_DIR:-$HOME/Projects}}"
  cd "$parent/$1" 2>/dev/null || true
}

# ============================================================
# initai
#   在「已存在的」项目里补铺 .ai 体系(不建目录、不碰 git)。
# ============================================================
initai() {
  bash "$AI_KIT_DIR/scripts/init-ai.sh"
}

# ============================================================
# checkgit [目录]
#   体检:列出某目录下还没 git 化的子项目。默认扫 $AI_KIT_PROJECTS_DIR 或 ~/Projects。
# ============================================================
checkgit() {
  local base="${1:-${AI_KIT_PROJECTS_DIR:-$HOME/Projects}}"
  local found=0
  for dir in "$base"/*/; do
    if [ ! -d "$dir/.git" ]; then
      echo "未初始化: $dir"
      found=1
    fi
  done
  [ "$found" -eq 0 ] && echo "全部已 git 化: $base"
}
