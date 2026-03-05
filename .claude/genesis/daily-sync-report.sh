#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
REPORT_DIR="$ROOT/.claude/genesis/reports"
TODAY="$(date +%F)"
REPORT_FILE="$REPORT_DIR/$TODAY.md"

mkdir -p "$REPORT_DIR"

branch="$(git rev-parse --abbrev-ref HEAD)"
status="$(git status --short --branch)"
recent_commits="$(git log --oneline -5)"

cat > "$REPORT_FILE" <<EOF
# Genesis Daily Sync Report ($TODAY)

## Branch

$branch

## Status

\`\`\`
$status
\`\`\`

## Recent commits

\`\`\`
$recent_commits
\`\`\`
EOF

echo "[genesis] report written: ${REPORT_FILE#$ROOT/}"
