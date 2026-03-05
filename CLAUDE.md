@AGENTS.md

## Genesis workflow (first loop)

- `./.claude/genesis/worktree-first-loop.sh <feature-branch-name>`: ensure branch is active, then run health check and daily report.
- `./.claude/genesis/health-check-sync.sh`: verify worktree state and required Genesis scripts.
- `./.claude/genesis/daily-sync-report.sh`: generate a dated status report under `.claude/genesis/reports/`.
