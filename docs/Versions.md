---
last_review_date: "2026-04-05"
---

# Formulae Versions

[homebrew/core](https://github.com/homebrew/homebrew-core) supports multiple versions of formulae by using a special naming format. For example, the formula for GCC 9 is named `gcc@9.rb` and begins with `class GccAT9 < Formula`.

This page is about versioned formulae such as `foo@1.2`. Formula variants such
as `foo-full` are not versioned formulae: they are separate formulae used to
provide a different dependency or feature trade-off and follow the
[`Homebrew/homebrew-core` dependency policy]({% link Homebrew-homebrew-core-Maintainer-Guide.md %}#dependencies-and-full-variants)
instead.

## Acceptable versioned formulae

Versioned formulae we include in [homebrew/core](https://github.com/homebrew/homebrew-core) must meet the following standards:

* Versioned software should build on all of Homebrew's supported versions of macOS.
* Versioned formulae should differ in major/minor (not patch) versions from the current stable release. This is because patch versions indicate bug or security updates, and we want to ensure you apply security updates.
* Unstable versions (alpha, beta, development versions) are not acceptable for versioned (or unversioned) formulae.
* Upstream should have a release branch for each formula version, and have an explicit policy of releasing security updates for each version when necessary. For example, [PHP 7.0 was not a supported version but PHP 7.2 was](https://www.php.net/supported-versions.php) in January 2020. By contrast, most software projects are structured to only release security updates for their latest versions, so their earlier versions are not eligible for versioning.
* Versioned formulae should share a codebase with the main formula. If the project is split into a different repository, we recommend creating a new formula (`formula2` rather than `formula@2` or `formula@1`).
* Formulae that depend on versioned formulae must not depend on the same formulae at two different versions twice in their recursive dependencies. For example, if you depend on `openssl@1.0` and `foo`, and `foo` depends on `openssl` then you must instead use `openssl`.
* Versioned formulae should only be linkable at the same time as their non-versioned counterpart if the upstream project provides support for it, e.g. by using suffixed binaries. If this is not possible, use `keg_only :versioned_formula` to allow users to have multiple versions installed at once.
* A `keg_only :versioned_formula` should not `post_install` anything in the `HOMEBREW_PREFIX` that conflicts with or duplicates the main counterpart (or other versioned formulae). For example, a `node@6` formula should not install its `npm` into `HOMEBREW_PREFIX` like the `node` formula does.
* Submitted versioned formulae should be expected to be used by a large number of people. If this ceases to be the case, they will be removed. We will aim not to remove those in the [top 3,000 `install_on_request` formulae](https://brew.sh/analytics/install-on-request/).
* Versioned formulae should not have `resource`s that require security updates. For example, a `node@6` formula should not have an `npm` resource but instead rely on the `npm` provided by the upstream tarball.
* Versioned formulae should be as similar as possible and sensible compared to the main formulae. Creating or updating a versioned formula should be a chance to ask questions of the main formula and vice versa, e.g. can some unused or useless options be removed or made default?
* No more than five versions of a formula (including the main one) will be supported at any given time, unless they are popular (e.g. have over 1000 [analytics 90 days installs](https://formulae.brew.sh/analytics/install/90d/) of usage). When removing formulae that violate this, we will aim to do so based on usage and support status rather than age.
* Versioned formulae must be ABI-stable for the lifetime of the version branch. Updates to the versioned formula must not introduce ABI incompatibilities or otherwise require dependents to be revision bumped. In practice, this means that their dependents should never need `revision` bumps to be rebuilt against newer versions. Version updates which violate this should be rejected and the formula be deprecated from that point onwards.

## Locking installed formulae at specific versions

Homebrew's versions should not be used to "pin" formulae to your personal requirements. If a versioned formula already exists in `homebrew/core`, prefer that first: it remains supported and updated by Homebrew.

If you want something else, choose the smallest tool that fits:

### `brew pin`

Use `brew pin <formula>` when you want `brew upgrade` to stop upgrading a formula you already have installed.

Pros:

* simplest built-in option

Cons:

* you will not receive updates for that formula, including security updates, while it remains pinned
* pinned formulae can block installs or upgrades when other formulae require a newer version

### `$HOMEBREW_NO_AUTO_UPDATE`

Use `export HOMEBREW_NO_AUTO_UPDATE=1` when you want Homebrew to stop automatically refreshing formula and cask metadata until you choose to run `brew update`.

Pros:

* Homebrew only learns about newer versions when you explicitly run `brew update`

Cons:

* this does not itself stop `brew upgrade` from changing installed formulae
* you may miss fixes and security updates until you run `brew update`

If you are using `brew bundle`, combine this with `brew bundle --no-upgrade` or `export HOMEBREW_BUNDLE_NO_UPGRADE=1` if you also want `brew bundle` to stop upgrading installed dependencies.

### `brew bundle --no-upgrade` and `$HOMEBREW_BUNDLE_NO_UPGRADE`

Use `brew bundle --no-upgrade` or `export HOMEBREW_BUNDLE_NO_UPGRADE=1` when you want `brew bundle` to stop running `brew upgrade` on outdated dependencies.

Pros:

* simplest way to reduce churn in `brew bundle`

Cons:

* this does not pin versions or add lock file support
* `brew install` may still upgrade a dependency if needed
* you may miss fixes and security updates while using it

### `$HOMEBREW_NO_INSTALL_UPGRADE`

Use `export HOMEBREW_NO_INSTALL_UPGRADE=1` when you want `brew install <formula>` to stop upgrading an already installed but outdated formula.

Pros:

* avoids surprise upgrades from `brew install`

Cons:

* this does not pin versions
* this does not stop `brew upgrade`
* you may miss fixes and security updates while using it

### `$HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK`

Use `export HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK=1` when you want Homebrew to skip checking for outdated or broken installed dependents after installs, upgrades, or reinstalls.

Pros:

* can reduce cascading upgrades and reinstalls

Cons:

* this is not a version-freezing tool
* it can leave broken linkage or outdated dependents in place
* it may increase breakage from later `brew install` or `brew upgrade`

### `brew version-install`

Use `brew version-install` when you want a simpler workflow to extract a specific older formula version into your own tap and install it.

Pros:

* simplest way to start using an older formula version from your own tap

Cons:

* from that point on, you are responsible for updating, maintaining, fixing deprecations, and applying security updates for that formula

### `brew extract`

Use `brew extract` when you want the lower-level workflow and to manage the extracted formula file yourself in a tap. See [How to Create and Maintain a Tap](How-to-Create-and-Maintain-a-Tap.md#extracting-a-historical-formula-into-your-tap) for more information.

Pros:

* gives you the most control over the formula file in your own tap

Cons:

* this is the most manual option
* from that point on, you are responsible for updating, maintaining, fixing deprecations, and applying security updates for that formula

Homebrew supports these commands and local workflows, but it does not commit to maintaining every frozen or extracted formula version for you. Before submitting Homebrew issues, run `brew update` first and reproduce with current metadata. If you use `brew pin`, `$HOMEBREW_NO_AUTO_UPDATE`, `$HOMEBREW_BUNDLE_NO_UPGRADE`, `$HOMEBREW_NO_INSTALL_UPGRADE`, `$HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK`, `brew version-install`, or `brew extract`, you must only file issues when you can reproduce with core formulae. If you maintain formulae in your own tap, those formulae, their deprecations, and their security updates are your responsibility. If you or your organisation need long-term control over formula versions, [create your own tap](How-to-Create-and-Maintain-a-Tap.md). A `brew upgrade` breaking your local frozen or extracted formula is not an argument for Homebrew to add and maintain another historical version in `homebrew/core`.

If there is a formula that currently exists in the Homebrew/homebrew-core repository or has existed in the past (i.e. was migrated or deleted), you can recover it for your own use with the `brew version-install` command. This will install the desired version of the formula from your own custom tap. For example, if your project depends on `automake` 1.12 instead of the most recent version, you can obtain the `automake` formula at version 1.12 by running:

```sh
brew version-install automake@1.12
```

Formulae obtained this way may contain deprecated, disabled or removed Homebrew syntax (e.g. checksums may be `sha1` instead of `sha256`); the `brew version-install` command does not edit or update formulae to meet current standards and style requirements.

We may temporarily add versioned formulae for our own needs that do not meet these standards in [homebrew/core](https://github.com/homebrew/homebrew-core). The presence of a versioned formula there does not imply it will be maintained indefinitely or that we are willing to accept any more versions that do not meet the requirements above.
