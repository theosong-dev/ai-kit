#!/usr/bin/env bash
# tests/install_test.sh -- regression tests for install.sh / init-ai.sh. Runs only under a mktemp fake HOME and fake repo.
set -u
unset AI_KIT_LANG  # the user shell may export it; tests set it explicitly
REAL_HOME="$HOME"
SRC="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok() { echo "PASS  $1"; PASS=$((PASS+1)); }
no() { echo "FAIL  $1"; FAIL=$((FAIL+1)); }
check() { if eval "$2"; then ok "$1"; else no "$1"; fi; }

mkrepo() {  # minimal fake repo; default sources contain "EN", zh-CN mirror contains "ZH"
  local R="$1" p m; mkdir -p "$R"
  cp "$SRC/install.sh" "$R/"; cp -R "$SRC/scripts" "$SRC/shell" "$R/"
  for p in "" zh-CN/; do
    m=EN; [ -z "$p" ] || m=ZH
    mkdir -p "$R/${p}templates/project/.ai" "$R/${p}templates/global" "$R/${p}skills/wrap" "$R/${p}skills/distill" "$R/${p}claude/agents"
    echo "$m P" > "$R/${p}templates/project/AGENTS.md"
    for f in PROGRESS DECISIONS GOTCHAS; do echo "$m $f" > "$R/${p}templates/project/.ai/$f.md"; done
    echo "$m G" > "$R/${p}templates/global/AGENTS.md"; echo "$m C" > "$R/${p}templates/global/claude-CLAUDE.md"; echo "$m X" > "$R/${p}templates/global/codex-AGENTS.md"
    echo "$m W" > "$R/${p}skills/wrap/SKILL.md"; echo "$m D" > "$R/${p}skills/distill/SKILL.md"
    echo "$m V" > "$R/${p}claude/agents/verifier.md"
  done
  mkdir -p "$R/claude/hooks"; printf '#!/bin/sh\n' > "$R/claude/hooks/guard.sh"; printf '#!/bin/sh\n' > "$R/claude/hooks/guard_test.sh"; echo '{}' > "$R/claude/settings-snippet.json"
}
REPO="$TMP/repo dir"; mkrepo "$REPO"
newhome() { H="$TMP/home$1"; mkdir -p "$H"; }
run() { [ "$H" != "$REAL_HOME" ] || { echo "refused: HOME is the real home directory"; exit 2; }; HOME="$H" SHELL=/bin/zsh bash "$REPO/install.sh" "$@" 2>&1; }
snap() { (cd "$H" && find . -print | sort; find . -type f -exec shasum {} \; | sort); }

# a + j: fresh HOME (j uses a path with spaces)
for tag in a "j with space"; do
  newhome "$tag"; out="$(run)"
  check "$tag: all targets created" '[ -f "$H/.ai/AGENTS.md" ] && [ -f "$H/.claude/CLAUDE.md" ] && [ -f "$H/.codex/AGENTS.md" ] && [ -f "$H/.ai/templates/GOTCHAS.md" ] && [ -f "$H/.claude/agents/verifier.md" ]'
  check "$tag: ~/.agents/skills/wrap -> repo" '[ "$(readlink "$H/.agents/skills/wrap")" = "$REPO/skills/wrap" ]'
  check "$tag: ~/.claude/skills/wrap -> ~/.agents" '[ "$(readlink "$H/.claude/skills/wrap")" = "$H/.agents/skills/wrap" ] && [ "$(readlink "$H/.codex/skills/distill")" = "$H/.agents/skills/distill" ]'
  check "$tag: hook is executable" '[ -x "$H/.claude/hooks/guard.sh" ]'
  check "$tag: rc has source line" 'grep -qF "shell/ai-kit.sh" "$H/.zshrc"'
done

# b: idempotent
newhome b; run >/dev/null; s1="$(snap)"; out="$(run)"; s2="$(snap)"
check "b: second run has no create/link/write" '! printf "%s\n" "$out" | grep -Eq "^(create|link|write) "'
check "b: files unchanged" '[ "$s1" = "$s2" ]'

