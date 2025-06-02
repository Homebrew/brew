---
last_review_date: "1970-01-01"
---

# Releases

Since Homebrew 1.0.0 most Homebrew users (those who haven't run a `dev-cmd` or set `HOMEBREW_DEVELOPER=1` which is ~99.9% based on analytics data) require tags on the [Homebrew/brew repository](https://github.com/homebrew/brew) in order to receive new versions of Homebrew. There are a few steps in making a new Homebrew release:

1. Check if there is anything pressing that needs to be fixed or merged before the next release in:
   - [`Homebrew/brew` pull requests](https://github.com/homebrew/brew/pulls)
   - [`Homebrew/brew` issues](https://github.com/homebrew/brew/issues)
   - [`Homebrew/homebrew-core` issues](https://github.com/homebrew/homebrew-core/issues)
   - [Homebrew/discussions (forum)](https://github.com/orgs/Homebrew/discussions)

    If so, fix and merge these changes.

2. Ensure that:
   - no code changes have happened for at least a couple of hours (ideally 4 hours),
   - at least one Homebrew/homebrew-core pull request CI job has completed successfully,
   - the state of the Homebrew/brew `master` CI job is clear (i.e. main jobs green or green after rerunning)
   - you are confident there are no major regressions on the current `master` branch.

3. Run `brew release` to create a new draft release. For major or minor version bumps, pass `--major` or `--minor`, respectively.

4. Publish the draft release on [GitHub](https://github.com/Homebrew/brew/releases).

If this is a major or minor release (e.g. X.0.0 or X.Y.0) then there are a few more steps:

1. Before creating the tag you should:
   - delete any `odisabled` code,
   - make any `odeprecated` code `odisabled`,
   - uncomment any `# odeprecated` code
   - add any new `odeprecations` that are desired.

   Also delete any command argument definitions that pass `replacement: ...`.

2. Write up a release notes blog post for <https://brew.sh> (e.g. [brew.sh#319](https://github.com/Homebrew/brew.sh/pull/319)). This should use the output from `brew release [--major|--minor]` as input but have the wording adjusted to be more human readable and explain not just what has changed but why.

3. When the release has shipped and the blog post has been merged, tweet the blog post as the [@MacHomebrew Twitter account](https://twitter.com/MacHomebrew) or tweet it yourself and retweet it with the @MacHomebrew Twitter account (credentials are in 1Password).

4. Consider whether to submit it to other sources, e.g. Hacker News, Reddit.
   - Pros: gets a wider reach and user feedback
   - Cons: negative comments are common and people take this as a chance to complain about Homebrew (regardless of their usage)

Please do not manually create a release based on older commits on the `master` branch. It's very hard to judge whether these have been sufficiently tested by users or if they will cause negative side effects with the current state of Homebrew/homebrew-core. If a new branch is needed ASAP but there are things on `master` that cannot be released yet (e.g. new deprecations and you want to make a patch release) then revert the relevant PRs, follow the process above and then revert the reverted PRs to reapply them on `master`.
