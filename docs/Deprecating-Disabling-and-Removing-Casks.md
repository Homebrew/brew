---
last_review_date: "1970-01-01"
---

# Deprecating, Disabling and Removing Casks

There are many reasons why casks may be deprecated, disabled or removed. This document explains the differences between each method as well as explaining when one method should be used over another.

## Overview

These general rules of thumb can be followed:

- `deprecate!` should be used for casks that _should_ no longer be used.
- `disable!` should be used for casks that _cannot_ be used.
- Casks that are no longer acceptable in `homebrew/cask` or have been disabled for over a year _should_ be removed.

## Deprecation

If a user attempts to install a deprecated cask, they will be shown a warning message but the install will proceed.

A cask should be deprecated to indicate to users that the cask should not be used and will be disabled in the future. Deprecated casks should continue to be maintained by the Homebrew maintainers if they continue to be installable. If this is not possible, they should be immediately disabled.

The most common reasons for deprecation are when the upstream project is deprecated, unmaintained or archived.

Casks should only be deprecated if at least one of the following are true:

- the software installed by the cask cannot be run on any of our supported macOS versions
- the cask has outstanding CVEs
- the cask has [zero installs in the last 90 days](https://formulae.brew.sh/analytics/cask-install/90d/)
- the software installed by the cask has been discontinued upstream

To deprecate a cask, add a `deprecate!` call. This call should include a deprecation date in the ISO 8601 format and a deprecation reason:

```ruby
deprecate! date: "YYYY-MM-DD", because: :reason
```

The `date` parameter should be set to the date that the deprecation period should begin, which is usually today's date. If the `date` parameter is set to a date in the future, the cask will not become deprecated until that date. This can be useful if the upstream developers have indicated a date when the project or version will stop being supported. Do not backdate the `date` parameter as it causes confusion for users and maintainers.

The `because` parameter can be a preset reason (using a symbol) or a custom reason. See the [Deprecate and Disable Reasons](#deprecate-and-disable-reasons) section below for more details about the `because` parameter.

An optional `replacement` parameter may also be specified to suggest a replacement formula or cask to the user. The value of the parameter is a string.

```ruby
deprecate! date: "YYYY-MM-DD", because: :reason, replacement: "foo"
```

## Disabling

If a user attempts to install a disabled cask, they will be shown an error message and the install will fail.

A cask should be disabled to indicate to users that the cask cannot be used and will be removed in the future. Disabled cask are those that could not be installed successfully any longer.

The most common reasons for disabling a cask are:

- it cannot be installed on any of our supported macOS versions
- it has been deprecated for a long time
- the upstream URL has been removed

Popular casks (e.g. have more than 300 [analytics installs in the last 90 days](https://formulae.brew.sh/analytics/cask-install/90d/)) should not be disabled without a deprecation period of at least six months unless they cannot be installed on all macOS versions and issue is unable be fixed (e.g. download URL no longer works and a mirror cannot be sourced).

Unpopular casks (e.g. have fewer than 300 [analytics installs in the last 90 days](https://formulae.brew.sh/analytics/cask-install/90d/)) can be disabled immediately for any of the reasons above.
They can be manually removed three months after their disable date.

To disable a cask, add a `disable!` call. This call should include a deprecation date (in the ISO 8601 format) and a deprecation reason:

```ruby
disable! date: "YYYY-MM-DD", because: :reason
```

The `date` parameter should be set to the date that the reason for disabling came into effect. If there is no clear date but the cask needs to be disabled, use today's date. If the `date` parameter is set to a date in the future, the cask will be deprecated until that date (on which the cask will become disabled).

The `because` parameter can be a preset reason (using a symbol) or a custom reason. See the [Deprecate and Disable Reasons](#deprecate-and-disable-reasons) section below for more details about the `because` parameter.

Similar to deprecated casks, an optional `replacement` parameter may also be specified for disabled casks to suggest a replacement formula or cask to the user. The value of the parameter is a string.

```ruby
disable! date: "YYYY-MM-DD", because: :reason, replacement: "foo"
```

## Removal

A cask should be removed if it does not meet our criteria for [acceptable casks](Acceptable-Casks.md) or has been disabled for over a year.

**Note: disabled casks in `homebrew/cask` will be automatically removed one year after their disable date.**

## Deprecate and Disable Reasons

When a cask is deprecated or disabled, a reason explaining the action must be provided.

There are two ways to indicate the reason. The preferred way is to use a pre-existing symbol to indicate the reason. The available symbols are listed below and can be found in the [`DeprecateDisable` module](https://github.com/Homebrew/brew/blob/master/Library/Homebrew/deprecate_disable.rb):

- `:discontinued`: the cask is discontinued upstream
- `:no_longer_available`: the cask is no longer available upstream
- `:unmaintained`: the cask is not maintained upstream

These reasons can be specified by their symbols (the comments show the message that will be displayed to users):

```ruby
# Warning: <cask> has been deprecated because it is discontinued upstream!
deprecate! date: "2020-01-01", because: :discontinued
```

If these pre-existing reasons do not fit, a custom reason can be specified. Such reasons should be written to fit into the sentence `<cask> has been deprecated/disabled because it <reason>!`.

A well-worded example of a custom reason would be:

```ruby
# Warning: <cask> has been deprecated because it has unresolved CVEs!
deprecate! date: "2020-01-01", because: "has unresolved CVEs"
```

A poorly-worded example of a custom reason would be:

```ruby
# Error: <cask> has been disabled because it broken!
disable! date: "2020-01-01", because: "broken"
```
