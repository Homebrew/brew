---
logo: https://brew.sh/assets/img/brewtestbot.png
image: https://brew.sh/assets/img/brewtestbot.png
redirect_from:
  - /Brew-Test-Bot-For-Core-Contributors
last_review_date: "2026-07-18"
---

# BrewTestBot for Maintainers

[`brew test-bot`](Manpage.md#test-bot-options-formula) runs Homebrew's formula checks, builds bottles and tests affected dependents in GitHub Actions.
This page describes maintainer actions after the required checks have completed.

## Publishing bottles from a pull request

When all required jobs pass and the pull request needs no changes:

1. Review the formula file, including its test, and the generated bottle information.
2. Approve the pull request.
3. Allow BrewTestBot to merge and publish it automatically when repository rules permit.
4. Watch the final publication job and respond to a BrewTestBot failure notification.

Passing checks are not a substitute for reviewing the formula file, its test and the generated bottle checksums.
Do not approve a pull request merely to discover whether the publication workflow succeeds.

When automatic publication is intentionally unavailable, trigger the supported workflow with the pull-request number or URL:

```sh
brew pr-publish PULL_REQUEST
```

Use `--autosquash` only when the target tap supports it and the resulting commit structure matches the repository's policy.
Check the [Homebrew/core Actions queue](https://github.com/Homebrew/homebrew-core/actions) until publication finishes.

## Changes that require a local commit edit

Use `brew pr-pull PULL_REQUEST` when a maintainer must download bottle artifacts and edit unpublished commits locally.
Inspect the command's dry-run and help output before using options that change commits or upload artifacts.

After editing, run the relevant formula checks, inspect the final commits and push only the intended pull-request branch.
See [Common Issues for Maintainers](Common-Issues-for-Maintainers.md) for preserving the current state before recovering a failed bottle upload from an earlier commit.

## Rebottling an existing formula

Use the [`homebrew/core` rebottling workflow](https://github.com/Homebrew/homebrew-core/actions/workflows/dispatch-rebottle.yml) when a formula needs new bottles without an ordinary version update.

1. Select **Run workflow**.
2. Enter the formula and required rebuild information.
3. Review the generated pull request and bottle jobs normally.

Do not use rebottling to conceal a formula change that requires a version or revision update.
