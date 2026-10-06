#!/usr/bin/env bash
# pending.sh -- deterministic input collector for /distill.
#
# Run from the project root (reads .ai/ under cwd), or pass a project root:
#     bash pending.sh [PROJECT_ROOT]
#
# Sections are hints, not verdicts, for the LLM steps of /distill:
#   [1] GOTCHAS entries without a distilled marker: titles + count
#   [2] DECISIONS entries without a distilled marker: titles + count
#   [3] Non-empty lines of the PROGRESS "User corrections (pending distillation)" section + count
#   [4] Possible duplicate pairs among [1] titles + [3] lines (CJK 2-grams, shared Latin words)
#   [5] Size of target rule files: project AGENTS.md lines / SKILL.md count per
#       .agents, .claude, .codex skills dir / ~/.ai/AGENTS.md lines
#   [6] Top-level list-item rules in project and global AGENTS.md, with / without a rationale
#
# Conventions: an entry is a line starting with `## `; the marker
# `<!-- distilled YYYY-MM-DD -->` (or `... skipped -->`) sits on the line after
# the title. `## ` inside an HTML comment block (e.g. a trailing template) is
# not an entry. Section names match in English (case-insensitive) or Chinese.
# All awk runs under LC_ALL=C on bytes, avoiding macOS awk multibyte errors.
# Compatibility: macOS bash 3.2 + BSD/one-true awk, BSD sed/grep.

set -u

ROOT="${1:-.}"
AI="$ROOT/.ai"
GOTCHAS="$AI/GOTCHAS.md"
DECISIONS="$AI/DECISIONS.md"
PROGRESS="$AI/PROGRESS.md"
GLOBAL_AGENTS="$HOME/.ai/AGENTS.md"

# Print titles of `## ` entries without a distilled marker. Usage: undistilled_titles <file>
undistilled_titles() {
  [ -f "$1" ] || return 0
  LC_ALL=C awk '
    BEGIN { incomment=0; pending=0 }
    {
      line=$0
      if (incomment) { if (index(line,"-->")>0) incomment=0; pending=0; next }
      if (pending) {                         # previous line was a title; check for marker
        if (index(line,"distilled")==0) print headingtext
        pending=0                            # no next: this line may be a title/comment start
      }
      if (index(line,"<!--")>0 && index(line,"-->")==0) { incomment=1; next }
      if (substr(line,1,3)=="## ") {
        h=substr(line,4)
        # skip template placeholder titles (Chinese / English "short title", YYYY-... titles)
        if (h=="简短标题" || h=="Short title" || substr(h,1,4)=="YYYY") next
        headingtext=h; pending=1; next
      }
    }
    END { if (pending) print headingtext }   # file ends with a title = not distilled
  ' "$1"
}

# Print non-empty, non-comment lines of the user-corrections section. Heading:
# exactly "## User corrections" or "## User corrections (pending distillation)"
# (case-insensitive, extra spaces and full-width parens ok), or the Chinese name
# (matched on its leading word, so either paren width works).
corrections_lines() {
  [ -f "$PROGRESS" ] || return 0
  LC_ALL=C awk '
    /^## / {
      insec=0                                # section ends at the next ## heading
      # English: exact match after normalizing (trim, collapse spaces, lowercase,
      # full-width parens -> ASCII, no spaces around parens). Chinese: unchanged.
      lc=tolower(substr($0,4)); gsub(/[ \t\r]+/, " ", lc); sub(/^ /, "", lc); sub(/ $/, "", lc)
      gsub(/（/, "(", lc); gsub(/）/, ")", lc); gsub(/ ?\( ?/, "(", lc); gsub(/ ?\) ?/, ")", lc)
      if (index($0,"用户纠正")>0 || lc=="user corrections" || lc=="user corrections(pending distillation)") insec=1
      next
    }
    insec {
      if ($0 ~ /^[ \t]*$/) next
      if (inc) { if (index($0,"-->")>0) inc=0; next }
      if (index($0,"<!--")>0) { if (index($0,"-->")==0) inc=1; next }
      line=$0
      sub(/^[ \t]*[-*+][ \t]+/, "", line)
      print line
    }
  ' "$PROGRESS"
}

