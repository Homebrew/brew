---
last_review_date: "2025-06-16"
---

# Autobump List

[BrewTestBot](BrewTestBot.md) automatically checks for available updates of packages in autobump list. It means that some formulae and casks in official repositories do not have to be bumped manually by a contributor. Instead, every 3 hours, a GitHub Action ensures and a new pull request is opened if Homebrew does not provide the latest version of a formula/cask.

## Excluding packages from autobump list

By default, all new formulae and casks from [Homebrew/core](https://github.com/Homebrew/homebrew-core) and [Homebrew/cask](https://github.com/Homebrew/homebrew-cask) repositories are added to the list. To exclude a package from the list, it should satisfy one of the following:

1. The package is deprecated or disabled.
2. The The Livecheck block has a `skip` method.
3. It has a `no_autobump!` stanza.
4. (Casks only) The cask version is `:latest` or the Livecheck block uses the `:extract_plist` strategy.

To use the `no_autobump!` stanza, a reason for exclusion **must** be provided. The preferred way to set the reason is to use one of the available supported symbols. The list of these symbols can be found in the [`NO_AUTOBUMP_REASONS_LIST`](https://rubydoc.brew.sh/top-level-namespace.html#NO_AUTOBUMP_REASONS_LIST-constant) constants:

* `:incompatible_version_format`: This reason is used when the `brew bump` command cannot determine a version for the URL or update it. For example, if a tarball with the source code has a complex URL like `https://example.com/download/<major-version>/<minor-version>/foo-<full-version>-<git-commit>.tar.gz`, Homebrew wouldn't be able to replace the old URL with the new one automatically.
* `:bumped_by_upstream`: Some developers whose programs are available in Homebrew want to take care of the updates themselves or even set up a CI action that does this. This `no_autobump!` reason exists for such cases.
* `:requires_manual_review`: This is a temporary reason and expected to be deprecated in the future. It indicates that this package was not in the `autobump.txt` file before the new autobump list was introduced.

Some `no_autobump!` reasons also appear in the list but should not be used directly:

* `:extract_plist`: This reason is set if `livecheck` uses the `:extract_plist` strategy.
* `:latest_version`: This reason is set if `version` is set to `:latest`.

The reasons can be specified by their symbols:

```ruby
no_autobump! because: :bumped_by_upstream
```

If none of the reasons from above fit, a custom reason can be provided as a string:

```ruby
no_autobump! because: "some unique reason"
```

If there are multiple packages with a similar custom reason, it should be considered to add it to `NO_AUTOBUMP_REASONS_LIST`.
