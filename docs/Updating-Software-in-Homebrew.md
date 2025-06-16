---
last_review_date: "2025-02-08"
---

# Updating Software in Homebrew

Did you find something in Homebrew that wasn't the latest version? You can help yourself and others by submitting a pull request to update the formula.

First, check the pull requests in the Homebrew tap repositories to make sure a PR isn't already open. If you're submitting a [formula](Formula-Cookbook.md#homebrew-terminology), check [homebrew-core](https://github.com/Homebrew/homebrew-core/pulls). If you're submitting a [cask](Formula-Cookbook.md#homebrew-terminology), check [homebrew-cask](https://github.com/Homebrew/homebrew-cask/pulls). You may also want to look through closed pull requests in the repositories, as sometimes packages run into problems preventing them from being updated and it's better to be aware of any issues before putting significant effort into an update.

The [How to Open a Homebrew Pull Request](How-To-Open-a-Homebrew-Pull-Request.md) documentation should explain most everything you need to know about the process of creating a PR for a version update. For simple updates, this typically involves changing the `url` and `sha256` values.

However, some updates require additional changes to the package. You can look back at previous pull requests to see how others have handled things in the past, but be sure to look at a variety of PRs. Sometimes packages aren't updated properly, so you may need to use your judgment to determine how best to proceed.

Once you've created the pull request in the appropriate Homebrew repository your commit(s) will be tested on our continuous integration servers, showing a green check mark if everything passed or a red X if there were failures. Maintainers will review your pull request and provide feedback about any changes that need to be made before it can be merged.

We appreciate your help in keeping Homebrew's repositories up to date as new versions of software are released!
