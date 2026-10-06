#!/usr/bin/env bash
# PreToolUse guard for Claude Code (global, user scope).
#
# Reads the hook JSON on stdin. Exit 2 blocks the tool call and shows the
# stderr message to the model; any other exit lets the call proceed
# (fail-open on parse errors, since permissions.deny is a second layer).
#
# Blocks, deterministically, for Bash commands:
#   a. force push to main/master. A push is "forced" by --force, a single-dash
#      flag cluster containing f (e.g. -f, -uf, -fu) after the push token, or a
#      refspec with a leading '+' (e.g. +main, +HEAD:main). --force-with-lease is
#      NOT a force push. The target is the destination branch of an explicit
#      refspec when given, otherwise the current branch of the effective cwd (see
#      below). A refspec destination is the right side of ':', with a leading
#      refs/heads/ stripped and a bare HEAD mapped to the current branch.
#   b. --no-verify on git commit/push/merge, or -n on git commit
#   c. recursive rm whose target is /, ., .., *, /*, ~, $HOME, or the git repo root
#   d. recursive rm whose target ends in .next or contains /.next (a Next.js
#      build/dist directory, including .next-prefixed variants like
#      .next-verify) -- a dev server may be using it live
#   e. destructive git history/worktree commands: `git reset` with a standalone
#      --hard token after the subcommand, and `git clean` with --force or a
#      single-dash flag cluster containing f (-f, -fd, -fdx, -df, -xf). The
#      subcommand is the first non-option token after git; global options
#      between git and it are skipped, including the value of -C / -c /
#      --git-dir / --work-tree / --namespace / --config-env when
#      given as a separate token. git reset --soft / --mixed / <rev> / -- <file>,
#      git clean -n / --dry-run / bare git clean, and git stash are allowed.
#
# The command is split into sub-command segments on unquoted newlines and
# && || ; | and each segment is judged independently. Tokenization uses Python's shlex so shell quoting is
# honored: content inside quotes is a single argument and never participates in
# flag/branch matching (e.g. `git commit -m "fix: handle -n flag"` is allowed,
# and `git commit -m "a && rm -rf /"` is not split on the quoted &&). If shlex
# cannot parse the command (e.g. an unbalanced quote), it falls back to plain
# whitespace splitting, which errs toward blocking.
#
# Branch context: each segment carries an "effective cwd". A `cd <path>` segment
# updates it for the segments that follow; a `git -C <path>` overrides it for
# that one git invocation. Relative paths resolve against the hook's cwd. When
# the effective cwd cannot be resolved to a git repo, a force push with no
# explicit refspec is blocked (err toward blocking).
#
# Depends only on jq + python3 + git + bash builtins (kept bash 3.2 compatible).

set -u

# ---------------------------------------------------------------- read input
input="$(cat)"

tool_name="$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null)"
[ "$tool_name" = "Bash" ] || exit 0

command="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)"
[ -n "$command" ] || exit 0

cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)"
[ -n "$cwd" ] || cwd="$PWD"

block() { printf '%s\n' "$1" >&2; exit 2; }

home="$HOME"

# resolve a path (from `cd` or `git -C`) against the hook cwd; absolute as-is.
resolve_cwd() {
  case "$1" in
    /*) printf '%s' "$1" ;;
    *)  printf '%s' "$cwd/$1" ;;
  esac
}

is_main() { case "$1" in main|master) return 0 ;; *) return 1 ;; esac; }

# Destination branch of a push refspec: drop one leading '+', take the right side
# of ':' (the ref updated on the remote), strip a leading refs/heads/, and map a
# bare HEAD to the current branch. Args: <refspec> <current_branch>
refspec_dest() {
  local rs="$1" cur="$2" dst
  rs="${rs#+}"
  case "$rs" in
    *:*) dst="${rs#*:}" ;;
    *)   dst="$rs" ;;
  esac
  dst="${dst#refs/heads/}"
  [ "$dst" = "HEAD" ] && dst="$cur"
  printf '%s' "$dst"
}

# strip surrounding quotes and one trailing slash (keep bare "/")
clean_target() {
  local t="$1"
  t="${t%\"}"; t="${t#\"}"
  t="${t%\'}"; t="${t#\'}"
  if [ "$t" != "/" ]; then t="${t%/}"; fi
  printf '%s' "$t"
}

# true when a recursive-rm target is a dangerous standalone path or the repo
# root. base_cwd resolves relative targets; root is the effective cwd's repo root.
dangerous_target() {
  local raw="$1" base_cwd="$2" root="$3" t abs
  t="$(clean_target "$raw")"
  [ -n "$t" ] || return 1

  case "$t" in
    "/"|"."|".."|"*"|"/*") return 0 ;;
    "~"|'$HOME'|'${HOME}') return 0 ;;
  esac

  [ "$t" = "$home" ] && return 0

  if [ -n "$root" ]; then
    case "$t" in
      /*) abs="$t" ;;
      *)  abs="$base_cwd/$t" ;;
    esac
    abs="${abs%/}"
    [ "$abs" = "$root" ] && return 0
  fi
  return 1
}

# true when a recursive-rm target is (or is nested under, or is a
# same-prefix variant of) a Next.js build/dist directory: the target string
# ends in ".next", contains "/.next" anywhere (covers nested prefix variants
# like web/.next-9320), or is itself a bare ".next"-prefixed name with no
# path separator (e.g. ".next-verify").
dangerous_next_target() {
  local raw="$1" t
  t="$(clean_target "$raw")"
  [ -n "$t" ] || return 1
  case "$t" in
    *.next)    return 0 ;;
    */.next*)  return 0 ;;
    .next-*)   return 0 ;;
  esac
  return 1
}

