---
last_review_date: "2026-07-18"
---

# Renaming a Formula or Cask

A rename must preserve upgrades from the old package name and avoid leaving chained or conflicting rename records.
Complete the file change and rename metadata in the same pull request.

## Formulae

1. Choose a new name that meets the [formula naming rules](Formula-Cookbook.md#a-quick-word-on-naming).
2. Rename the formula file and class together.
3. Update aliases, dependencies, service names, caveats, tests and documentation that refer to the old name.
4. Add an old-to-new mapping to the tap's `formula_renames.json` using canonical names without a tap prefix.
5. Collapse an existing rename chain so every historical name maps directly to the current formula.
6. Run the strict audit, formula test and changed-package checks.

Example:

```json
{
  "ack": "newack"
}
```

Use a commit summary such as `newack: renamed from ack`.
Do not leave a formula under both names unless they are intentionally separate packages that can be maintained independently.

## Casks

1. Choose a token that meets the [cask token rules](Cask-Cookbook.md#token-reference).
2. Rename the cask file and update the token in the `cask` block.
3. Update references to the old token, including dependencies, conflicts and documentation.
4. Add an old-to-new mapping to `cask_renames.json`.
5. Collapse existing rename chains and ensure the old token does not conflict with a current cask.
6. Test installation, migration and uninstall behaviour and run the cask audit.

Example:

```json
{
  "old-token": "new-token"
}
```

Use a commit summary such as `new-token: renamed from old-token`.
Homebrew uses the rename mapping during updates and `brew migrate`, so the target must exist in the same tap.