# c: regression -- do not write through the ~/.claude/skills/wrap symlink
newhome c; mkdir -p "$H/.agents/skills/wrap" "$H/.claude/skills"; echo NEW > "$H/.agents/skills/wrap/SKILL.md"
ln -s "$H/.agents/skills/wrap" "$H/.claude/skills/wrap"; run >/dev/null
check "c: shared skill content is still NEW" '[ "$(cat "$H/.agents/skills/wrap/SKILL.md")" = NEW ] && [ ! -L "$H/.agents/skills/wrap" ]'

# d: existing, differing files are kept as is
newhome d; mkdir -p "$H/.ai" "$H/.claude/agents" "$H/.claude/hooks"
for f in .ai/AGENTS.md .claude/CLAUDE.md .claude/agents/verifier.md .claude/hooks/guard.sh; do echo MINE > "$H/$f"; done
out="$(run)"
check "d: 4 files unchanged" '[ "$(cat "$H/.ai/AGENTS.md" "$H/.claude/CLAUDE.md" "$H/.claude/agents/verifier.md" "$H/.claude/hooks/guard.sh" | sort -u)" = MINE ]'
check "d: output has skip with diff hint" '[ "$(printf "%s\n" "$out" | grep -c "^skip .*diff ")" -ge 4 ]'

# e: old-layout symlink
newhome e; mkdir -p "$H/.ai" "$H/.claude"; echo OLD > "$H/.ai/AGENTS.md"; ln -s "$H/.ai/AGENTS.md" "$H/.claude/CLAUDE.md"; out="$(run)"
check "e: old symlink untouched and note printed" '[ "$(readlink "$H/.claude/CLAUDE.md")" = "$H/.ai/AGENTS.md" ] && printf "%s\n" "$out" | grep -q "^note "'

# f: dry-run writes nothing
newhome f; out="$(run --dry-run)"; rc=$?
check "f: HOME empty after dry-run" '[ $rc -eq 0 ] && [ -z "$(ls -A "$H")" ]'

# g: switches and unknown argument
newhome g1; run --no-skill >/dev/null; check "g: --no-skill" '[ ! -e "$H/.agents" ] && [ -f "$H/.claude/CLAUDE.md" ]'
newhome g2; run --no-claude >/dev/null; check "g: --no-claude" '[ ! -e "$H/.claude/agents" ] && [ ! -e "$H/.claude/hooks" ] && [ -L "$H/.claude/skills/wrap" ]'
newhome g3; run --no-codex >/dev/null; check "g: --no-codex" '[ ! -e "$H/.codex" ] && [ -L "$H/.claude/skills/wrap" ]'
newhome g4; run --bogus >/dev/null; rc=$?; check "g: unknown argument exits 1" '[ $rc -eq 1 ]'

# h: dangling symlink targets
newhome h; mkdir -p "$H/.claude/agents" "$H/.agents/skills"; ln -s "$H/nowhere" "$H/.claude/agents/verifier.md"; ln -s "$H/nowhere2" "$H/.agents/skills/wrap"
run >/dev/null; rc=$?
check "h: dangling symlinks kept and run not aborted" '[ $rc -eq 0 ] && [ "$(readlink "$H/.claude/agents/verifier.md")" = "$H/nowhere" ] && [ "$(readlink "$H/.agents/skills/wrap")" = "$H/nowhere2" ] && [ ! -e "$H/nowhere" ] && [ -f "$H/.ai/AGENTS.md" ]'

# k: *_test.sh under hooks are tests and are not installed
newhome k; out="$(run)"
check "k: guard.sh installed, guard_test.sh not" '[ -f "$H/.claude/hooks/guard.sh" ] && [ ! -e "$H/.claude/hooks/guard_test.sh" ] && ! printf "%s\n" "$out" | grep -q guard_test.sh'

