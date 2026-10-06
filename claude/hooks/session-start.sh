#!/bin/bash
# SessionStart hook: in repos with .ai/, inject the tail of PROGRESS.md plus git status,
# so the model gets project state without having to read it on its own.
[ -f .ai/PROGRESS.md ] || exit 0
echo "## .ai/PROGRESS.md (tail 60)"
tail -n 60 .ai/PROGRESS.md
echo
echo "## git"
git status -sb 2>/dev/null
git log --oneline -5 2>/dev/null
exit 0
