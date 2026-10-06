#!/usr/bin/env bash
# pending.sh —— /distill 的确定性输入收集器。
#
# 在项目根运行（默认读 cwd 下的 .ai/），也可传一个目录参数指向别的项目根：
#     bash pending.sh [PROJECT_ROOT]
#
# 输出五部分，全部是"线索"不是"判定"，供 /distill 的 LLM 步骤消费：
#   [1] GOTCHAS 未打 distilled 标记的条目标题 + 计数
#   [2] DECISIONS 未打 distilled 标记的条目标题 + 计数
#   [3] PROGRESS「用户纠正（待蒸馏）」段的非空内容行 + 行数
#   [4] 对 [1]+[3] 的标题做 2-gram 共享检测，列出可能重复的条目对（线索，非去重判定）
#   [5] 落点文件现有规则规模：项目 AGENTS.md 行数 / .agents、.claude、.codex skills 分目录数量 / ~/.ai/AGENTS.md 行数
#   [6] （后加，只追加）项目 AGENTS.md 与 ~/.ai/AGENTS.md 的顶格列表项规则带 / 不带「来由」条数
#
# 约定：条目是 `## ` 开头的行；distilled 标记 `<!-- distilled YYYY-MM-DD -->`
# （未采纳记 `... skipped -->`）在标题的**下一行**。HTML 注释块内的 `## `（如文件末尾模板）
# 不算条目。全部 awk 都跑在 LC_ALL=C 下，按字节处理，避开 macOS awk 的多字节转换报错。
#
# 兼容目标：macOS 自带 bash 3.2 + BSD/one-true awk、BSD sed/grep。

set -u

ROOT="${1:-.}"
AI="$ROOT/.ai"
GOTCHAS="$AI/GOTCHAS.md"
DECISIONS="$AI/DECISIONS.md"
PROGRESS="$AI/PROGRESS.md"
GLOBAL_AGENTS="$HOME/.ai/AGENTS.md"

# --- 打印未打 distilled 标记的 `## ` 条目标题（跳过注释块内的 `## `）---
# 用法：undistilled_titles <file>
undistilled_titles() {
  [ -f "$1" ] || return 0
  LC_ALL=C awk '
    BEGIN { incomment=0; pending=0 }
    {
      line=$0
      if (incomment) {                       # 注释块内：找到 --> 就出块，块内一切忽略
        if (index(line,"-->")>0) incomment=0
        pending=0
        next
      }
      if (pending) {                         # 上一行是真条目标题，本行判断有无 distilled 标记
        if (index(line,"distilled")==0) print headingtext
        pending=0
        # 不 next：本行可能自身是新标题或注释起点，继续下面的判断
      }
      if (index(line,"<!--")>0 && index(line,"-->")==0) { incomment=1; next }
      if (substr(line,1,3)=="## ") {
        h=substr(line,4)
        # 跳过模板占位标题（新建自模板、或文件末尾/中部残留的模板块）
        if (h=="简短标题" || substr(h,1,4)=="YYYY") next
        headingtext=h; pending=1; next
      }
    }
    END { if (pending) print headingtext }   # 文件以标题结尾、无下一行 = 未蒸馏
  ' "$1"
}

# --- 打印「用户纠正（待蒸馏）」段的非空、非注释内容行 ---
corrections_lines() {
  [ -f "$PROGRESS" ] || return 0
  LC_ALL=C awk '
    /^## / {
      if (insec) insec=0                     # 段在下一个 ## 标题处结束
      if (index($0,"用户纠正")>0) insec=1
      next
    }
    insec {
      if ($0 ~ /^[ \t]*$/) next              # 跳过空行
      if (inc) { if (index($0,"-->")>0) inc=0; next }   # 跳过多行注释
      if (index($0,"<!--")>0) { if (index($0,"-->")==0) inc=1; next }  # 单/多行注释起点
      line=$0
      sub(/^[ \t]*[-*+][ \t]+/, "", line)               # 去掉行首列表符号，显示更干净
      print line
    }
  ' "$PROGRESS"
}

