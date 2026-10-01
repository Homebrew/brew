---
last_review_date: "2026-07-18"
redirect_from:
  - /Common-Issues-for-Core-Contributors
---

# Common Issues for Maintainers

This page records maintainer-only recovery procedures that are not part of normal user troubleshooting.
Preserve local work and prefer a temporary clone or Git worktree when reproducing an older repository state.

## Bottle publication failed after the commits were created

If the formula commits are correct and only bottle publication failed:

1. Download and extract the bottle artifact from the failed workflow.
2. Change to the extracted artifact directory.
3. Run `brew pr-upload --no-commit` with the appropriate upload options.

`brew pr-pull` always operates on the canonical tap checkout, regardless of the current directory.
If it must be repeated from an earlier commit, first ensure that the canonical `homebrew/core` checkout has no uncommitted work, fetch its remote and create a backup branch at its current commit:

```sh
git -C "$(brew --repository homebrew/core)" status --short
git -C "$(brew --repository homebrew/core)" fetch origin
git -C "$(brew --repository homebrew/core)" branch pr-pull-recovery-backup
```

Reset the canonical checkout to the commit before the commits created by the failed `brew pr-pull`, then repeat the command with the original options:

```sh
git -C "$(brew --repository homebrew/core)" reset --hard COMMIT_SHA
brew pr-pull PULL_REQUEST
```

Add `--warn-on-upload-failure` only when bottles were partially uploaded and their checksums are known to match the existing `bottle do` block.

After publication succeeds, return the checkout to the remote default branch:

```sh
git -C "$(brew --repository homebrew/core)" reset --hard origin/HEAD
```

Delete the backup branch only after confirming that it is no longer needed.
Do not use this recovery procedure when the canonical checkout contains work that has not been committed or preserved elsewhere.

## Unfamiliar build failures

Do not add a permanent workaround based only on an old issue or an exact linker error string.
Reproduce the failure on a supported runner, inspect the compiler and linker invocation, then determine whether the problem comes from the formula, upstream or the runner image.

Document reusable findings in the relevant maintainer or formula-author guide instead of adding one-off historical errors to this page.
