#!/usr/bin/env bash
# Test suite for guard.sh. Feeds hook JSON on stdin and asserts the exit code.
# Usage: bash ~/.claude/hooks/guard_test.sh

set -u

HOOK="$(cd "$(dirname "$0")" && pwd)/guard.sh"

# throwaway git repo on branch main, one commit, no remote
REPO="$(mktemp -d)"
git -C "$REPO" init -q
git -C "$REPO" symbolic-ref HEAD refs/heads/main
git -C "$REPO" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
REPO="$(git -C "$REPO" rev-parse --show-toplevel)"   # canonical path

pass=0
fail=0

# run <expected_exit> <tool_name> <command> [cwd]
run() {
  local exp="$1" tool="$2" cmd="$3" cwd="${4:-$REPO}" got
  local json
  json="$(jq -n --arg t "$tool" --arg c "$cmd" --arg d "$cwd" \
    '{tool_name:$t, tool_input:{command:$c}, cwd:$d}')"
  printf '%s' "$json" | bash "$HOOK" >/dev/null 2>&1
  got=$?
  if [ "$got" -eq "$exp" ]; then
    printf 'PASS  exit=%s  %s\n' "$got" "$cmd"
    pass=$((pass+1))
  else
    printf 'FAIL  expected=%s got=%s  %s\n' "$exp" "$got" "$cmd"
    fail=$((fail+1))
  fi
}

# --- force push -------------------------------------------------------------
run 0 Bash 'git push --force-with-lease origin main'   # force-with-lease always allowed
run 0 Bash 'git push --force origin feature-x'         # force to explicit non-main branch
run 2 Bash 'git push -f origin main'                   # force to explicit main
run 2 Bash 'git push --force origin master'            # force to explicit master
run 2 Bash 'git push -f'                               # no branch, current=main
run 2 Bash 'git push -f origin'                        # remote only, current=main
run 2 Bash 'cd sub && git push -f'                     # judged by current branch (main)
run 0 Bash 'git push origin main'                      # non-force push to main is fine

# --- verification hooks -----------------------------------------------------
run 2 Bash 'git commit --no-verify -m x'
run 2 Bash 'git commit -n -m x'
run 2 Bash 'npm test && git commit --no-verify -m x'  # in a compound command
run 2 Bash 'git merge --no-verify feature'
run 0 Bash 'git commit -m "normal message"'

# --- dangerous rm -----------------------------------------------------------
run 0 Bash 'rm -rf ./build'
run 2 Bash 'rm -rf .'
run 2 Bash 'rm -rf /'
run 2 Bash 'rm -rf ~'
run 2 Bash 'rm -rf $HOME'                              # literal $HOME (single-quoted here)
run 2 Bash 'rm -rf ..'
run 2 Bash 'rm -rf *'
run 2 Bash "rm -rf $REPO"                              # equals git repo root
run 0 Bash 'rm -rf node_modules'
run 0 Bash 'rm file.txt'                               # not recursive

# --- non-Bash / benign ------------------------------------------------------
run 0 Read 'anything'                                  # not a Bash tool
run 0 Bash 'ls -la'
run 0 Bash 'git status'

# --- shell quoting (flags/operators inside quotes are data, not args) --------
run 0 Bash 'git commit -m "fix: handle -n flag"'       # -n inside message
run 0 Bash 'git commit -m "do not use --no-verify"'    # --no-verify inside message
run 0 Bash 'git commit -m "a && rm -rf /"'             # && / rm inside message
run 2 Bash 'git commit -n -m "x"'                      # real -n flag still blocked
run 0 Bash 'echo "git push -f origin main"'            # whole git command quoted
run 2 Bash 'git push -f origin main # comment'         # trailing comment, real force push

# --- combined short options -------------------------------------------------
run 2 Bash 'git push -uf origin main'                  # -uf cluster contains f -> force to main
run 2 Bash 'git push -fu origin main'                  # -fu cluster contains f -> force to main
run 0 Bash 'git push -u origin main'                   # -u has no f -> not a force push
run 0 Bash 'git push -uf origin feature-x'             # force to explicit non-main branch

# --- refspec '+' prefix -----------------------------------------------------
run 2 Bash 'git push origin +main'                     # +main is a forced update to main
run 2 Bash 'git push origin +HEAD:main'                # dest side of ':' is main
run 0 Bash 'git push origin +feature-x'                # forced update to non-main branch
run 0 Bash 'git push origin main:+x'                   # '+' not at token start -> not a refspec force

