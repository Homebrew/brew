---
last_review_date: "1970-01-01"
---

# Common Issues for Maintainers

## Overview

This is a page for maintainers to diagnose certain build errors.

## Issues

### Bottle publishes failed but the commits are correct in the git history

Follow these steps to fix this issue:

* Download and extract the bottle artifact.
* `brew pr-upload --no-commit` in the bottle directory.

Alternative instructions using `pr-pull`:

* `git reset --hard <SHA>` in `homebrew/core` to reset to the commit before all the commits created by `brew pr-pull`.
* `brew pr-pull <options>` to upload the right bottles. Add the `--warn-on-upload-failure` switch if the bottles have been partially uploaded and you're certain that the bottle checksums will match the checksums already present in the `bottle do` block of the formula.
* `git reset --hard origin/master` to return to the latest commit and discard the commits made by `brew pr-pull`.

### `ld: internal error: atom not found in symbolIndex(__ZN10SQInstance3GetERK11SQObjectPtrRS0_) for architecture x86_64`

The exact atom may be different.

This can be caused by passing the obsolete `-s` option to the linker and can be fixed [using `inreplace`](https://github.com/Homebrew/homebrew-core/commit/c4ad981d788b21a406a6efe7748f2922986919a8).