# ------------------------------------------------------ per-segment analysis
# Judges one sub-command segment. The first argument is the segment's effective
# cwd (updated by preceding `cd` segments); the rest are its fully-parsed argv
# tokens (quotes removed), so flag and branch checks are exact token comparisons.
check_segment_argv() {
  local seg_cwd="$1"; shift
  local -a toks=("$@")
  local n=${#toks[@]}
  [ "$n" -gt 0 ] || return 0

  # ---- git subcommands -----------------------------------------------------
  local i git_idx=-1
  for ((i=0;i<n;i++)); do
    case "${toks[i]}" in git|*/git) git_idx=$i; break ;; esac
  done

  if [ "$git_idx" -ge 0 ]; then
    local has_commit=0 has_push=0 has_merge=0 push_idx=-1
    for ((i=git_idx+1;i<n;i++)); do
      case "${toks[i]}" in
        commit) has_commit=1 ;;
        push)   has_push=1; [ "$push_idx" -lt 0 ] && push_idx=$i ;;
        merge)  has_merge=1 ;;
      esac
    done

    # (e) destructive reset / clean. Find the real subcommand: the first token
    # after git that is not a global option (or the value of one that takes a
    # separate argument, e.g. -C <path>, -c <k=v>).
    local sub_idx=-1
    for ((i=git_idx+1;i<n;i++)); do
      case "${toks[i]}" in
        -C|-c|--git-dir|--work-tree|--namespace|--config-env)
          i=$((i+1)) ;;
        -*) : ;;
        *)  sub_idx=$i; break ;;
      esac
    done
    if [ "$sub_idx" -ge 0 ]; then
      local destructive=0
      case "${toks[sub_idx]}" in
        reset)
          for ((i=sub_idx+1;i<n;i++)); do
            [ "${toks[i]}" = "--hard" ] && destructive=1
          done
          ;;
        clean)
          for ((i=sub_idx+1;i<n;i++)); do
            case "${toks[i]}" in
              --force) destructive=1 ;;
              --*)     : ;;
              -*)      case "${toks[i]}" in *f*) destructive=1 ;; esac ;;
            esac
          done
          ;;
      esac
      if [ "$destructive" -eq 1 ]; then
        block "Blocked by global guard: git reset --hard / git clean -f is blocked because it discards uncommitted or committed work. If it is really needed, ask the user to run it in their terminal with the ! prefix."
      fi
    fi

    # (b) bypassing verification hooks
    if [ $((has_commit + has_push + has_merge)) -gt 0 ]; then
      for ((i=0;i<n;i++)); do
        if [ "${toks[i]}" = "--no-verify" ]; then
          block "Blocked by global guard: --no-verify bypasses git verification hooks and is not allowed."
        fi
      done
    fi
    if [ "$has_commit" -eq 1 ]; then
      for ((i=0;i<n;i++)); do
        if [ "${toks[i]}" = "-n" ]; then
          block "Blocked by global guard: git commit -n bypasses the pre-commit hook and is not allowed."
        fi
      done
    fi

    # (a) force push to main/master
    if [ "$has_push" -eq 1 ]; then
      # A push is forced by --force, or a single-dash flag cluster containing
      # 'f' (e.g. -f, -uf, -fu) appearing AFTER the push token. --force-with-lease
      # and other long options, and non-f clusters (e.g. -n), do not force. The
      # scan is limited to after push_idx so tokens elsewhere in the segment
      # (e.g. an earlier `rm -rf`) never register as a force flag.
      local forced=0
      for ((i=push_idx+1;i<n;i++)); do
        case "${toks[i]}" in
          --force) forced=1 ;;
          --*)     : ;;
          -*)      case "${toks[i]}" in *f*) forced=1 ;; esac ;;
        esac
      done

      # positionals after 'push' (non-option tokens): remote and refspec(s)
      local -a positionals=()
      for ((i=push_idx+1;i<n;i++)); do
        case "${toks[i]}" in
          -*) : ;;
          *)  positionals+=("${toks[i]}") ;;
        esac
      done

      # current branch: from the repo at `git -C <path>` when given (last one
      # wins, resolved against the hook cwd), else the effective cwd. Needed to
      # resolve a bare HEAD refspec and the remote-only / no-refspec case.
      local git_cwd="$seg_cwd" ci
      for ((ci=git_idx+1;ci<n;ci++)); do
        case "${toks[ci]}" in
          commit|push|merge) break ;;
        esac
        if [ "${toks[ci]}" = "-C" ] && [ $((ci+1)) -lt "$n" ]; then
          git_cwd="$(resolve_cwd "${toks[ci+1]}")"
          ci=$((ci+1))
        fi
      done
      local current_branch
      current_branch="$(git -C "$git_cwd" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"

      # A refspec with a leading '+' is itself a forced update, regardless of any
      # flag. Block when its destination branch is main/master.
      local rs target
      if [ "${#positionals[@]}" -gt 0 ]; then
        for rs in "${positionals[@]}"; do
          case "$rs" in
            +*)
              target="$(refspec_dest "$rs" "$current_branch")"
              if is_main "$target"; then
                block "Blocked by global guard: force push to the main / master branch is not allowed."
              fi
              ;;
          esac
        done
      fi

      if [ "$forced" -eq 1 ]; then
        local pcount=${#positionals[@]}
        if [ "$pcount" -ge 2 ]; then
          # positionals[0] is the remote; the rest are refspecs. Block when any
          # refspec destination is main/master.
          local pi
          for ((pi=1; pi<pcount; pi++)); do
            target="$(refspec_dest "${positionals[pi]}" "$current_branch")"
            if is_main "$target"; then
              block "Blocked by global guard: force push to the main / master branch is not allowed."
            fi
          done
        else
          # 0 or 1 positional (nothing / remote only) -> current branch decides.
          if is_main "$current_branch"; then
            block "Blocked by global guard: the current branch is $current_branch; force push to main / master is not allowed."
          elif [ -z "$current_branch" ]; then
            block "Blocked by global guard: cannot determine the target repository branch (path does not exist or is not a git repository); force push is blocked by the fail-safe policy."
          fi
        fi
      fi
    fi
  fi

  # ---- dangerous recursive rm ---------------------------------------------
  local rm_idx=-1
  for ((i=0;i<n;i++)); do
    if [ "${toks[i]}" = "rm" ]; then rm_idx=$i; break; fi
  done
  if [ "$rm_idx" -ge 0 ]; then
    local recursive=0 j tk repo_root
    repo_root="$(git -C "$seg_cwd" rev-parse --show-toplevel 2>/dev/null || true)"
    local -a targets=()
    for ((j=rm_idx+1;j<n;j++)); do
      tk="${toks[j]}"
      case "$tk" in
        --)          : ;;
        --recursive) recursive=1 ;;
        --*)         : ;;
        -*)          case "$tk" in *[rR]*) recursive=1 ;; esac ;;
        *)           targets+=("$tk") ;;
      esac
    done
    if [ "$recursive" -eq 1 ] && [ "${#targets[@]}" -gt 0 ]; then
      for tk in "${targets[@]}"; do
        [ -n "$tk" ] || continue
        if dangerous_target "$tk" "$seg_cwd" "$repo_root"; then
          block "Blocked by global guard: recursive deletion of dangerous path '$tk' is not allowed."
        fi
        if dangerous_next_target "$tk"; then
          block "guard: refusing recursive rm of a Next.js .next directory (dev server may be using it); stop the dev server and mv it instead"
        fi
      done
    fi
  fi

  return 0
}

