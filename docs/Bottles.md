---
last_review_date: "2026-07-18"
---

# Bottles (Binary Packages)

Bottles are produced by installing a formula with `brew install --build-bottle <formula>` and then bottling it with `brew bottle <formula>`. This generates a bottle file in the current directory and outputs the bottle DSL for insertion into the formula file.

## Usage

When the formula being installed defines a bottle matching your system, it will be downloaded and installed automatically when you run `brew install <formula>`.

Bottles are not used when:

- the user requests it (by specifying `--build-from-source`),
- the formula requests it (with `pour_bottle?`),
- any options are specified during installation (bottles are all compiled with default options),
- the bottle is not up to date (e.g. missing or mismatched checksum),
- the bottle's `cellar` is neither relocatable nor compatible with the current `HOMEBREW_PREFIX` and `HOMEBREW_CELLAR`.

## Creation

Bottles for `homebrew/core` formulae are created by [BrewTestBot](BrewTestBot.md) when a pull request is submitted. If the formula builds successfully on each supported platform and a maintainer approves the change, BrewTestBot updates its `bottle do` block and uploads each bottle to [GitHub Packages](https://github.com/orgs/Homebrew/packages).

By default, Homebrew targets the oldest CPU generation supported for the operating system and architecture being bottled.
For 64-bit x86 builds, the baseline is Core 2 unless the platform definition specifies a newer minimum.
This makes the bottle usable across the supported hardware range.

Use `--bottle-arch=` only when the formula intentionally requires another architecture and its compatibility has been reviewed.
A bottle built for a newer CPU can fail with an illegal-instruction error on older supported hardware.

## Format

Bottles are simple gzipped tarballs of compiled binaries.
The formula name, version, target operating system and rebuild version are stored in the filename.
Other metadata is in the formula's bottle DSL, and the formula definition is located within the bottle at `<formula>/<version>/.brew/<formula>.rb`.

## Bottle DSL (domain specific language)

Bottles are specified in formula definitions by a DSL contained within a `bottle do ... end` block.

A simple (and typical) example:

```ruby
bottle do
  sha256 arm64_tahoe: "a9ae578b05c3da46cedc07dd428d94a856aeae7f3ef80a0f405bf89b8cde893a"
  sha256 tahoe:       "5dc376aa20241233b76e2ec2c1d4e862443a0250916b2838a1ff871e8a6dc2c5"
  sha256 sequoia:     "924afbbc16549d8c2b80544fd03104ff8c17a4b1460238e3ed17a1313391a2af"
end
```

A full example:

```ruby
bottle do
  root_url "https://example.com"
  rebuild 4
  sha256 cellar: "/opt/homebrew/Cellar", arm64_tahoe: "a9ae578b05c3da46cedc07dd428d94a856aeae7f3ef80a0f405bf89b8cde893a"
  sha256 cellar: :any,                   tahoe:       "5dc376aa20241233b76e2ec2c1d4e862443a0250916b2838a1ff871e8a6dc2c5"
  sha256                                 sequoia:     "924afbbc16549d8c2b80544fd03104ff8c17a4b1460238e3ed17a1313391a2af"
end
```

Use the `all:` tag for a platform-independent bottle whose contents are identical and usable on every supported operating system and architecture.

### Root URL (`root_url`)

Optionally contains the URL root used to determine bottle URLs.

By default this is omitted and Homebrew's default bottle URL root is used. This may be useful for taps that wish to provide bottles for their formulae or cater to a non-default `HOMEBREW_CELLAR`.

### Cellar (`cellar`)

Optionally contains the value of `HOMEBREW_CELLAR` in which the bottles were built.

Most compiled software contains references to its compiled location, preventing it from being simply relocated anywhere on disk. A value of `:any` or `:any_skip_relocation` means that the bottle can be safely installed in any Cellar as it did not contain any references to the Cellar in which it was originally built. This can be omitted if the bottle was compiled for the given OS/architecture's default `HOMEBREW_CELLAR`, as is done for all bottles built by BrewTestBot.

### Rebuild version (`rebuild`)

Optionally contains the rebuild version of the bottle.

Sometimes a bottle must be updated without changing the formula version or revision, such as after a bottle-only packaging correction.
In that case `rebuild` has a value of `1` or greater.

### Checksum (`sha256`)

Contains the SHA-256 hash of the bottle for the given OS/architecture.

## Formula DSL

An additional bottle-related method is available in the formula DSL.

### Pour bottle (`pour_bottle?`)

Optionally returns a boolean to indicate whether a bottle should be used when installing this formula.

For example a bottle may break if a related formula has been compiled with non-default options, so this method could check for that case and return `false`.

A full example:

```ruby
pour_bottle? do
  reason "The bottle needs to be installed into #{Homebrew::DEFAULT_PREFIX}."
  satisfy { HOMEBREW_PREFIX.to_s == Homebrew::DEFAULT_PREFIX }
end
```

Commonly used `pour_bottle?` conditions can be added as preset symbols to the `pour_bottle?` method, allowing them to be specified like this:

```ruby
pour_bottle? only_if: :default_prefix
pour_bottle? only_if: :clt_installed
```