# l: relative symlink to the same dir counts as ok
newhome l; mkdir -p "$H/.agents/skills/wrap" "$H/.claude/skills"; ln -s ../../.agents/skills/wrap "$H/.claude/skills/wrap"; out="$(run)"
check "l: relative symlink reported ok and unchanged" 'printf "%s\n" "$out" | grep -q "^ok .*/.claude/skills/wrap -> " && ! printf "%s\n" "$out" | grep -q "^skip .*/.claude/skills/wrap " && [ "$(readlink "$H/.claude/skills/wrap")" = ../../.agents/skills/wrap ]'

# i: init-ai.sh
P="$TMP/proj x"; mkdir -p "$P"
(cd "$P" && bash "$REPO/scripts/init-ai.sh" >/dev/null); out2="$(cd "$P" && bash "$REPO/scripts/init-ai.sh")"
check "i: init-ai creates files and CLAUDE.md symlink" '[ "$(cat "$P/AGENTS.md")" = "EN P" ] && [ -f "$P/.ai/PROGRESS.md" ] && [ -f "$P/.ai/DECISIONS.md" ] && [ -f "$P/.ai/GOTCHAS.md" ] && [ "$(readlink "$P/CLAUDE.md")" = AGENTS.md ]'
check "i: second run is all skip" '! printf "%s\n" "$out2" | grep -Eq "^(create|link) " && [ "$(printf "%s\n" "$out2" | grep -c "^skip")" -eq 5 ]'

# ---- language selection (--lang / AI_KIT_LANG) ----
# allmark <EN|ZH> [files...]: every listed file under $H starts with the marker
GLOBALS=".ai/AGENTS.md .claude/CLAUDE.md .codex/AGENTS.md .ai/templates/PROGRESS.md .ai/templates/DECISIONS.md .ai/templates/GOTCHAS.md"
allmark() { local m="$1" f; shift; for f in "$@"; do grep -q "^$m " "$H/$f" || return 1; done; }
langbefore() { local a b; a="$(grep -n '^export AI_KIT_LANG=zh-CN$' "$H/.zshrc" | cut -d: -f1)"; b="$(grep -n 'shell/ai-kit.sh' "$H/.zshrc" | cut -d: -f1)"; [ -n "$a" ] && [ -n "$b" ] && [ "$a" -lt "$b" ]; }

# m + n2: --lang zh-CN / --lang=zh-CN on a fresh HOME
for tag in m n2; do
  newhome "$tag"; if [ "$tag" = m ]; then out="$(run --lang zh-CN)"; else out="$(run --lang=zh-CN)"; fi; rc=$?
  check "$tag: exit 0, globals/templates/agents are ZH" '[ $rc -eq 0 ] && allmark ZH $GLOBALS .claude/agents/verifier.md'
  check "$tag: ~/.agents/skills/wrap -> zh-CN/skills/wrap" '[ "$(readlink "$H/.agents/skills/wrap")" = "$REPO/zh-CN/skills/wrap" ] && [ "$(readlink "$H/.agents/skills/distill")" = "$REPO/zh-CN/skills/distill" ]'
  check "$tag: hooks come from default source" 'cmp -s "$REPO/claude/hooks/guard.sh" "$H/.claude/hooks/guard.sh"'
  check "$tag: rc has export AI_KIT_LANG=zh-CN before source line" 'langbefore'
done

# n: no --lang on a fresh HOME
newhome n; out="$(run)"
check "n: globals/templates/agents are EN" 'allmark EN $GLOBALS .claude/agents/verifier.md && [ "$(readlink "$H/.agents/skills/wrap")" = "$REPO/skills/wrap" ]'
check "n: rc has no AI_KIT_LANG" '! grep -q AI_KIT_LANG "$H/.zshrc"'

# p: bad --lang values exit 1 and write nothing
newhome p1; out="$(run --lang fr)"; rc=$?
check "p: --lang fr exits 1, HOME empty" '[ $rc -eq 1 ] && [ -z "$(ls -A "$H")" ] && printf "%s\n" "$out" | grep -q "^error "'
newhome p2; out="$(run --no-codex --lang)"; rc=$?
check "p: trailing --lang without value exits 1, HOME empty" '[ $rc -eq 1 ] && [ -z "$(ls -A "$H")" ] && printf "%s\n" "$out" | grep -q "^error "'