# --- git -C / cd branch context ---------------------------------------------
# Two throwaway repos: A on feature-x, B on main. Hook cwd is A for all three.
REPO_A="$(mktemp -d)"
git -C "$REPO_A" init -q
git -C "$REPO_A" symbolic-ref HEAD refs/heads/feature-x
git -C "$REPO_A" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
REPO_A="$(git -C "$REPO_A" rev-parse --show-toplevel)"

REPO_B="$(mktemp -d)"
git -C "$REPO_B" init -q
git -C "$REPO_B" symbolic-ref HEAD refs/heads/main
git -C "$REPO_B" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
REPO_B="$(git -C "$REPO_B" rev-parse --show-toplevel)"

run 2 Bash "git -C $REPO_B push -f" "$REPO_A"          # -C repo is on main -> block
run 0 Bash "git -C $REPO_A push -f" "$REPO_A"          # -C repo is on feature-x -> allow
run 2 Bash "cd $REPO_B && git push -f" "$REPO_A"       # cd into main repo -> block

# --- refs/heads/ prefix + HEAD refspec --------------------------------------
run 2 Bash 'git push -f origin refs/heads/main'        # dest strips refs/heads/ -> main
run 0 Bash 'git push -f origin refs/heads/feature-x'   # dest strips refs/heads/ -> feature-x
run 2 Bash 'git push -f origin HEAD'                    # HEAD -> current branch (main)
run 0 Bash 'git push -f origin HEAD' "$REPO_A"          # HEAD -> current branch (feature-x)
run 2 Bash 'git push -f origin HEAD:main'               # dest side of ':' is main

# --- git by absolute path ---------------------------------------------------
run 2 Bash '/usr/bin/git push -f origin main'          # basename is git -> force push detected

# --- newline as segment separator -------------------------------------------
run 2 Bash $'git push -f\necho done'                   # seg1 forces to current main -> block
run 2 Bash $'git push -f\nls -la foo bar'              # trailing line words never join seg1
run 0 Bash $'rm -rf ./build\ngit push origin main'     # rm -rf x isolated; push is non-force
run 0 Bash $'echo main\ngit push -f origin feature-x'  # literal main on its own line, force->feature-x
run 0 Bash $'git commit -m "line1\nline2"'             # real newline inside quotes -> one arg, allowed

# --- regression: force flag scoped to its own segment -----------------------
run 0 Bash 'rm -rf ./build && git push origin main'    # no force in the push segment

# --- (e) destructive git reset / clean --------------------------------------
# Only fed to the hook as JSON; none of these commands is actually executed.
run 2 Bash 'git reset --hard'
run 2 Bash 'git reset --hard HEAD~1'
run 2 Bash 'git reset --hard origin/main'
run 2 Bash "git -C $REPO_A reset --hard" "$REPO_B"      # -C <path> skipped to find subcommand
run 2 Bash 'git -c core.x=y reset --hard'              # -c k=v skipped to find subcommand
run 2 Bash 'npm test && git reset --hard HEAD~1'       # in a compound command
run 2 Bash 'git clean -f'
run 2 Bash 'git clean -fd'
run 2 Bash 'git clean -fdx'
run 2 Bash 'git clean -df'
run 2 Bash 'git clean -xf'
run 2 Bash 'git clean --force'
run 0 Bash 'git reset --soft HEAD~1'
run 0 Bash 'git reset --mixed HEAD~1'
run 0 Bash 'git reset HEAD~1'
run 0 Bash 'git reset -- file.txt'
run 0 Bash 'git clean -n'
run 0 Bash 'git clean --dry-run'
run 0 Bash 'git clean'                                 # no -f: git refuses by itself
run 0 Bash 'git clean -e foo -n'                       # -e value has an f but is not a flag
run 0 Bash 'git stash'
run 0 Bash 'git commit -m "guard: block reset --hard"' # --hard inside quoted message
run 0 Bash 'echo "git clean -fd"'                      # whole command quoted
run 0 Bash 'git log --format=%H -- reset'              # subcommand is log, not reset

echo "----"
echo "passed=$pass failed=$fail"
rm -rf "$REPO" "$REPO_A" "$REPO_B"
[ "$fail" -eq 0 ]
