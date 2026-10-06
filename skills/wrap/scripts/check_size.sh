#!/usr/bin/env bash
# check_size.sh —— /wrap 的确定性体积/结构检查器。
#
# 在项目根运行（默认读 cwd 下的 .ai/PROGRESS.md），也可传目录参数：
#     bash check_size.sh [PROJECT_ROOT]
#
# 一次性输出并逐项判定 OK / OVER；任一超限或结构漂移 -> exit 1。
#
# ---- 判定规则（数字与段名集中在此，SKILL.md 只引用本脚本，不再复述）----
# 上限：
#   PROGRESS 总行数（wc -l）           <= 120
#   「当前状态」段非空、非注释内容行     <= 10
#   「进度日志」条目数（列表项）         <= 10
# 结构：必须恰好是模板六段，各出现一次、无缺失、无重复、无多余顶层 ## 段：
#   当前状态 / 下一步 / 任务清单 / 遗留 / 用户纠正 / 进度日志
#   （匹配按关键词：遗留 段实际标题是「遗留 / 待澄清」，用户纠正 段是「用户纠正（待蒸馏）」）
# 超限/漂移的处置见 SKILL.md「体积检查」步骤（多余进度日志进 archive、多余段归位等）。
#
# 兼容目标：macOS 自带 bash 3.2 + BSD/one-true awk、BSD sed/grep。

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
  echo "  (文件不存在 —— 先按模板新建 .ai/PROGRESS.md)"
  exit 1
fi

TOTAL=$(wc -l < "$PROGRESS" | tr -d ' ')

# 一次 awk 扫描：当前状态非空行数、进度日志条目数、六段各自出现次数、多余段清单
OUT=$(LC_ALL=C awk '
  BEGIN { inc=0; sec="" }
  {
    line=$0
    if (substr(line,1,3)=="## ") {
      inc=0
      if      (index(line,"当前状态")>0) { sec="cur";    c_cur++ }
      else if (index(line,"下一步")>0)   { sec="next";   c_next++ }
      else if (index(line,"任务清单")>0) { sec="tasks";  c_tasks++ }
      else if (index(line,"遗留")>0)     { sec="legacy"; c_legacy++ }
      else if (index(line,"用户纠正")>0) { sec="corr";   c_corr++ }
      else if (index(line,"进度日志")>0) { sec="log";    c_log++ }
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
    print "SEC cur "    c_cur+0
    print "SEC next "   c_next+0
    print "SEC tasks "  c_tasks+0
    print "SEC legacy " c_legacy+0
    print "SEC corr "   c_corr+0
    print "SEC log "    c_log+0
  }
' "$PROGRESS")

getval() { echo "$OUT" | awk -v k="$1" '$1==k{print $2}'; }
getsec() { echo "$OUT" | awk -v k="$1" '$1=="SEC" && $2==k{print $3}'; }

CUR=$(getval CUR); LOG=$(getval LOG)
S_CUR=$(getsec cur); S_NEXT=$(getsec next); S_TASKS=$(getsec tasks)
S_LEGACY=$(getsec legacy); S_CORR=$(getsec corr); S_LOG=$(getsec log)
EXTRAS=$(echo "$OUT" | sed -n 's/^EXTRA //p')

FAIL=0
# st 只回显 OK/OVER，不改全局（避免在 $() 子shell 里改 FAIL 丢失）；FAIL 在父shell 里判定
st() { if [ "$1" -le "$2" ]; then echo "OK"; else echo "OVER"; fi; }

ST_TOTAL=$(st "$TOTAL" "$MAX_TOTAL"); [ "$ST_TOTAL" = OK ] || FAIL=1
ST_CUR=$(st "$CUR" "$MAX_CUR");       [ "$ST_CUR" = OK ]   || FAIL=1
ST_LOG=$(st "$LOG" "$MAX_LOG");       [ "$ST_LOG" = OK ]   || FAIL=1

echo
printf '  %-22s : %3s / %-3s  %s\n' "总行数"            "$TOTAL" "$MAX_TOTAL" "$ST_TOTAL"
printf '  %-22s : %3s / %-3s  %s\n' "当前状态段内容行数" "$CUR"   "$MAX_CUR"   "$ST_CUR"
printf '  %-22s : %3s / %-3s  %s\n' "进度日志条目数"      "$LOG"   "$MAX_LOG"   "$ST_LOG"

# ---- 六段结构 ----
missing=""; dup=""
check_sec() { # name count
  if [ "${2:-0}" -eq 0 ]; then missing="$missing $1"; fi
  if [ "${2:-0}" -gt 1 ]; then dup="$dup $1(x$2)"; fi
}
check_sec 当前状态 "$S_CUR"
check_sec 下一步   "$S_NEXT"
check_sec 任务清单 "$S_TASKS"
check_sec 遗留     "$S_LEGACY"
check_sec 用户纠正 "$S_CORR"
check_sec 进度日志 "$S_LOG"

STRUCT_OK="OK"
if [ -n "$missing" ] || [ -n "$dup" ] || [ -n "$EXTRAS" ]; then STRUCT_OK="DRIFT"; FAIL=1; fi
printf '  %-22s : %s\n' "六段结构" "$STRUCT_OK"
echo "      缺失: ${missing:- 无}"
echo "      重复: ${dup:- 无}"
if [ -n "$EXTRAS" ]; then
  echo "      多余顶层 ## 段:"
  echo "$EXTRAS" | sed 's/^/        - /'
else
  echo "      多余顶层 ## 段: 无"
fi

echo
if [ "$FAIL" -eq 0 ]; then
  echo "结论: OK —— 体积与结构均达标"
  exit 0
else
  echo "结论: OVER/DRIFT —— 存在超限或结构漂移，按 SKILL.md「体积检查」步骤归位后再写更新"
  exit 1
fi
