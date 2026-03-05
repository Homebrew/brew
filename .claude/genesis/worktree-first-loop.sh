#!/usr/bin/env bash
set -euo pipefail

if [ "${1:-}" = "" ]; then
  echo "usage: $0 <feature-branch-name>"
  echo "example: $0 feature/genesis-task-001"
  exit 1
fi

branch="$1"
current_branch="$(git rev-parse --abbrev-ref HEAD)"

if [ "$current_branch" != "$branch" ]; then
  if git show-ref --verify --quiet "refs/heads/$branch"; then
    git switch "$branch"
  else
    git switch -c "$branch"
  fi
fi

"$(git rev-parse --show-toplevel)/.claude/genesis/health-check-sync.sh"
"$(git rev-parse --show-toplevel)/.claude/genesis/daily-sync-report.sh"

echo "[genesis] first-loop ready on $branch"
