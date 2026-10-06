#!/bin/bash
# newproj.sh -- single entry point for creating a project
#
# Purpose: bundle "mkdir + git init + .gitignore + .ai/ files" into one
#          atomic step so no setup step gets forgotten.
#
# Scope: scaffolding only; never runs git commit / tag / push.
#        You make the first commit after reviewing the content.
#
# Usage: newproj <name> [parent-dir]
#   newproj my-robot                  -> create under the default parent dir
#   newproj my-robot ~/Projects/work  -> explicit parent dir
#
# Idempotent: an existing dir is reused; existing git / files are skipped.

set -e

# ---- paths are derived automatically ----
# Override the parent dir with AI_KIT_PROJECTS_DIR (default ~/Projects).
AI_KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_PARENT="${AI_KIT_PROJECTS_DIR:-$HOME/Projects}"
AI_KIT_INIT="$AI_KIT_DIR/scripts/init-ai.sh"

NAME="$1"
PARENT="${2:-$DEFAULT_PARENT}"

# The name must be a single directory name: no "/", not "." / "..", not
# starting with "-", not empty or blank. Otherwise an absolute path passed
# as the name would be created under the default parent dir.
NAME_OK=1
case "$NAME" in */*|.|..|-*|*$'\n'*) NAME_OK=0 ;; esac
[ -n "$(printf '%s' "$NAME" | tr -d '[:space:]')" ] || NAME_OK=0
if [ "$NAME_OK" -eq 0 ]; then
  echo "error  project name must be a single directory name (got: $NAME); pass the location as the second argument: newproj <name> <parent-dir>" >&2
  exit 1
fi

PROJECT_DIR="$PARENT/$NAME"

# ---- 1. create and enter the dir (reuse if it exists)----
if [ -d "$PROJECT_DIR" ]; then
  echo "dir exists: $PROJECT_DIR -- continuing setup there (no files overwritten)"
else
  mkdir -p "$PROJECT_DIR"
  echo "create $PROJECT_DIR"
fi
cd "$PROJECT_DIR"

# ---- 2. git init (empty repo, no commit)----
if [ -d .git ]; then
  echo "skip   git init (.git exists)"
else
  git init -q
  echo "create .git (empty repo, no commits yet)"
fi

# ---- 3. .gitignore -- never overwritten; only missing lines are appended ----
ensure_line() {
  local line="$1" file=".gitignore"
  touch "$file"
  grep -qxF "$line" "$file" || echo "$line" >> "$file"
}

# OS junk files
# Note: drop this block if you use a global ~/.gitignore_global.
ensure_line ".DS_Store"
ensure_line "._*"
ensure_line "Thumbs.db"
ensure_line "desktop.ini"

# Editors / IDEs
ensure_line ".vscode/"
ensure_line ".idea/"
ensure_line "*.swp"
ensure_line "*~"

# Secrets / env files (security critical, keep these)
ensure_line ".env"
ensure_line ".env.local"
ensure_line ".env.*.local"
ensure_line "*.pem"
ensure_line "*.key"

# Logs / temp
ensure_line "*.log"
ensure_line "logs/"
ensure_line "tmp/"
ensure_line ".cache/"

echo "ready  .gitignore (generic baseline)"
echo "       Once the stack is chosen, append rules from the github/gitignore templates, e.g.:"
echo "       curl -sL https://raw.githubusercontent.com/github/gitignore/main/Python.gitignore >> .gitignore"

# ---- 4. AI collaboration files (delegated to init-ai.sh)----
if [ -f "$AI_KIT_INIT" ]; then
  echo ""
  echo "--- setting up .ai/ ---"
  bash "$AI_KIT_INIT"
else
  echo "warn   init-ai.sh not found: $AI_KIT_INIT"
  echo "       Check the AI_KIT_INIT path at the top of this script."
fi

# ---- 5. wrap-up -- the remaining steps are manual ----
echo ""
echo "=============================================="
echo "project scaffold ready: $PROJECT_DIR"
echo ""
echo "Done automatically: dir / empty git repo / .gitignore / .ai files"
echo "Your next steps:"
echo "  1. Edit AGENTS.md with the project overview and build commands"
echo "  2. Once the stack is chosen, append the official gitignore template (see above)"
echo "  3. After reviewing, make the first commit yourself:"
echo "       git add -A && git commit -m \"chore: scaffold project\""
echo "  (git commit / tag / push are always yours to run; this script never does them)"
echo "=============================================="