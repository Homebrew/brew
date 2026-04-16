---
last_review_date: "2026-04-08"
---

# Deprecating, Disabling and Removing

Homebrew uses a three-stage lifecycle to remove formulae, casks and its own code (Ruby methods, CLI flags, environment variables and commands):

1. **Deprecated**: _should_ no longer be used. Users see a **warning** but the action proceeds.
2. **Disabled**: _cannot_ be used. Users see an **error** and the action fails.
3. **Removed**: the code or package is deleted entirely.

Items that are no longer acceptable or have been disabled for over a year should be removed. Disabled formulae in `homebrew/core` and disabled casks in `homebrew/cask` are **automatically removed one year after their disable date**.

## Formulae and casks

Formulae and casks use the `deprecate!` and `disable!` DSL to move through the lifecycle.

### `deprecate!`

Add a `deprecate!` call with a date in ISO 8601 format and a reason:

```ruby
deprecate! date: "YYYY-MM-DD", because: :reason
```

- `date:` should be the date the deprecation period begins (usually today). A future date delays the deprecation until that date. Do not backdate as it causes confusion.
- `because:` can be a preset symbol or a custom string (see [Deprecate and Disable Reasons](#deprecate-and-disable-reasons)).
- An optional `replacement_formula:` or `replacement_cask:` string suggests a replacement to the user.

```ruby
deprecate! date: "YYYY-MM-DD", because: :reason, replacement_formula: "foo"
```

### `disable!`

Add a `disable!` call with the same parameters:

```ruby
disable! date: "YYYY-MM-DD", because: :reason
```

- `date:` should be the date the reason for disabling came into effect. A future date means the formula or cask is deprecated until that date and then becomes disabled.
- `replacement_formula:` and `replacement_cask:` work the same as for `deprecate!`.

### When to deprecate formulae

Formulae should be deprecated if at least one of the following are true:

- the formula does not build on any supported OS versions
- the software has outstanding CVEs
- the software has been discontinued or abandoned upstream
- the formula has [zero installs in the last 90 days](https://formulae.brew.sh/analytics/install/90d/)

Formulae with dependents should not be deprecated unless all dependents are also deprecated. Deprecated formulae should continue to be maintained so they still build from source and their bottles continue to work. If this is not possible, they should be disabled.

### When to deprecate casks

Casks should be deprecated if at least one of the following are true:

- the software fails macOS Gatekeeper checks for supported OS versions
- the software cannot be run on any supported OS versions
- the software has outstanding CVEs
- the software has been discontinued or abandoned upstream
- the cask has [zero installs in the last 90 days](https://formulae.brew.sh/analytics/cask-install/90d/)

Deprecated casks should continue to be maintained if they continue to be installable. If not, they should be immediately disabled.

### When to disable formulae

Formulae should be disabled when they cannot be built from source on any supported OS version, have been deprecated for a long time, or have no license. Popular formulae (more than 1000 [installs in the last 90 days](https://formulae.brew.sh/analytics/install/90d/)) should not be disabled without a deprecation period of at least six months. Unpopular formulae can be disabled immediately and manually removed three months after their disable date.

### When to disable casks

Casks should be disabled when they cannot be installed on any supported OS version, have been deprecated for a long time, or the upstream URL has been removed. Popular casks (more than 300 [installs in the last 90 days](https://formulae.brew.sh/analytics/cask-install/90d/)) should not be disabled without a deprecation period of at least six months unless the issue is unfixable. Unpopular casks can be disabled immediately and manually removed three months after their disable date.

### When to remove formulae

A formula should be removed if it does not meet the criteria for [acceptable formulae](Acceptable-Formulae.md) or [versioned formulae](Versions.md), has a non-open-source license, or has been disabled for over a year.

### When to remove casks

A cask should be removed if it has been disabled for over a year, or immediately in exceptional circumstances.

### Deprecate and Disable Reasons

A reason must be provided when deprecating or disabling. The preferred way is to use a preset symbol from the [`DeprecateDisable` module](/rubydoc/DeprecateDisable.html). Custom strings are also accepted and should fit the sentence `<name> has been deprecated/disabled because it <reason>!`.

```ruby
# Good: "fetches unversioned dependencies at runtime" fits the sentence
deprecate! date: "2020-01-01", because: "fetches unversioned dependencies at runtime"

# Bad: "invalid license" does not fit the sentence
disable! date: "2020-01-01", because: "invalid license"
```

**Formula reasons:**

- `:does_not_build`: cannot be built from source on any supported macOS version or Linux
- `:no_license`: no identifiable license
- `:repo_archived`: upstream repository archived with no usable replacement
- `:repo_removed`: upstream repository removed with no usable replacement
- `:unmaintained`: project abandoned (no commits for a year and unresolved critical bugs or CVEs; note: some software is "done" — inactivity alone does not imply removal)
- `:unsupported`: compilation not supported by upstream (e.g. only supports macOS older than 10.15)
- `:deprecated_upstream`: deprecated upstream with no usable replacement
- `:versioned_formula`: versioned formula that no longer [meets the requirements](Versions.md)
- `:checksum_mismatch`: source checksum changed since bottles were built with no reputable justification

**Cask reasons:**

- `:discontinued`: discontinued upstream
- `:moved_to_mas`: now exclusively on the Mac App Store
- `:no_longer_available`: no longer available upstream
- `:no_longer_meets_criteria`: no longer meets the criteria for acceptable casks
- `:unmaintained`: not maintained upstream
- `:fails_gatekeeper_check`: fails macOS Gatekeeper checks

## Code

Homebrew also deprecates, disables and removes its own code using `odeprecated`/`odisabled` rather than the `deprecate!`/`disable!` DSL.

### API classification

The API classification determines whether a deprecation period is required.

**Public APIs** require the full deprecation lifecycle before removal:

- documented environment variables (e.g. `HOMEBREW_*` variables in the [manual page](Manpage.md))
- CLI flags and commands documented in the [manual page](Manpage.md)
- Ruby methods annotated with `@api public` (visible in the [Ruby API documentation](/rubydoc/index.html))
- DSL methods documented in the [Formula Cookbook](Formula-Cookbook.md) or [Cask Cookbook](Cask-Cookbook.md)

**Internal APIs** do not require a deprecation period. These are methods in `Homebrew/brew` that are used by `homebrew/core` or `homebrew/cask` but are not documented for external use, or are specifically annotated with `@api internal`.

**Private APIs** do not require a deprecation period. These are implementation details in `Homebrew/brew` that are never used outside `Homebrew/brew` itself. They are likely to change at any time without notice.

### When to deprecate code

Public APIs (see [API classification](#api-classification)) should be deprecated if at least one of the following are true:

- the feature is no longer needed on currently supported macOS or Linux versions
- a better replacement exists and the old API creates confusion or support burden
- the feature has no Homebrew test coverage and is only used by third-party taps
- the feature generates a disproportionate number of support requests or bug reports
- the behaviour is unsafe or encourages patterns that lead to broken installations
- the feature has [zero or negligible usage](Analytics.md) based on analytics or repository search

Internal and private APIs (see [API classification](#api-classification)) can be changed or removed at any time without deprecation.

### When to disable code

A deprecated public API should be disabled (moved from `odeprecated` to `odisabled`) at the next minor or major release after the one in which it was deprecated. This gives users at least one full release cycle to migrate.

### When to remove code

Disabled code (`odisabled`) should be deleted at the next minor or major release after the one in which it was disabled.

### The deprecation lifecycle

Public APIs go through four stages. Each transition happens at a **minor or major release** (e.g. 5.0.0 or 5.1.0), never a patch release. See [Releases](Releases.md) for the full release process.

**1. `# odeprecated` (commented placeholder)** — A comment is added as a reminder. No user-visible effect.

```ruby
# odeprecated "ENV.no_weak_imports"
append "LDFLAGS", "-Wl,-no_weak_imports" if no_weak_imports_support?
```

**2. `odeprecated` (active deprecation)** — The comment is uncommented. Users see a warning; developers (`HOMEBREW_DEVELOPER=1`) see an error. A replacement can be suggested.

```ruby
odeprecated "ENV.no_weak_imports"
```

**3. `odisabled` (disabled)** — All users see an error.

```ruby
odisabled "ENV.no_weak_imports"
```

**4. Removal** — The `odisabled` call and all supporting code are deleted.

| Release | State | User experience |
| ------- | ----- | --------------- |
| 5.0.0 | `# odeprecated "Formula#my_method"` added | No visible change |
| 5.1.0 | Uncommented to `odeprecated "Formula#my_method", "Formula#new_method"` | Warning printed |
| 5.2.0 | Changed to `odisabled "Formula#my_method", "Formula#new_method"` | Error raised |
| 5.3.0 | Code deleted | Method no longer exists |

### CLI flags

The `switch` method in the CLI argument parser accepts `odeprecated:` and `odisabled:` parameters:

```ruby
switch "--my-flag",
       description: "Do something.",
       odeprecated: true,
       replacement: "--new-flag"
```

When `odeprecated: true`, the flag is hidden from `--help` and completions and prints a warning when used. When `odisabled: true`, using the flag raises an error. At the removal stage, delete the flag definition and any `replacement:` parameter.

### Environment variables

Environment variables follow the same four-stage lifecycle. Include migration logic to copy the old value during the transition:

```ruby
if (old_value = ENV["HOMEBREW_OLD_VAR"].presence)
  opoo "`HOMEBREW_OLD_VAR` is deprecated. Use `HOMEBREW_NEW_VAR` instead."
  # odeprecated "HOMEBREW_OLD_VAR", "HOMEBREW_NEW_VAR"
  ENV["HOMEBREW_NEW_VAR"] = old_value
end
```

The `# odeprecated` comment is then uncommented, changed to `odisabled` and finally removed following the standard lifecycle.
