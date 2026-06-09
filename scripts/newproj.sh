#!/bin/bash
# newproj.sh —— 新建工程的统一入口
#
# 作用:把"建目录 + git init + .gitignore + 铺 .ai/ 体系"打包成一个
#       不可分割的入口动作,消除"新建工程漏掉某步"的可能。
#
# 边界:本脚本只搭骨架,绝不执行 git commit / tag / push。
#       第一个 commit 由你在检查内容后主动发起。
#
# 用法:newproj <项目名> [父目录]
#   newproj my-robot                  -> 在默认父目录下创建
#   newproj my-robot ~/Projects/work  -> 指定父目录
#
# 幂等:目录已存在则进入而不重建;git / 文件已存在则跳过。

set -e

# ---- 路径自动推导:无需手改 ----
# 父目录可用环境变量 AI_KIT_PROJECTS_DIR 覆盖,默认 ~/Projects。
AI_KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_PARENT="${AI_KIT_PROJECTS_DIR:-$HOME/Projects}"
AI_KIT_INIT="$AI_KIT_DIR/scripts/init-ai.sh"

NAME="$1"
PARENT="${2:-$DEFAULT_PARENT}"

if [ -z "$NAME" ]; then
  echo "用法: newproj <项目名> [父目录]"
  exit 1
fi

PROJECT_DIR="$PARENT/$NAME"

# ---- 1. 建目录并进入(已存在则直接进入,不重建)----
if [ -d "$PROJECT_DIR" ]; then
  echo "目录已存在: $PROJECT_DIR —— 在其上继续初始化(不会覆盖文件)"
else
  mkdir -p "$PROJECT_DIR"
  echo "create $PROJECT_DIR"
fi
cd "$PROJECT_DIR"

# ---- 2. git init(建空仓库,无副作用;不 commit)----
if [ -d .git ]; then
  echo "skip   git init (.git 已存在)"
else
  git init -q
  echo "create .git (空仓库,尚无 commit)"
fi

# ---- 3. .gitignore —— 已存在则不覆盖,只补缺失行 ----
ensure_line() {
  local line="$1" file=".gitignore"
  touch "$file"
  grep -qxF "$line" "$file" || echo "$line" >> "$file"
}

# OS 垃圾文件
# 注:若已配全局 ~/.gitignore_global,可删掉这一段(见随附说明)。
ensure_line ".DS_Store"
ensure_line "._*"
ensure_line "Thumbs.db"
ensure_line "desktop.ini"

# 编辑器 / IDE
ensure_line ".vscode/"
ensure_line ".idea/"
ensure_line "*.swp"
ensure_line "*~"

# 密钥 / 环境变量(安全关键,务必保留)
ensure_line ".env"
ensure_line ".env.local"
ensure_line ".env.*.local"
ensure_line "*.pem"
ensure_line "*.key"

# 日志 / 临时
ensure_line "*.log"
ensure_line "logs/"
ensure_line "tmp/"
ensure_line ".cache/"

echo "ready  .gitignore (通用基础)"
echo "       技术栈专属规则待栈确定后,从 github/gitignore 官方模板按需追加,例如:"
echo "       curl -sL https://raw.githubusercontent.com/github/gitignore/main/Python.gitignore >> .gitignore"

# ---- 4. 铺设 AI 协作体系(委托给 init-ai.sh)----
if [ -f "$AI_KIT_INIT" ]; then
  echo ""
  echo "--- 铺设 .ai/ 体系 ---"
  bash "$AI_KIT_INIT"
else
  echo "warn   未找到 init-ai.sh: $AI_KIT_INIT"
  echo "       请检查脚本顶部的 AI_KIT_INIT 路径配置。"
fi

# ---- 5. 收尾提示 —— 下一步由你手动做 ----
echo ""
echo "=============================================="
echo "项目骨架就绪: $PROJECT_DIR"
echo ""
echo "已完成(自动): 目录 / git 空仓库 / .gitignore / .ai 体系"
echo "待你手动:"
echo "  1. 编辑 AGENTS.md 填入项目简介与构建命令"
echo "  2. 技术栈确定后,按需追加官方 gitignore 模板(见上方提示)"
echo "  3. 内容确认无误后,自行发起首个 commit:"
echo "       git add -A && git commit -m \"chore: scaffold project\""
echo "  (git commit / tag / push 一律由你主动发起,脚本不代劳)"
echo "=============================================="