# q: default install, then --lang zh-CN on the same HOME changes nothing
newhome q; run >/dev/null; s1="$(snap)"; out="$(run --lang zh-CN)"; rc=$?; s2="$(snap)"
check "q: exit 0, no create/link/write, has skip" '[ $rc -eq 0 ] && ! printf "%s\n" "$out" | grep -Eq "^(create|link|write) " && printf "%s\n" "$out" | grep -q "^skip "'
check "q: files (incl. rc) unchanged, no AI_KIT_LANG in rc" '[ "$s1" = "$s2" ] && ! grep -q AI_KIT_LANG "$H/.zshrc"'
check "q: hint about adding AI_KIT_LANG manually" 'printf "%s\n" "$out" | grep -q "export AI_KIT_LANG=zh-CN"'

# o: partial / missing language sources fall back to defaults
SAVED_REPO="$REPO"
REPO="$TMP/repo o1"; mkrepo "$REPO"; rm -rf "$REPO/zh-CN/skills/distill"
newhome o1; out="$(run --lang zh-CN)"; rc=$?
check "o: missing zh-CN distill falls back with note, wrap stays zh-CN" '[ $rc -eq 0 ] && [ "$(readlink "$H/.agents/skills/distill")" = "$REPO/skills/distill" ] && printf "%s\n" "$out" | grep -q "^note .*distill" && [ "$(readlink "$H/.agents/skills/wrap")" = "$REPO/zh-CN/skills/wrap" ]'
REPO="$TMP/repo o2"; mkrepo "$REPO"; rm -rf "$REPO/zh-CN/templates"
newhome o2; out="$(run --lang zh-CN)"; rc=$?
check "o: missing zh-CN/templates warns, globals EN, exit 0" '[ $rc -eq 0 ] && printf "%s\n" "$out" | grep -q "^warn .*zh-CN/templates" && allmark EN $GLOBALS && allmark ZH .claude/agents/verifier.md'

# r: init-ai.sh honours AI_KIT_LANG
P="$TMP/proj r1"; mkdir -p "$P"; (cd "$P" && AI_KIT_LANG=zh-CN bash "$SAVED_REPO/scripts/init-ai.sh" >/dev/null)
check "r: AI_KIT_LANG=zh-CN gives ZH templates" '[ "$(cat "$P/AGENTS.md")" = "ZH P" ] && [ "$(cat "$P/.ai/GOTCHAS.md")" = "ZH GOTCHAS" ]'
P="$TMP/proj r2"; mkdir -p "$P"; (cd "$P" && bash "$SAVED_REPO/scripts/init-ai.sh" >/dev/null)
check "r: unset AI_KIT_LANG gives EN templates" '[ "$(cat "$P/AGENTS.md")" = "EN P" ]'
REPO="$TMP/repo o1"; rm -f "$REPO/zh-CN/templates/project/AGENTS.md"
P="$TMP/proj r3"; mkdir -p "$P"; (cd "$P" && AI_KIT_LANG=zh-CN bash "$REPO/scripts/init-ai.sh" >/dev/null 2>&1); rc=$?
check "r: missing zh-CN template exits 1, project dir empty" '[ $rc -eq 1 ] && [ -z "$(ls -A "$P")" ]'
REPO="$SAVED_REPO"

# s: dry-run with --lang zh-CN writes nothing but mentions AI_KIT_LANG
newhome s; out="$(run --dry-run --lang zh-CN)"; rc=$?
check "s: dry-run zh-CN leaves HOME empty, mentions AI_KIT_LANG" '[ $rc -eq 0 ] && [ -z "$(ls -A "$H")" ] && printf "%s\n" "$out" | grep -q "^\[dry-run\] .*AI_KIT_LANG"'

echo ""; echo "Summary: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