# ------------------------------------------- dispatch one segment (or cd shift)
# A `cd <path>` segment updates the shared seg_cwd for later segments; any other
# segment is judged with the current seg_cwd. seg_cwd is read/written via the
# global GUARD_SEG_CWD so the two tokenizer paths can share this logic.
dispatch_segment() {
  if [ "$1" = "cd" ] && [ "$#" -ge 2 ]; then
    GUARD_SEG_CWD="$(resolve_cwd "$2")"
  else
    check_segment_argv "$GUARD_SEG_CWD" "$@"
  fi
}

# --------------------------------------------- tokenize + split into segments
# Python emits, NUL-separated: a status field ("OK" or "FAIL"), then, when OK,
# the flat token list with the shell operators && || ; | preserved as their own
# tokens. Quoting is honored, so operators inside quotes are not tokenized as
# separators. On any parse failure (unbalanced quote) status is "FAIL".
#
# shlex with punctuation_chars treats a bare newline as ordinary whitespace, so
# it would flatten a multi-line command into one argv. To keep each line its own
# segment we walk the tokens with position tracking (lx.instream.tell()): the
# whitespace separating two tokens is everything between the end of one token's
# raw text and the start of the next, i.e. the single terminating char captured
# after the previous token (pending_term) plus the leading whitespace of the
# current token's region. If that separator contains an unquoted '\n' we emit a
# ';' token, putting newlines at the same level as ; && || |. A newline inside
# quotes lives inside the token's raw text (never in the separator), so it is
# preserved as part of the argument and does not split.
PY='
import shlex, sys, os
c = os.environ.get("GUARD_CMD", "")
out = []
last_after = 0
pending_term = ""
try:
    lx = shlex.shlex(c, posix=True, punctuation_chars=True)
    lx.whitespace_split = True
    while True:
        tok = lx.get_token()
        after = lx.instream.tell()
        if tok is lx.eof:          # posix mode: eof is None
            break
        region = c[last_after:after]
        lead = region[:len(region) - len(region.lstrip())]
        if out and "\n" in (pending_term + lead):
            out.append(";")
        out.append(tok)
        pending_term = region[-1:] if (region and region[-1:].isspace()) else ""
        last_after = after