# --- 2-gram 共享检测：入参是一个每行一条目的文件，输出可能重复的条目对 ---
twogram_pairs() {
  LC_ALL=C awk '
    # 需要跳过的 CJK 标点（多字节），用字节序列匹配剔除，避免 2-gram 跨标点
    function is_cjk_punct(c) {
      return (c=="，"||c=="。"||c=="、"||c=="；"||c=="："||c=="？"||c=="！"|| \
              c=="「"||c=="」"||c=="『"||c=="』"||c=="（"||c=="）"||c=="【"||c=="】"|| \
              c=="《"||c=="》"||c=="—"||c=="…"||c=="·"||c=="．"||c=="　"||c=="／")
    }
    {
      disp=$0
      line=$0
      sub(/^[ \t]*[-*+][ \t]+/, "", line)               # 去掉行首列表符号
      # 去掉行首日期前缀（YYYY-MM-DD 及其后可能的 (4) 之类，再吃掉空格）—— 日期是元数据不是内容
      sub(/^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9][^ ]*[ ]*/, "", line)
      # 拆 UTF-8 字符，保留内容字符；wide[] 标记是否多字节（CJK）
      n=length(line); i=1; m=0
      while (i<=n) {
        len=1
        while (i+len<=n) { nb=substr(line,i+len,1); if (nb ~ /[\200-\277]/) len++; else break }
        c=substr(line,i,len); i+=len
        if (len==1) { if (c ~ /[A-Za-z0-9]/) { m++; ch[m]=c; wide[m]=0 } }  # ASCII 只留字母数字
        else { if (!is_cjk_punct(c)) { m++; ch[m]=c; wide[m]=1 } }          # 多字节留非标点
      }
      idx++
      item[idx]=disp
      # 相邻两字符组 2-gram，登记「该 gram 出现在哪些条目」；
      # 只收含 ≥1 个 CJK 字符的 2-gram —— 纯 ASCII / 纯数字 gram（日期、agent 之类样板词）是噪声
      for (j=1; j<m; j++) {
        if (!wide[j] && !wide[j+1]) continue
        g=ch[j] ch[j+1]
        if (!((g SUBSEP idx) in seen)) {
          seen[g SUBSEP idx]=1
          members[g]=members[g] " " idx
        }
      }
    }
    END {
      pc=0
      for (g in members) {
        cnt=split(members[g], a, " ")   # a[1] 是前导空格产生的空元素
        # 收集非空成员
        c2=0
        for (t=1; t<=cnt; t++) if (a[t]!="") { c2++; b[c2]=a[t] }
        if (c2>=2) {
          for (x=1; x<c2; x++) for (y=x+1; y<=c2; y++) {
            key=b[x] SUBSEP b[y]
            if (index(SUBSEP pairgrams[key] SUBSEP, SUBSEP g SUBSEP)==0)
              pairgrams[key]=pairgrams[key] SUBSEP g
          }
        }
      }
      for (key in pairgrams) {
        split(key, kp, SUBSEP)
        # pairgrams[key] 形如 \034g1\034g2...，转成逗号分隔展示
        grams=pairgrams[key]; gsub(SUBSEP, ",", grams); sub(/^,/, "", grams)
        printf "  - \"%s\"\n    <-> \"%s\"\n    [共享 2-gram: %s]\n", item[kp[1]], item[kp[2]], grams
        pc++
      }
      printf "PAIRCOUNT %d\n", pc
    }
  ' "$1"
}

count_lines() { [ -f "$1" ] && wc -l < "$1" | tr -d ' ' || echo "0"; }

echo "=================================================="
echo " distill pending report"
echo " root: $ROOT"
echo "=================================================="
echo

# 收集 [1] 与 [3] 到临时文件，供 [4] 复用
TMP_G="$(mktemp "${TMPDIR:-/tmp}/distill_g.XXXXXX")"
TMP_C="$(mktemp "${TMPDIR:-/tmp}/distill_c.XXXXXX")"
TMP_ALL="$(mktemp "${TMPDIR:-/tmp}/distill_all.XXXXXX")"
trap 'rm -f "$TMP_G" "$TMP_C" "$TMP_ALL"' EXIT

undistilled_titles "$GOTCHAS" > "$TMP_G"
corrections_lines > "$TMP_C"

echo "[1] GOTCHAS 未蒸馏条目  ($GOTCHAS)"
if [ ! -f "$GOTCHAS" ]; then
  echo "  (文件不存在)"
else
  gc=$(grep -c '' "$TMP_G" 2>/dev/null); [ -s "$TMP_G" ] || gc=0
  echo "  count: $gc"
  if [ "$gc" -gt 0 ]; then sed 's/^/  - /' "$TMP_G"; else echo "  (全部已打 distilled 标记)"; fi
fi
echo

echo "[2] DECISIONS 未蒸馏条目  ($DECISIONS)"
if [ ! -f "$DECISIONS" ]; then
  echo "  (文件不存在)"
else
  DTMP="$(mktemp "${TMPDIR:-/tmp}/distill_d.XXXXXX")"
  undistilled_titles "$DECISIONS" > "$DTMP"
  dc=$(grep -c '' "$DTMP" 2>/dev/null); [ -s "$DTMP" ] || dc=0
  echo "  count: $dc"
  if [ "$dc" -gt 0 ]; then sed 's/^/  - /' "$DTMP"; else echo "  (全部已打 distilled 标记)"; fi
  rm -f "$DTMP"
fi
echo

