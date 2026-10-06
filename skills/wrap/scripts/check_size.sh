#!/usr/bin/env bash
# check_size.sh -- deterministic size/structure checker for /wrap.
#
# Run from the project root (reads .ai/PROGRESS.md under cwd by default), or pass a directory:
#     bash check_size.sh [PROJECT_ROOT]
#
# Prints every item with an OK / OVER verdict; any limit exceeded or structure drift -> exit 1.
#
# ---- Rules (numbers and section names live here only; SKILL.md refers to this script) ----
# Limits:
#   PROGRESS total lines (wc -l)                           <= 120
#   "Current status" non-blank, non-comment content lines  <= 10
#   "Progress log" entries (list items)                    <= 10
# Structure: exactly the six template sections, each once; none missing, none duplicated,
# no extra top-level ## section. Each logical section is recognized in English or Chinese:
#   Current status                          / 当前状态
#   Next steps                              / 下一步
#   Task list                               / 任务清单
#   Open issues                             / 遗留 (actual title: 遗留 / 待澄清)
#   User corrections (pending distillation) / 用户纠正 (actual title: 用户纠正（待蒸馏）)
#   Progress log                            / 进度日志
# Matching is by keyword; English is case-insensitive and tolerates extra whitespace.
# A logical section appearing twice (same language, or once in each language) is a duplicate.
# How to fix OVER/DRIFT: see the "Size / structure check" step in SKILL.md.
#
# Compatibility: macOS stock bash 3.2 + BSD/one-true awk, BSD sed/grep.

set -u

MAX_TOTAL=120
MAX_CUR=10
MAX_LOG=10

ROOT="${1:-.}"
PROGRESS="$ROOT/.ai/PROGRESS.md"

echo "=================================================="
echo " wrap size check"
echo " file: $PROGRESS"
echo "=================================================="

if [ ! -f "$PROGRESS" ]; then
  echo "  (file not found -- create .ai/PROGRESS.md from the template first)"
  exit 1
fi

TOTAL=$(wc -l < "$PROGRESS" | tr -d ' ')

# Single awk pass: Current status content lines, Progress log entries,
# per-section occurrence counts, list of extra sections.
OUT=$(LC_ALL=C awk '
  function hit(key) { sec=key; cnt[key]++ }
  BEGIN { inc=0; sec="" }
  {
    line=$0
    if (substr(line,1,3)=="## ") {
      inc=0
      # English names: exact match after normalizing (trim, collapse spaces,
      # lowercase, full-width parens -> ASCII, no spaces around parens).
      # Chinese names: substring match (unchanged).
      en=tolower(substr(line,4)); gsub(/[ \t\r]+/, " ", en); sub(/^ /, "", en); sub(/ $/, "", en)
      gsub(/（/, "(", en); gsub(/）/, ")", en); gsub(/ ?\( ?/, "(", en); gsub(/ ?\) ?/, ")", en)
      if      (index(line,"当前状态")>0 || en=="current status")   hit("cur")
      else if (index(line,"下一步")>0   || en=="next steps")       hit("next")
      else if (index(line,"任务清单")>0 || en=="task list")        hit("tasks")
      else if (index(line,"遗留")>0     || en=="open issues")      hit("legacy")
      else if (index(line,"用户纠正")>0 || en=="user corrections" || en=="user corrections(pending distillation)") hit("corr")
      else if (index(line,"进度日志")>0 || en=="progress log")     hit("log")
      else { sec="extra"; print "EXTRA " substr(line,4) }
      next
    }
    if (sec=="cur") {
      if (line ~ /^[ \t]*$/) next
      if (inc) { if (index(line,"-->")>0) inc=0; next }
      if (index(line,"<!--")>0) { if (index(line,"-->")==0) inc=1; next }
      curcount++
    } else if (sec=="log") {
      if (line ~ /^[ \t]*[-*+][ \t]/) logcount++
    }
  }
  END {
    print "CUR " curcount+0
    print "LOG " logcount+0
    print "SEC cur "    cnt["cur"]+0
    print "SEC next "   cnt["next"]+0
    print "SEC tasks "  cnt["tasks"]+0
    print "SEC legacy " cnt["legacy"]+0
    print "SEC corr "   cnt["corr"]+0
    print "SEC log "    cnt["log"]+0
  }
' "$PROGRESS")

getval() { echo "$OUT" | awk -v k="$1" '$1==k{print $2}'; }
getsec() { echo "$OUT" | awk -v k="$1" '$1=="SEC" && $2==k{print $3}'; }

CUR=$(getval CUR); LOG=$(getval LOG)
S_CUR=$(getsec cur); S_NEXT=$(getsec next); S_TASKS=$(getsec tasks)
S_LEGACY=$(getsec legacy); S_CORR=$(getsec corr); S_LOG=$(getsec log)
EXTRAS=$(echo "$OUT" | sed -n 's/^EXTRA //p')

FAIL=0
# st only echoes OK/OVER and never touches globals (a FAIL change inside $() would be lost);
# FAIL is decided in the parent shell.
st() { if [ "$1" -le "$2" ]; then echo "OK"; else echo "OVER"; fi; }

ST_TOTAL=$(st "$TOTAL" "$MAX_TOTAL"); [ "$ST_TOTAL" = OK ] || FAIL=1
ST_CUR=$(st "$CUR" "$MAX_CUR");       [ "$ST_CUR" = OK ]   || FAIL=1
ST_LOG=$(st "$LOG" "$MAX_LOG");       [ "$ST_LOG" = OK ]   || FAIL=1

echo
printf '  %-28s : %3s / %-3s  %s\n' "Total lines"                  "$TOTAL" "$MAX_TOTAL" "$ST_TOTAL"
printf '  %-28s : %3s / %-3s  %s\n' "Current status content lines" "$CUR"   "$MAX_CUR"   "$ST_CUR"
printf '  %-28s : %3s / %-3s  %s\n' "Progress log entries"         "$LOG"   "$MAX_LOG"   "$ST_LOG"

# ---- Six-section structure ----
missing=""; dup=""
check_sec() { # name count
  if [ "${2:-0}" -eq 0 ]; then missing="$missing; $1"; fi
  if [ "${2:-0}" -gt 1 ]; then dup="$dup; $1 (x$2)"; fi
}
check_sec "Current status"   "$S_CUR"
check_sec "Next steps"       "$S_NEXT"
check_sec "Task list"        "$S_TASKS"
check_sec "Open issues"      "$S_LEGACY"
check_sec "User corrections" "$S_CORR"
check_sec "Progress log"     "$S_LOG"
missing="${missing#; }"; dup="${dup#; }"

STRUCT_OK="OK"
if [ -n "$missing" ] || [ -n "$dup" ] || [ -n "$EXTRAS" ]; then STRUCT_OK="DRIFT"; FAIL=1; fi
printf '  %-28s : %s\n' "Six-section structure" "$STRUCT_OK"
echo "      missing: ${missing:-none}"
echo "      duplicated: ${dup:-none}"
if [ -n "$EXTRAS" ]; then
  echo "      extra top-level ## sections:"
  echo "$EXTRAS" | sed 's/^/        - /'
else
  echo "      extra top-level ## sections: none"
fi

echo
if [ "$FAIL" -eq 0 ]; then
  echo "Result: OK -- size and structure within limits"
  exit 0
else
  echo "Result: OVER/DRIFT -- limit exceeded or structure drifted; fix per the \"Size / structure check\" step in SKILL.md, then write the update"
  exit 1
fi
