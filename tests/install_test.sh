#!/usr/bin/env bash
# tests/install_test.sh —— install.sh / init-ai.sh 回归测试。只在 mktemp 假 HOME 与假仓库下运行。
set -u
REAL_HOME="$HOME"
SRC="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok() { echo "PASS  $1"; PASS=$((PASS+1)); }
no() { echo "FAIL  $1"; FAIL=$((FAIL+1)); }
check() { if eval "$2"; then ok "$1"; else no "$1"; fi; }

mkrepo() {  # 造最小假仓库,不依赖真实 templates/skills/claude
  local R="$1"; mkdir -p "$R"
  cp "$SRC/install.sh" "$R/"; cp -R "$SRC/scripts" "$SRC/shell" "$R/"
  mkdir -p "$R/templates/project/.ai" "$R/templates/global" "$R/skills/wrap" "$R/skills/distill" "$R/claude/agents" "$R/claude/hooks"
  echo P > "$R/templates/project/AGENTS.md"
  for f in PROGRESS DECISIONS GOTCHAS; do echo "$f" > "$R/templates/project/.ai/$f.md"; done
  echo G > "$R/templates/global/AGENTS.md"; echo C > "$R/templates/global/claude-CLAUDE.md"; echo X > "$R/templates/global/codex-AGENTS.md"
  echo W > "$R/skills/wrap/SKILL.md"; echo D > "$R/skills/distill/SKILL.md"
  echo V > "$R/claude/agents/verifier.md"; printf '#!/bin/sh\n' > "$R/claude/hooks/guard.sh"; printf '#!/bin/sh\n' > "$R/claude/hooks/guard_test.sh"; echo '{}' > "$R/claude/settings-snippet.json"
}
REPO="$TMP/repo dir"; mkrepo "$REPO"
newhome() { H="$TMP/home$1"; mkdir -p "$H"; }
run() { [ "$H" != "$REAL_HOME" ] || { echo "拒绝:HOME 是真实家目录"; exit 2; }; HOME="$H" SHELL=/bin/zsh bash "$REPO/install.sh" "$@" 2>&1; }
snap() { (cd "$H" && find . -print | sort; find . -type f -exec shasum {} \; | sort); }

# a + j: 全新 HOME(j 用含空格路径)
for tag in a "j with space"; do
  newhome "$tag"; out="$(run)"
  check "$tag: 全部目标创建" '[ -f "$H/.ai/AGENTS.md" ] && [ -f "$H/.claude/CLAUDE.md" ] && [ -f "$H/.codex/AGENTS.md" ] && [ -f "$H/.ai/templates/GOTCHAS.md" ] && [ -f "$H/.claude/agents/verifier.md" ]'
  check "$tag: ~/.agents/skills/wrap -> 仓库" '[ "$(readlink "$H/.agents/skills/wrap")" = "$REPO/skills/wrap" ]'
  check "$tag: ~/.claude/skills/wrap -> ~/.agents" '[ "$(readlink "$H/.claude/skills/wrap")" = "$H/.agents/skills/wrap" ] && [ "$(readlink "$H/.codex/skills/distill")" = "$H/.agents/skills/distill" ]'
  check "$tag: hook 可执行" '[ -x "$H/.claude/hooks/guard.sh" ]'
  check "$tag: rc 有 source 行" 'grep -qF "shell/ai-kit.sh" "$H/.zshrc"'
done

# b: 幂等
newhome b; run >/dev/null; s1="$(snap)"; out="$(run)"; s2="$(snap)"
check "b: 第二次无 create/link/write" '! printf "%s\n" "$out" | grep -Eq "^(create|link|write) "'
check "b: 文件无变化" '[ "$s1" = "$s2" ]'

# c: 回归 —— 不写穿 ~/.claude/skills/wrap 软链接
newhome c; mkdir -p "$H/.agents/skills/wrap" "$H/.claude/skills"; echo NEW > "$H/.agents/skills/wrap/SKILL.md"
ln -s "$H/.agents/skills/wrap" "$H/.claude/skills/wrap"; run >/dev/null
check "c: 共享 skill 内容仍为 NEW" '[ "$(cat "$H/.agents/skills/wrap/SKILL.md")" = NEW ] && [ ! -L "$H/.agents/skills/wrap" ]'