# Duplicate hints; input file has one entry per line.
# Source 1: CJK 2-grams (>=1 multibyte char). Source 2: Latin words (lowercase, len>=4, no stopwords).
dup_pairs() {
  LC_ALL=C awk '
    function is_cjk_punct(c) {
      return (c=="，"||c=="。"||c=="、"||c=="；"||c=="："||c=="？"||c=="！"|| \
              c=="「"||c=="」"||c=="『"||c=="』"||c=="（"||c=="）"||c=="【"||c=="】"|| \
              c=="《"||c=="》"||c=="—"||c=="…"||c=="·"||c=="．"||c=="　"||c=="／")
    }
    function addv(arr, k, v) { if (index(SUBSEP arr[k] SUBSEP, SUBSEP v SUBSEP)==0) arr[k]=arr[k] SUBSEP v }
    function pairs(mem, kind,   x, y, cnt, c2, t, a, b, g) {
      for (g in mem) {
        cnt=split(mem[g], a, " "); c2=0
        for (t=1; t<=cnt; t++) if (a[t]!="") { c2++; b[c2]=a[t] }
        for (x=1; x<c2; x++) for (y=x+1; y<=c2; y++) {
          allk[b[x] SUBSEP b[y]]=1
          if (kind=="g") addv(pg, b[x] SUBSEP b[y], g); else addv(pw, b[x] SUBSEP b[y], g)
        }
      }
    }
    BEGIN {
      ns=split("the with from that this when into after before should does have been were " \
               "will would could them then than they their there what which while about " \
               "also only some more must need each over just like your other", sw, " ")
      for (t=1; t<=ns; t++) stop[sw[t]]=1
    }
    {
      disp=$0; line=$0
      sub(/^[ \t]*[-*+][ \t]+/, "", line)
      # drop a leading date (YYYY-MM-DD plus suffix like (4)); dates are metadata
      sub(/^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9][^ ]*[ ]*/, "", line)
      # split UTF-8 chars; ASCII keeps alnum, multibyte keeps non-punct; wide[] = multibyte
      n=length(line); i=1; m=0
      while (i<=n) {
        len=1
        while (i+len<=n) { nb=substr(line,i+len,1); if (nb ~ /[\200-\277]/) len++; else break }
        c=substr(line,i,len); i+=len
        if (len==1) { if (c ~ /[A-Za-z0-9]/) { m++; ch[m]=c; wide[m]=0 } }
        else { if (!is_cjk_punct(c)) { m++; ch[m]=c; wide[m]=1 } }
      }
      idx++; item[idx]=disp
      for (j=1; j<m; j++) {                  # 2-grams with >=1 CJK char only
        if (!wide[j] && !wide[j+1]) continue
        g=ch[j] ch[j+1]
        if (!((g SUBSEP idx) in seen)) { seen[g SUBSEP idx]=1; members[g]=members[g] " " idx }
      }
      wl=tolower(line); gsub(/[^a-z0-9]+/, " ", wl)    # multibyte bytes act as separators
      nw=split(wl, ws, " ")
      for (t=1; t<=nw; t++) {
        w=ws[t]
        if (length(w)<4 || w ~ /^[0-9]+$/ || (w in stop)) continue
        if (!((w SUBSEP idx) in wseen)) { wseen[w SUBSEP idx]=1; wmembers[w]=wmembers[w] " " idx }
      }
    }
    END {
      pairs(members, "g"); pairs(wmembers, "w"); pc=0
      for (key in allk) {
        split(key, kp, SUBSEP)
        printf "  - \"%s\"\n    <-> \"%s\"\n", item[kp[1]], item[kp[2]]
        if (key in pg) { s=pg[key]; gsub(SUBSEP, ",", s); sub(/^,/, "", s); printf "    [shared 2-gram: %s]\n", s }
        if (key in pw) { s=pw[key]; gsub(SUBSEP, ",", s); sub(/^,/, "", s); printf "    [shared word: %s]\n", s }
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

TMP_G="$(mktemp "${TMPDIR:-/tmp}/distill_g.XXXXXX")"
TMP_C="$(mktemp "${TMPDIR:-/tmp}/distill_c.XXXXXX")"
TMP_ALL="$(mktemp "${TMPDIR:-/tmp}/distill_all.XXXXXX")"
trap 'rm -f "$TMP_G" "$TMP_C" "$TMP_ALL"' EXIT

undistilled_titles "$GOTCHAS" > "$TMP_G"
corrections_lines > "$TMP_C"

echo "[1] GOTCHAS undistilled entries  ($GOTCHAS)"
if [ ! -f "$GOTCHAS" ]; then
  echo "  (file not found)"
else
  gc=$(grep -c '' "$TMP_G" 2>/dev/null); [ -s "$TMP_G" ] || gc=0
  echo "  count: $gc"
  if [ "$gc" -gt 0 ]; then sed 's/^/  - /' "$TMP_G"; else echo "  (all entries have a distilled marker)"; fi
fi
echo

echo "[2] DECISIONS undistilled entries  ($DECISIONS)"
if [ ! -f "$DECISIONS" ]; then
  echo "  (file not found)"
else
  DTMP="$(mktemp "${TMPDIR:-/tmp}/distill_d.XXXXXX")"
  undistilled_titles "$DECISIONS" > "$DTMP"
  dc=$(grep -c '' "$DTMP" 2>/dev/null); [ -s "$DTMP" ] || dc=0
  echo "  count: $dc"
  if [ "$dc" -gt 0 ]; then sed 's/^/  - /' "$DTMP"; else echo "  (all entries have a distilled marker)"; fi
  rm -f "$DTMP"
fi
echo

echo "[3] PROGRESS \"User corrections (pending distillation)\"  ($PROGRESS)"
if [ ! -f "$PROGRESS" ]; then
  echo "  (file not found)"
else
  cc=$(grep -c '' "$TMP_C" 2>/dev/null); [ -s "$TMP_C" ] || cc=0
  echo "  lines: $cc"
  if [ "$cc" -gt 0 ]; then sed 's/^/  - /' "$TMP_C"; else echo "  (empty)"; fi
fi
echo

echo "[4] Title duplicate hints  (input = [1] GOTCHAS titles + [3] user corrections; shared CJK 2-grams / words; hints, not verdicts)"
cat "$TMP_G" "$TMP_C" > "$TMP_ALL"
if [ ! -s "$TMP_ALL" ]; then
  echo "  (no input entries, skipped)"
else
  OUT="$(dup_pairs "$TMP_ALL")"
  pc=$(echo "$OUT" | sed -n 's/^PAIRCOUNT //p')
  [ -n "$pc" ] || pc=0
  echo "  pairs: $pc"
  if [ "$pc" -gt 0 ]; then echo "$OUT" | grep -v '^PAIRCOUNT'; else echo "  (no pairs share a 2-gram or word)"; fi
fi
echo

echo "[5] Size of target rule files"
if [ -f "$ROOT/AGENTS.md" ]; then
  echo "  project AGENTS.md       : $(count_lines "$ROOT/AGENTS.md") lines  ($ROOT/AGENTS.md)"
elif [ -f "$ROOT/CLAUDE.md" ]; then
  echo "  project CLAUDE.md       : $(count_lines "$ROOT/CLAUDE.md") lines  ($ROOT/CLAUDE.md, no AGENTS.md)"
else
  echo "  project AGENTS.md       : (not found)"
fi
# Per directory, not summed: entries may symlink to the same skill.
echo "  skills counted per directory (not a deduplicated total; symlinked entries may repeat)"
for skill_scope in .agents .claude .codex; do
  skc=0
  for d in "$ROOT"/"$skill_scope"/skills/*/SKILL.md; do [ -f "$d" ] && skc=$((skc+1)); done
  echo "  project $skill_scope/skills : $skc SKILL.md"
done
if [ -f "$GLOBAL_AGENTS" ]; then
  echo "  global ~/.ai/AGENTS.md  : $(count_lines "$GLOBAL_AGENTS") lines  ($GLOBAL_AGENTS)"
else
  echo "  global ~/.ai/AGENTS.md  : (not found)"
fi
echo

# [6] A rule = top-level list item (`- ` `* ` `+ ` `1. `) plus indented continuation
# lines; blank lines, headings and top-level non-list lines end it; code fences and
# HTML comments are skipped. Has a rationale if any line contains "(rationale:"
# (case-insensitive) or the Chinese equivalent. Approximate count.
rule_provenance() {
  [ -f "$1" ] || { echo "(not found)"; return 0; }
  LC_ALL=C awk '
    function flush() { if (initem) { total++; if (has) withp++ } initem=0; has=0 }
    function hasr(s) { return (index(s,"来由")>0 || tolower(s) ~ /\([ \t]*rationale[ \t]*:/) }
    {
      line=$0
      if (incomment) { if (index(line,"-->")>0) incomment=0; next }
      if (line ~ /^[ \t]*```/) { flush(); infence=!infence; next }
      if (infence) next
      if (index(line,"<!--")>0 && index(line,"-->")==0) { flush(); incomment=1; next }
      if (line ~ /^([-*+]|[0-9]+\.)[ \t]/) { flush(); initem=1; if (hasr(line)) has=1; next }
      if (line ~ /^[ \t]*$/ || line !~ /^[ \t]/) { flush(); next }
      if (initem && hasr(line)) has=1
    }
    END { flush(); printf "%d list-item rule%s: %d with rationale / %d without\n", total, (total==1 ? "" : "s"), withp, total-withp }
  ' "$1"
}

echo "[6] Rule rationale stats in target files  (approximate top-level list-item count; for /distill step 4 cross-model review)"
if [ -f "$ROOT/AGENTS.md" ]; then
  echo "  project AGENTS.md       : $(rule_provenance "$ROOT/AGENTS.md")"
elif [ -f "$ROOT/CLAUDE.md" ]; then
  echo "  project CLAUDE.md       : $(rule_provenance "$ROOT/CLAUDE.md")"
else
  echo "  project AGENTS.md       : (not found)"
fi
echo "  global ~/.ai/AGENTS.md  : $(rule_provenance "$GLOBAL_AGENTS")"
echo

exit 0
