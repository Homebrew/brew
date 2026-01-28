---
last_review_date: "2025-02-08"
---

# Migrating a Formula to a Tap

There are times when we may wish to migrate a formula from one tap into another tap. To do this:

1. Create a pull request on the new tap adding the formula file as-is from the original tap. Fix any test failures that may occur due to the stricter requirements for new formulae compared to existing formulae (e.g. `brew audit --strict` must pass for that formula).
2. Create a pull request on the original tap deleting the formula file and adding it to `tap_migrations.json` with a commit message like `gv: migrate to homebrew/core`.
3. Put a link for each pull request in the other pull request so the maintainers can merge them both at once.

Congratulations, you've moved a formula to another tap!

For Homebrew maintainers, formulae should only ever be migrated into and within the Homebrew organisation (e.g. from `homebrew/core` to `homebrew/cask`, or from a third-party tap to `homebrew/core`), and never out of it.
