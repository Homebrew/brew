---
last_review_date: "2026-07-24"
---

# Releases

Homebrew users receive new versions of Homebrew/brew from GitHub release tags.
Only maintainers with write access to Homebrew/brew can create a release.

## Prepare the release

1. Check for urgent work that should be resolved before the release:
   - [`Homebrew/brew` pull requests](https://github.com/Homebrew/brew/pulls)
   - [`Homebrew/brew` issues](https://github.com/Homebrew/brew/issues)
   - [`Homebrew/homebrew-core` issues](https://github.com/Homebrew/homebrew-core/issues)
   - [Homebrew Discussions](https://github.com/orgs/Homebrew/discussions)
2. Label any Homebrew/brew issues or pull requests that must be resolved before any release with `release blocker`, or before the next major or minor release with `major/minor release blocker`.
   While any open Homebrew/brew issue or pull request has a relevant label, `brew release` and the release workflow will refuse to create a release.
3. Confirm that the workflows on Homebrew/brew's `main` branch are passing and that at least one recent Homebrew/homebrew-core pull request has completed CI successfully.
4. Allow enough time after the last code change to detect regressions before releasing.
5. Confirm that the current `main` branch is suitable for release.

Do not create a release from an older commit on `main`.
If unreleased changes must be excluded from an urgent patch release, revert those changes, complete the release process and then reapply them.

## Create the release

Preview the release notes and version number:

```sh
brew release
```

Pass `--major` or `--minor` to preview a major or minor release instead of the default patch release.
Homebrew will refuse to create a major or minor release if the previous major or minor release was less than one month ago.

After reviewing the preview, create the draft release and trigger the release workflow:

```sh
brew release --force
```

Include `--major` or `--minor` when required.
Review the resulting [draft release](https://github.com/Homebrew/brew/releases), confirm the version and notes, then publish it.

## Major and minor releases

Before creating a major or minor release:

1. Remove code marked `odisabled`.
2. Change code marked `odeprecated` to `odisabled`.
3. Uncomment code marked `# odeprecated` when it should enter the deprecation cycle.
4. Add planned `odeprecations`.
5. Remove command argument definitions that still pass `replacement:`.

See [Deprecating, Disabling and Removing](Deprecating-Disabling-and-Removing.md#the-deprecation-lifecycle) for the complete lifecycle.

Use the output from `brew release [--major|--minor]` as the basis for a release notes post on the [Homebrew website](https://brew.sh/).
Edit the generated notes to explain the purpose and user impact of the changes, not only what changed.

After the release and post are published, announce them through the project communication channels currently maintained by Homebrew.
Consider broader announcement channels only when their expected reach and moderation cost are appropriate for the release.
