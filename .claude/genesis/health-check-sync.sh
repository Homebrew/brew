#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"

required_files=(
  "$ROOT/.claude/genesis/worktree-first-loop.sh"
  "$ROOT/.claude/genesis/health-check-sync.sh"
  "$ROOT/.claude/genesis/daily-sync-report.sh"
)

echo "[genesis] health-check-sync"
echo "- repo root: $ROOT"
echo "- branch: $(git rev-parse --abbrev-ref HEAD)"

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "- git: ok"
else
  echo "- git: failed"
  exit 1
fi

if [ -n "$(git status --short)" ]; then
  echo "- working tree: dirty"
else
  echo "- working tree: clean"
fi

missing=0
for file in "${required_files[@]}"; do
  if [ -f "$file" ]; then
    echo "- file exists: ${file#$ROOT/}"
  else
    echo "- file missing: ${file#$ROOT/}"
    missing=1
  fi
done

if [ "$missing" -ne 0 ]; then
  echo "[genesis] health-check failed"
  exit 1
fi

echo "[genesis] health-check passed"
