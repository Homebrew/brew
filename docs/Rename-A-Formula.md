---
last_review_date: "1970-01-01"
---

# Renaming a Formula

Sometimes software and formulae need to be renamed. To rename a formula you need to:

1. Copy the formula file and rename its class to a new formula name. The new name must meet all the usual rules of formula naming. Fix any test failures that may occur due to the stricter requirements for new formulae compared to existing formulae (e.g. `brew audit --strict` must pass for that formula).

2. Create a pull request on the corresponding tap with at least two separate commits - one adding the new formula file, another deleting the old formula file. Also record the rename in `formula_renames.json` with a commit message like `newack: renamed from ack`. Use the canonical name (e.g. `ack` instead of `user/repo/ack`).

A `formula_renames.json` example for a formula rename:

```json
{
  "ack": "newack"
}
```
