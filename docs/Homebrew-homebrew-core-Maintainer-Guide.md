---
last_review_date: "1970-01-01"
---

# Homebrew/homebrew-core Maintainer Guide

## Quick merge checklist

A detailed checklist can be found [below](#detailed-merge-checklist). This is all that really matters:

- Ensure the name seems reasonable.
- Add aliases.
- Ensure it uses `keg_only :provided_by_macos` if it already comes with macOS.
- Ensure it is not a library that can be installed with [gem](https://en.wikipedia.org/wiki/RubyGems), [cpan](https://en.wikipedia.org/wiki/Cpan) or [pip](https://pip.pypa.io/en/stable/).
- Ensure that any dependencies are accurate and minimal. We don't need to support every possible optional feature for the software.
- When bottles aren't required or affected, use the GitHub squash & merge workflow for a single-formula PR or rebase & merge workflow for a multiple-formulae PR. See the [How to merge without bottles](#how-to-merge-without-bottles) section below for more details.
- Use `brew pr-publish` or `brew pr-pull` otherwise, which adds messages to auto-close pull requests and pull bottles built by BrewTestBot.
- Thank people for contributing.

Checking dependencies is important, because they will probably stick around forever. Nobody really checks if they are necessary or not.

Depend on as little stuff as possible. Disable X11 functionality if possible. For example, we build Wireshark, but not the heavy GUI.

Homebrew is about Unix software. Stuff that builds to an `.app` should be in Homebrew Cask instead.

## Merging, rebasing, cherry-picking

For most PRs that make formula modifications, you can simply approve the PR and an automatic merge (with bottles) will be performed by [@BrewTestBot](https://github.com/BrewTestBot). See [BrewTestBot for Maintainers](BrewTestBot-For-Maintainers.md) for more information.

Certain PRs may not be merged automatically by [@BrewTestBot](https://github.com/BrewTestBot), even after they've been approved. This includes PRs with the `new formula` and `automerge-skip` labels. To trigger a merge for these PRs, run `brew pr-publish`.

PRs modifying formulae that don't need bottles or making changes that don't require new bottles to be pulled should use GitHub's squash & merge or rebase & merge workflows.

Otherwise, you should use `brew pr-pull` (or `rebase`/`cherry-pick` contributions).

Don’t `rebase` until you finally `push`. Once `master` is pushed, you can’t `rebase`: **you’re a maintainer now!**

Cherry-picking changes the date of the commit, which kind of sucks.

Don’t `merge` unclean branches. So if someone is still learning `git` and their branch is filled with nonsensical merges, then `rebase` and squash the commits. Our main branch history should be useful to other people, not confusing.

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

We need to at least check that it builds. Use [BrewTestBot](BrewTestBot.md) for this.

Verify the formula works if possible. If you can’t tell (e.g. if it’s a library) trust the original contributor; it worked for them, so chances are it is fine. If you aren’t an expert in the tool in question, you can’t really gauge if the formula installed the program correctly. At some point an expert will come along, cry blue murder that it doesn’t work, and fix it. This is how open source works. Ideally, request a `test do` block to test that functionality is consistently available.

If the formula uses a repository, then the `url` parameter should have a tag or revision. `url`s have versions and are stable (not yet implemented!).

Don't merge any formula updates with failing `brew test`s. If a `test do` block is failing it needs to be fixed. This may involve replacing more involved tests with those that are more reliable. This is fine: false positives are better than false negatives as we don't want to teach maintainers to merge red PRs. If the test failure is believed to be due to a bug in `Homebrew/brew` or the CI system, that bug must be fixed, or worked around in the formula to yield a passing test, before the PR can be merged.

## Duplicates

We now accept stuff that comes with macOS as long as it uses `keg_only :provided_by_macos` to be keg-only by default.

## Removing formulae

Formulae that:

- work on at least 2/3 of our supported macOS versions in the default Homebrew prefix
- do not require patches rejected by upstream to work
- do not have known security vulnerabilities or CVEs for the version we package
- are shown to be still installed by users in our analytics with a `BuildError` rate of <25%

should not be removed from Homebrew. The exception to this rule are [versioned formulae](Versions.md) for which there are higher standards of usage and a maximum number of versions for a given formula.

For more information about deprecating, disabling and removing formulae, see the [Deprecating, Disabling and Removing Formulae](Deprecating-Disabling-and-Removing-Formulae.md) page.

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
        brew bump-revision --message 'for libuv' urbit

    - make sure it has one commit per revision bump
- if CI is green and...
  - bottles need to be pulled, and...
    - the commits are correct, don't need changes, and BrewTestBot can merge it (doesn't have the label `automerge-skip`): approve the PR to trigger an automatic merge (use `brew pr-publish $PR_ID` to trigger manually in case of a new formula)
    - the commits are correct and don't need changes, but BrewTestBot can't merge it (has the label `automerge-skip`): use `brew pr-publish $PR_ID`
    - the commits need to be amended: use `brew pr-pull $PR_ID`, make changes, and `git push`
- don't forget to thank the contributor
  - celebrate any first-time contributors
- suggest using `brew bump-formula-pr` next time if this was not the case

## Common build failures and how to handle them

### Test errors

#### "undefined reference to ..."

This error might pop up when parameters passed to `gcc` are in the wrong order.

An example from `libmagic` formula:

    ==> brew test libmagic --verbose
    Testing libmagic
    ==> /usr/bin/gcc -I/home/linuxbrew/.linuxbrew/Cellar/libmagic/5.38/include -L/home/linuxbrew/.linuxbrew/Cellar/libmagic/5.38/lib -lmagic test.c -o test
    /tmp/ccNeDVRt.o: In function `main':
    test.c:(.text+0x15): undefined reference to `magic_open'
    test.c:(.text+0x4a): undefined reference to `magic_load'
    test.c:(.text+0x81): undefined reference to `magic_file'
    collect2: error: ld returned 1 exit status

Solution:

```ruby
if OS.mac?
  system ENV.cc, "-I#{include}", "-L#{lib}", "-lmagic", "test.c", "-o", "test"
else
  system ENV.cc, "test.c", "-I#{include}", "-L#{lib}", "-lmagic", "-o", "test"
end
```

For an explanation of why this happens, read the [Ubuntu 11.04 Toolchain documentation](https://wiki.ubuntu.com/NattyNarwhal/ToolchainTransition).

## Staging Branches

### Summary

Some formulae (e.g. Python, OpenSSL, ICU, Boost) have a large number of dependents. This makes updating these formulae (or their dependents) difficult because the standard procedure involves updating a large number of formulae in a single pull request. An alternative procedure that can significantly simplify this process is to use a staging branch.

The idea of using a staging branch is to merge updates and publish bottles for the affected formula to a non-default branch. This allows work to be done incrementally in smaller PRs, instead of in one giant PR that touches many formulae. When the staging branch is ready, it can be merged to the `master`/default branch.

Before making use of a staging branch, there is one important disadvantage to consider: once you have merged bottle updates to the staging branch, it is **very difficult** to take them back. This typically involves deleting uploaded bottles, which will occasionally require an owner of the Homebrew GitHub organisation to delete uploaded bottles one at a time.

### How to use a staging branch

Here is a rough outline of how to use a staging branch:

1. Create the staging branch in [Homebrew/homebrew-core](https://github.com/Homebrew/homebrew-core). The name of the staging branch _must_ start with the name of the root formula, followed by a `-`, and end in `-staging`. You can omit the `@` and anything that follows for versioned formulae (e.g. `icu4c-staging`, `openssl-migration-staging`, `python@3.12-staging`). It might be helpful to look at the [code](https://github.com/Homebrew/brew/blob/3db1acf3e38e270af4e1c3f214622bbfb18f830e/Library/Homebrew/formula_auditor.rb#L357-L375) that parses the branch names to check whether a PR targets a staging branch.

1. Open an issue in homebrew-core inviting contributors to help. Be sure to include instructions for how to do so, and a checklist of formulae that need to be updated. See [Homebrew/homebrew-core#134251](https://github.com/Homebrew/homebrew-core/issues/134251) for an example.

1. Open a _draft_ PR that merges the staging branch into the `master` branch. This allows you to keep track of the work done so far. You may wish to apply the [`no long build conflict`](https://github.com/Homebrew/homebrew-core/labels/no%20long%20build%20conflict) label to this PR to avoid conflicting changes from being merged to the `master` branch.

1. Open PRs targeting the staging branch that update the affected formulae. Each PR should touch as few formulae as possible. The typical PR that targets the staging branch will update only one formula at a time. Staging branch PRs can be merged using the same process as PRs that target the `master` branch. Ideally, these PRs should be opened in [topological order](https://en.wikipedia.org/wiki/Topological_sorting) according to the dependency graph, but we don't currently have good tooling for generating a topological sort. (Help wanted.)

1. Label PRs that target the staging branch with the [`staging-branch-pr`](https://github.com/Homebrew/homebrew-core/labels/staging-branch-pr) label for ease of tracking and review. (TODO: Add some automation for this to homebrew-core.)

1. Monitor the draft PR you created in step 3 above for merge conflicts. If you encounter a merge conflict, you must resolve those conflicts in a staging branch PR that merges the `master` branch into the staging branch.

1. When the staging branch is ready to be merged into `master`, mark the draft PR as ready for review and merge it into the `master` branch. Your PR may spend a long time in the merge queue waiting for the bottle fetch tests to run.

For examples of uses of the staging branch, see homebrew-core PRs labelled [`openssl-3-migration-staging`](https://github.com/Homebrew/homebrew-core/labels/openssl-3-migration), [Homebrew/homebrew-core#134260](https://github.com/Homebrew/homebrew-core/pull/134260), or [Homebrew/homebrew-core#133611](https://github.com/Homebrew/homebrew-core/pull/133611).

Finally: while the use of a staging branch worked extremely well in the two instances it was used (see PRs linked in the previous paragraph), the procedure outlined above is not perfect. Suggestions for improvement are much appreciated.
