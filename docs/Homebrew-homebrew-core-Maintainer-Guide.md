---
last_review_date: "2026-07-18"
---

# Homebrew/homebrew-core Maintainer Guide

## Quick merge checklist

A detailed checklist appears [below](#detailed-merge-checklist).
Use this summary for routine reviews, then consult the detailed checklist when a change has unusual dependencies, build behaviour or release history:

- Ensure the name seems reasonable.
- Add aliases.
- Ensure it uses `keg_only :provided_by_macos` if it already comes with macOS.
- Ensure it is not a library that can be installed with [gem](https://en.wikipedia.org/wiki/RubyGems), [cpan](https://en.wikipedia.org/wiki/Cpan) or [pip](https://pip.pypa.io/en/stable/).
- Ensure that any dependencies are accurate and minimal. We don't need to support every possible optional feature for the software.
- When bottles aren't required or affected, use the GitHub squash & merge workflow for a single-formula PR or rebase & merge workflow for a multiple-formulae PR. See the [How to merge without bottles](#how-to-merge-without-bottles) section below for more details.
- Use `brew pr-publish` or `brew pr-pull` otherwise, which adds messages to auto-close pull requests and pull bottles built by BrewTestBot.
- Thank people for contributing.

Review dependencies carefully because unnecessary dependencies impose an ongoing build, security and maintenance cost.
Revisit existing dependencies when upstream changes its defaults or removes a feature.

Keep the dependency graph as small as practical while preserving the supported functionality users reasonably expect.
Disable optional X11 functionality when it adds substantial dependencies and does not provide a suitable default macOS experience.

`homebrew/core` primarily packages command-line software and libraries.
Software whose primary artifact is a native macOS `.app` belongs in `homebrew/cask` as a cask.

## Dependencies and full variants

Apply the contributor-facing [dependency and full-variant acceptance policy](Acceptable-Formulae.md#dependencies-and-full-variants).
When reviewing an existing dependency, also consider whether removing it would cause surprising breakage in common workflows or force formulae to rely on a deprecated system component.

## Merging, rebasing, cherry-picking

For most PRs that make formula modifications, you can simply approve the PR and an automatic merge (with bottles) will be performed by [@BrewTestBot](https://github.com/BrewTestBot). See [BrewTestBot for Maintainers](BrewTestBot-For-Maintainers.md) for more information.

Some PRs may not be merged automatically by [@BrewTestBot](https://github.com/BrewTestBot), even after approval.
Inspect the current workflow result and labels to determine why automation stopped, then run `brew pr-publish` when manual publication is appropriate.

PRs modifying formulae that don't need bottles or making changes that don't require new bottles to be pulled should use GitHub's squash & merge or rebase & merge workflows.

Otherwise, you should use `brew pr-pull` (or `rebase`/`cherry-pick` contributions).

Do not rebase commits after they have been pushed to `main`.
Rewrite only unpublished commits and inspect the final history before pushing.

Cherry-picking changes commit metadata, so preserve the original contribution and authorship information when using it.

Do not merge a branch whose history contains unrelated or accidental merge commits.
Rebase or squash unpublished contributor commits when needed so the `main` branch records a clear, reviewable change history.

Only one maintainer is necessary to approve and merge the addition of a new or updated formula which passes CI. However, if the formula addition or update proves controversial the maintainer who adds it will be expected to answer requests and fix problems that arise with it in future.

### How to merge without bottles

Here are guidelines about when to use squash & merge versus rebase & merge. These options should only be used with PRs where bottles are not affected.

| | PR modifies a single formula | PR modifies multiple formulae |
|---|---|---|
| **Commits look good** | rebase & merge _or_ squash & merge | rebase & merge |
| **Commits need work** | squash & merge | manually merge using the command line |

## Naming

The name is the strictest item, because avoiding a later name change is desirable.

Choose a name that’s the most common name for the project. For example, we initially chose `objective-caml` but we should have chosen `ocaml`. Choose what people say to each other when talking about the project.

Formulae that are also packaged by other package managers (e.g. Debian, Ubuntu) should be named consistently (subject to minor differences due to Homebrew formula naming conventions).

Add other names as aliases using symlinks within `Aliases` in the tap root. Ensure the name referenced on the homepage is one of these, as it may be different and have underscores and hyphens and so on.

We now accept versioned formulae as long as they [meet the requirements](Versions.md).

## Testing

Every formula change must at least build successfully in the required BrewTestBot jobs.
Use [BrewTestBot](BrewTestBot.md) for this validation.

- Verify installed functionality rather than relying solely on the contributor's local result.
- Require a meaningful `test do` block that exercises the installed software without network access.
- For a library, compile and run a small program against the installed headers and library when practical.
- If the reviewer cannot evaluate specialised behaviour, request reproducible validation from upstream documentation, an existing test suite or another reviewer with relevant knowledge.

If a formula uses a source-code repository, its `url` must identify an immutable tag or revision.
Do not package a moving branch as a stable release.

- Do not merge a formula update with a failing `brew test`.
- Fix the failure or replace a flaky test with a reliable test that still detects whether the installed software works.
- If the failure comes from Homebrew or CI, fix that problem or add a narrowly scoped formula workaround before merging.
- Do not normalise merging a red pull request.

## Retagged formulae

Upstream source archives and Git tags for released versions are expected to be immutable.
If the checksum of a fixed-version source archive changes or a Git tag moves to a different commit, treat this as a potential upstream compromise or supply-chain attack rather than a routine update.

Where possible, contact upstream through an official channel, preferably a public issue tracker, and ask them to confirm why the source changed and that it was not the result of a compromise.
Do not open or merge a PR updating the formula's checksum, revision or source until upstream has confirmed the change was intentional.
The PR should link to upstream's confirmation.

If the change cannot be verified, deprecate the formula with `:checksum_mismatch` rather than packaging the changed source.

## Duplicates

Software that duplicates a macOS-provided tool or library may be accepted when it uses `keg_only :provided_by_macos` and otherwise meets the [formula acceptance criteria](Acceptable-Formulae.md).

## Removing formulae

Formulae that:

- work on at least 2/3 of our supported macOS versions in the default Homebrew prefix
- do not require patches rejected by upstream to work
- do not have known security vulnerabilities or CVEs for the version we package
- are shown to be still installed by users in our analytics with a `BuildError` rate of <25%

should not be removed from Homebrew. The exception to this rule are [versioned formulae](Versions.md) for which there are higher standards of usage and a maximum number of versions for a given formula.

Apply the shared policy for [upstream removal requests](Deprecating-Disabling-and-Removing.md#upstream-removal-requests).

For more information about deprecating, disabling and removing formulae, see the [Deprecating, Disabling and Removing](Deprecating-Disabling-and-Removing.md#formulae-and-casks) page.

## Detailed merge checklist

The following checklist is intended to help maintainers decide on whether to merge, request changes or close a PR. It also brings more transparency for contributors in addition to the [Acceptable Formulae](Acceptable-Formulae.md) requirements.

- previously opened active PRs, as we would like to be fair to contributors who came first
- patches/`inreplace` that have been applied to upstream and can be removed
- comments in formula around `url`, as we do skip some versions (for example [`vim`](https://github.com/Homebrew/homebrew-core/blob/960639ce96ae5dd4a4b60b8887f44c1475dc60db/Formula/v/vim.rb#L4) or [`v8`](https://github.com/Homebrew/homebrew-core/blob/d14753288535e01178a3cd510ef2d64b03901c01/Formula/v/v8.rb#L4))
- vendored resources that need updates (for example [`emscripten`](https://github.com/Homebrew/homebrew-core/blob/442f9cc511ce6dfe75b96b2c83749d90dde914d2/Formula/e/emscripten.rb#L49-L67))
- vendored dependencies (for example [`certbot`](https://github.com/Homebrew/homebrew-core/pull/42966/files))
- stable/announced release:
  - some teams use an odd minor release number for tests and even for stable releases
  - other teams drop new versions with minor release 0 but promote it to stable only after a few minor releases
  - if the software uses only hosted version control (such as GitHub, GitLab or Bitbucket), the release should be tagged and if upstream marks latest/pre-releases, PR must use latest
- does changelog mention addition/removal of a dependency, and is it addressed in the PR?
  - does formula depend on versioned formula (for example `python@3.7`, `go@1.10`, `erlang@17`) that can be upgraded?
- commits:
  - contain one formula change per commit
    - ask author to squash
    - rebase during merge
  - version update follows preferred message format for simple version updates: `foobar 7.3`
  - other fixes format is `foobar: fix flibble matrix`
- bottle block is not removed

  Suggested reply:

      Please keep bottle block in place; [@BrewTestBot](https://github.com/BrewTestBot) takes care of it.

- is there a test block for other than checking version or printing help? Consider asking to add one
- if CI failed:
  - due to test block - paste relevant lines and add `test failure` label
  - due to build errors - paste relevant lines and add `build failure` label
  - due to other formulae needing revision bumps - suggest using the following command:

        # in this example: PR is for `libuv` formula and `urbit` needs revision bump
        brew bump-compatibility-version --write-only libuv
        brew bump-revision --message 'for libuv' urbit

    - make sure it has one commit per revision bump
- if CI is green and...
  - bottles need to be pulled, and...
    - the commits are correct, don't need changes, and BrewTestBot can merge it: approve the PR to trigger an automatic merge (use `brew pr-publish $PR_ID` to trigger it manually when necessary)
    - the commits are correct and don't need changes, but BrewTestBot can't merge it (has the label `automerge-skip`): use `brew pr-publish $PR_ID`
    - the commits need to be amended: use `brew pr-pull $PR_ID`, make changes, and `git push`
- don't forget to thank the contributor
  - celebrate any first-time contributors
- suggest using `brew bump-formula-pr` next time if this was not the case

## Staging branches

### Summary

Some formulae (e.g. Python, OpenSSL, ICU, Boost) have a large number of dependents. This makes updating these formulae (or their dependents) difficult because the standard procedure involves updating a large number of formulae in a single pull request. An alternative procedure that can significantly simplify this process is to use a staging branch.

The idea of using a staging branch is to merge updates and publish bottles for the affected formula to a non-default branch. This allows work to be done incrementally in smaller PRs, instead of in one giant PR that touches many formulae. When the staging branch is ready, it can be merged to the `main`/default branch.

Before making use of a staging branch, there is one important disadvantage to consider: once you have merged bottle updates to the staging branch, it is **very difficult** to take them back. This typically involves deleting uploaded bottles, which will occasionally require an owner of the Homebrew GitHub organisation to delete uploaded bottles one at a time.

### How to use a staging branch

Here is a rough outline of how to use a staging branch:

1. Create the staging branch in [Homebrew/homebrew-core](https://github.com/Homebrew/homebrew-core). The name of the staging branch _must_ start with the name of the root formula, followed by a `-`, and end in `-staging`. You can omit the `@` and anything that follows for versioned formulae (e.g. `icu4c-staging`, `openssl-migration-staging`, `python@3.12-staging`). It might be helpful to look at the [code](https://github.com/Homebrew/brew/blob/3db1acf3e38e270af4e1c3f214622bbfb18f830e/Library/Homebrew/formula_auditor.rb#L357-L375) that parses the branch names to check whether a PR targets a staging branch.

1. Open an issue in homebrew-core inviting contributors to help. Be sure to include instructions for how to do so, and a checklist of formulae that need to be updated. See [Homebrew/homebrew-core#134251](https://github.com/Homebrew/homebrew-core/issues/134251) for an example.

1. Open a _draft_ PR that merges the staging branch into the `main` branch. This allows you to keep track of the work done so far. You may wish to apply the [`no long build conflict`](https://github.com/Homebrew/homebrew-core/labels/no%20long%20build%20conflict) label to this PR to avoid conflicting changes from being merged to the `main` branch.

1. Open PRs targeting the staging branch that update the affected formulae. Each PR should touch as few formulae as possible. The typical PR that targets the staging branch will update only one formula at a time. Staging branch PRs can be merged using the same process as PRs that target the `main` branch. Ideally, these PRs should be opened in [topological order](https://en.wikipedia.org/wiki/Topological_sorting) according to the dependency graph, but we don't currently have good tooling for generating a topological sort. (Help wanted.)

1. Label PRs that target the staging branch with the [`staging-branch-pr`](https://github.com/Homebrew/homebrew-core/labels/staging-branch-pr) label for ease of tracking and review. (TODO: Add some automation for this to homebrew-core.)

1. Monitor the draft PR you created in step 3 above for merge conflicts. If you encounter a merge conflict, you must resolve those conflicts in a staging branch PR that merges the `main` branch into the staging branch.

1. When the staging branch is ready to be merged into `main`, mark the draft PR as ready for review and merge it into the `main` branch. Your PR may spend a long time in the merge queue waiting for the bottle fetch tests to run.

For examples of uses of the staging branch, see homebrew-core PRs labelled [`openssl-3-migration-staging`](https://github.com/Homebrew/homebrew-core/labels/openssl-3-migration), [Homebrew/homebrew-core#134260](https://github.com/Homebrew/homebrew-core/pull/134260), or [Homebrew/homebrew-core#133611](https://github.com/Homebrew/homebrew-core/pull/133611).

Finally: while the use of a staging branch worked extremely well in the two instances it was used (see PRs linked in the previous paragraph), the procedure outlined above is not perfect. Suggestions for improvement are much appreciated.
