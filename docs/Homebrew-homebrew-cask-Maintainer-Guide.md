---
last_review_date: "1970-01-01"
---

# Homebrew/homebrew-cask Maintainer Guide

This guide is intended to help maintainers effectively maintain the cask repository. It is meant to be used in conjunction with the more generic [Maintainer Guidelines](Maintainer-Guidelines.md).

## Common Situations

Here is a list of the most common situations that arise in cask PRs and how to handle them:

- The `version` and `sha256` both change (keeping the same format): Merge.
- Only the `sha256` changes: Merge unless the version needs to be updated as well. It’s not uncommon for upstream vendors to update versions in-place. However, be wary for times when e.g. upstream could have been hacked.
- `livecheck` is updated: Use your best judgement and try to make sure that the changes follow the [`livecheck` guidelines](Brew-Livecheck.md).
- Only the `version` changes or the `version` format changes: Use your best judgement and merge if it seems correct (this is relatively rare).
- Other changes (including adding new casks): Use the [Cask Cookbook](Cask-Cookbook.md) to determine what's correct.

If in doubt, ask another cask maintainer on GitHub or Slack.

Note that unlike formulae, casks do not consider the `sha256` stanza to be a meaningful security measure as maintainers cannot realistically check them for authenticity. Casks download from upstream; if a malicious actor compromised a URL, they could potentially compromise a version and make it look like an update.

## Merging

In general, using GitHub's "Merge" button is the best way to merge a PR. This can be used when the PR modifies only one cask, regardless of the number of commits or whether the commit message format is correct. When merging using this method, the commit message can be modified if needed. Usually, version bump commit messages follow the form `Update CASK from OLD_VERSION to NEW_VERSION`.

If the PR modifies multiple casks, use the "Rebase and Merge" button to merge the PR. This will use the commit messages from the PR, so make sure that they are appropriate before merging. If needed, checkout the PR, squash/reword the commits and force-push back to the PR branch to ensure the proper commit format.

Finally, make sure to thank the contributor for submitting a PR!

## Other Tips

A maintainer can easily rebase a PR onto the latest `master` branch by adding a `/rebase` comment. `BrewTestBot` will automatically rebase the PR and add a reaction to the comment once the rebase is in progress and complete.