# d: 已存在且不同的文件原样保留
newhome d; mkdir -p "$H/.ai" "$H/.claude/agents" "$H/.claude/hooks"
for f in .ai/AGENTS.md .claude/CLAUDE.md .claude/agents/verifier.md .claude/hooks/guard.sh; do echo MINE > "$H/$f"; done
out="$(run)"
check "d: 4 个文件原样" '[ "$(cat "$H/.ai/AGENTS.md" "$H/.claude/CLAUDE.md" "$H/.claude/agents/verifier.md" "$H/.claude/hooks/guard.sh" | sort -u)" = MINE ]'
check "d: 输出含 skip 与 diff 提示" '[ "$(printf "%s\n" "$out" | grep -c "^skip .*diff ")" -ge 4 ]'

# e: 旧布局软链接
newhome e; mkdir -p "$H/.ai" "$H/.claude"; echo OLD > "$H/.ai/AGENTS.md"; ln -s "$H/.ai/AGENTS.md" "$H/.claude/CLAUDE.md"; out="$(run)"
check "e: 旧软链接未动且有 note" '[ "$(readlink "$H/.claude/CLAUDE.md")" = "$H/.ai/AGENTS.md" ] && printf "%s\n" "$out" | grep -q "^note "'

# f: dry-run 不写任何东西
newhome f; out="$(run --dry-run)"; rc=$?
check "f: dry-run 后 HOME 为空" '[ $rc -eq 0 ] && [ -z "$(ls -A "$H")" ]'

# g: 开关与未知参数
newhome g1; run --no-skill >/dev/null; check "g: --no-skill" '[ ! -e "$H/.agents" ] && [ -f "$H/.claude/CLAUDE.md" ]'
newhome g2; run --no-claude >/dev/null; check "g: --no-claude" '[ ! -e "$H/.claude/agents" ] && [ ! -e "$H/.claude/hooks" ] && [ -L "$H/.claude/skills/wrap" ]'
newhome g3; run --no-codex >/dev/null; check "g: --no-codex" '[ ! -e "$H/.codex" ] && [ -L "$H/.claude/skills/wrap" ]'
newhome g4; run --bogus >/dev/null; rc=$?; check "g: 未知参数退出 1" '[ $rc -eq 1 ]'

# h: 悬空软链接目标
newhome h; mkdir -p "$H/.claude/agents" "$H/.agents/skills"; ln -s "$H/nowhere" "$H/.claude/agents/verifier.md"; ln -s "$H/nowhere2" "$H/.agents/skills/wrap"
run >/dev/null; rc=$?
check "h: 悬空软链接未被覆盖且未中断" '[ $rc -eq 0 ] && [ "$(readlink "$H/.claude/agents/verifier.md")" = "$H/nowhere" ] && [ "$(readlink "$H/.agents/skills/wrap")" = "$H/nowhere2" ] && [ ! -e "$H/nowhere" ] && [ -f "$H/.ai/AGENTS.md" ]'

# k: hooks 下的 *_test.sh 是测试,不安装
newhome k; out="$(run)"
check "k: guard.sh 已装且 guard_test.sh 未装" '[ -f "$H/.claude/hooks/guard.sh" ] && [ ! -e "$H/.claude/hooks/guard_test.sh" ] && ! printf "%s\n" "$out" | grep -q guard_test.sh'

# l: 相对路径软链接指向同一目录时算 ok
newhome l; mkdir -p "$H/.agents/skills/wrap" "$H/.claude/skills"; ln -s ../../.agents/skills/wrap "$H/.claude/skills/wrap"; out="$(run)"
check "l: 相对软链接输出 ok 且未改动" 'printf "%s\n" "$out" | grep -q "^ok .*/.claude/skills/wrap -> " && ! printf "%s\n" "$out" | grep -q "^skip .*/.claude/skills/wrap " && [ "$(readlink "$H/.claude/skills/wrap")" = ../../.agents/skills/wrap ]'

# i: init-ai.sh
P="$TMP/proj x"; mkdir -p "$P"
(cd "$P" && bash "$REPO/scripts/init-ai.sh" >/dev/null); out2="$(cd "$P" && bash "$REPO/scripts/init-ai.sh")"
check "i: init-ai 生成文件与 CLAUDE.md 软链接" '[ "$(cat "$P/AGENTS.md")" = P ] && [ -f "$P/.ai/PROGRESS.md" ] && [ -f "$P/.ai/DECISIONS.md" ] && [ -f "$P/.ai/GOTCHAS.md" ] && [ "$(readlink "$P/CLAUDE.md")" = AGENTS.md ]'
check "i: 第二次全是 skip" '! printf "%s\n" "$out2" | grep -Eq "^(create|link) " && [ "$(printf "%s\n" "$out2" | grep -c "^skip")" -eq 5 ]'

echo ""; echo "汇总: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
