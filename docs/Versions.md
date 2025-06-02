---
last_review_date: "1970-01-01"
---

# Formulae Versions

[homebrew/core](https://github.com/homebrew/homebrew-core) supports multiple versions of formulae by using a special naming format. For example, the formula for GCC 9 is named `gcc@9.rb` and begins with `class GccAT9 < Formula`.

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

Homebrew's versions should not be used to "pin" formulae to your personal requirements. You should instead [create your own tap](How-to-Create-and-Maintain-a-Tap.md) for formulae you or your organisation wish to control the versioning of, or those that do not meet the above standards. Software that has regular API or ABI breaking releases still needs to meet all the above requirements; that a `brew upgrade` has broken something for you is not an argument for us to add and maintain a formula for you.

If there is a formula that currently exists in the Homebrew/homebrew-core repository or has existed in the past (i.e. was migrated or deleted), you can recover it for your own use with the `brew extract` command. This will copy the desired version of the formula into a custom tap. For example, if your project depends on `automake` 1.12 instead of the most recent version, you can obtain the `automake` formula at version 1.12 by running:

```sh
brew extract automake --version=1.12 <YOUR_GITHUB_USER>/<YOUR_TAP_REPOSITORY_NAME>
```

Formulae obtained this way may contain deprecated, disabled or removed Homebrew syntax (e.g. checksums may be `sha1` instead of `sha256`); the `brew extract` command does not edit or update formulae to meet current standards and style requirements.

We may temporarily add versioned formulae for our own needs that do not meet these standards in [homebrew/core](https://github.com/homebrew/homebrew-core). The presence of a versioned formula there does not imply it will be maintained indefinitely or that we are willing to accept any more versions that do not meet the requirements above.
