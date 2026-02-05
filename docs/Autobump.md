---
last_review_date: "2025-08-06"
---

# Autobump

In official repositories, [BrewTestBot](BrewTestBot.md) automatically checks for available updates to packages that are in Homebrew's "autobump list". These packages do not need to be bumped (i.e. have their version number increased) manually by a contributor. Instead, every 3 hours, a GitHub Action opens a new pull request to upgrade them to the latest version, if needed.

## Excluding packages from autobumping

By default, all new formulae and casks from the [Homebrew/core](https://github.com/Homebrew/homebrew-core) and [Homebrew/cask](https://github.com/Homebrew/homebrew-cask) repositories are autobumped. To exclude a package from the autobump list, it must have one of the following:

* an active `deprecate!` or `disable!` call
* a `livecheck do` block containing a `skip` call
* a `no_autobump!` call

Other formula and cask specific reasons for why a package is not autobumped are listed in the [Formula Cookbook](Formula-Cookbook.md) and [Cask Cookbook](Cask-Cookbook.md) respectively.

## Autobump exclusion reasons

When using `no_autobump!`, a reason for exclusion must be provided.

There are two ways to indicate the reason. The preferred way is to use a pre-existing symbol, which can be found in [`NO_AUTOBUMP_REASONS_LIST`](/rubydoc/top-level-namespace.html#NO_AUTOBUMP_REASONS_LIST-constant), for example:

```ruby
no_autobump! because: :bumped_by_upstream
```

If these pre-existing reasons do not fit, a custom reason can be specified:

```ruby
no_autobump! because: "some unique reason"
```

If there are multiple packages with a similar custom reason, it can be added as a new symbol to `NO_AUTOBUMP_REASONS_LIST`.