except ValueError:
    sys.stdout.write("FAIL\x00")
    sys.exit(0)
sys.stdout.write("\x00".join(["OK"] + out) + "\x00")
'

# Runs the shlex-based path. Returns non-zero to request the whitespace fallback
# (python3 missing, produced no output, or reported a parse failure).
run_shlex_path() {
  local status="" first=1
  local -a flat=()
  while IFS= read -r -d '' field; do
    if [ "$first" -eq 1 ]; then status="$field"; first=0; else flat+=("$field"); fi
  done < <(GUARD_CMD="$command" python3 -c "$PY" 2>/dev/null)

  [ "$first" -eq 0 ] || return 1        # no output at all -> fallback
  [ "$status" = "OK" ] || return 1      # shlex parse failure -> fallback
  [ "${#flat[@]}" -gt 0 ] || return 0   # parsed to nothing -> nothing to check

  GUARD_SEG_CWD="$cwd"
  local -a seg=()
  local t
  for t in "${flat[@]}"; do
    case "$t" in
      "&&"|"||"|";"|"|")
        [ "${#seg[@]}" -gt 0 ] && dispatch_segment "${seg[@]}"
        seg=()
        ;;
      *)
        seg+=("$t")
        ;;
    esac
  done
  [ "${#seg[@]}" -gt 0 ] && dispatch_segment "${seg[@]}"
  return 0
}

# Fallback: plain whitespace splitting (used only when shlex cannot parse).
# Whitespace-split tokens make flag/branch matching over-inclusive, i.e. it errs
# toward blocking, which is the desired direction on ambiguous input.
run_fallback_path() {
  local nl=$'\n' work seg
  local -a ftoks=()
  GUARD_SEG_CWD="$cwd"
  work="$command"
  work="${work//&&/$nl}"
  work="${work//||/$nl}"
  work="${work//;/$nl}"
  work="${work//|/$nl}"
  while IFS= read -r seg; do
    seg="${seg#"${seg%%[![:space:]]*}"}"
    seg="${seg%"${seg##*[![:space:]]}"}"
    [ -n "$seg" ] || continue
    ftoks=()
    read -ra ftoks <<< "$seg"
    [ "${#ftoks[@]}" -gt 0 ] && dispatch_segment "${ftoks[@]}"
  done <<< "$work"
}

GUARD_SEG_CWD="$cwd"
if ! run_shlex_path; then
  run_fallback_path
fi

exit 0