echo "[3] PROGRESS「用户纠正（待蒸馏）」  ($PROGRESS)"
if [ ! -f "$PROGRESS" ]; then
  echo "  (文件不存在)"
else
  cc=$(grep -c '' "$TMP_C" 2>/dev/null); [ -s "$TMP_C" ] || cc=0
  echo "  lines: $cc"
  if [ "$cc" -gt 0 ]; then sed 's/^/  - /' "$TMP_C"; else echo "  (空)"; fi
fi
echo

echo "[4] 标题重复线索  (输入 = [1] GOTCHAS 标题 + [3] 用户纠正；2-gram 共享，线索非判定)"
cat "$TMP_G" "$TMP_C" > "$TMP_ALL"
if [ ! -s "$TMP_ALL" ]; then
  echo "  (无输入条目，跳过)"
else
  OUT="$(twogram_pairs "$TMP_ALL")"
  pc=$(echo "$OUT" | sed -n 's/^PAIRCOUNT //p')
  [ -n "$pc" ] || pc=0
  echo "  pairs: $pc"
  if [ "$pc" -gt 0 ]; then echo "$OUT" | grep -v '^PAIRCOUNT'; else echo "  (未发现共享 2-gram 的条目对)"; fi
fi
echo

echo "[5] 落点文件现有规则规模"
# 项目 AGENTS.md（缺失则回退 CLAUDE.md）
if [ -f "$ROOT/AGENTS.md" ]; then
  echo "  项目 AGENTS.md          : $(count_lines "$ROOT/AGENTS.md") 行  ($ROOT/AGENTS.md)"
elif [ -f "$ROOT/CLAUDE.md" ]; then
  echo "  项目 CLAUDE.md          : $(count_lines "$ROOT/CLAUDE.md") 行  ($ROOT/CLAUDE.md，无 AGENTS.md)"
else
  echo "  项目 AGENTS.md          : (不存在)"
fi
# 分目录展示，不相加：不同入口可能通过 symlink 指向同一 skill。
echo "  skills 按目录计数（不是去重总计；symlink 入口可能重复）"
for skill_scope in .agents .claude .codex; do
  skc=0
  for d in "$ROOT"/"$skill_scope"/skills/*/SKILL.md; do [ -f "$d" ] && skc=$((skc+1)); done
  echo "  项目 $skill_scope/skills : $skc 个 SKILL.md"
done
# 全局 ~/.ai/AGENTS.md
if [ -f "$GLOBAL_AGENTS" ]; then
  echo "  全局 ~/.ai/AGENTS.md    : $(count_lines "$GLOBAL_AGENTS") 行  ($GLOBAL_AGENTS)"
else
  echo "  全局 ~/.ai/AGENTS.md    : (不存在)"
fi
echo

# [6] 是后加的部分，只追加在 [5] 之后；[1]-[5] 的格式不变。
# 规则 = 顶格的列表项（`- ` / `* ` / `+ ` / `1. `），连同其后缩进的续行（含子列表）算一条；
# 空行、标题、顶格非列表行结束一条。代码块与 HTML 注释内的行不算。
# 一条内任意行出现「来由」即算带来由。表格行、段落式规则不计 —— 是近似计数。
rule_provenance() {
  [ -f "$1" ] || { echo "(不存在)"; return 0; }
  LC_ALL=C awk '
    function flush() { if (initem) { total++; if (has) withp++ } initem=0; has=0 }
    {
      line=$0
      if (incomment) { if (index(line,"-->")>0) incomment=0; next }
      if (line ~ /^[ \t]*```/) { flush(); infence=!infence; next }
      if (infence) next
      if (index(line,"<!--")>0 && index(line,"-->")==0) { flush(); incomment=1; next }
      if (line ~ /^([-*+]|[0-9]+\.)[ \t]/) { flush(); initem=1; if (index(line,"来由")>0) has=1; next }
      if (line ~ /^[ \t]*$/ || line !~ /^[ \t]/) { flush(); next }
      if (initem && index(line,"来由")>0) has=1
    }
    END { flush(); printf "列表项规则 %d 条：带来由 %d / 不带来由 %d\n", total, withp, total-withp }
  ' "$1"
}

echo "[6] 落点文件规则来由统计  (顶格列表项近似计数；供 /distill 步骤 4 换模型复查)"
if [ -f "$ROOT/AGENTS.md" ]; then
  echo "  项目 AGENTS.md          : $(rule_provenance "$ROOT/AGENTS.md")"
elif [ -f "$ROOT/CLAUDE.md" ]; then
  echo "  项目 CLAUDE.md          : $(rule_provenance "$ROOT/CLAUDE.md")"
else
  echo "  项目 AGENTS.md          : (不存在)"
fi
echo "  全局 ~/.ai/AGENTS.md    : $(rule_provenance "$GLOBAL_AGENTS")"
echo

exit 0
