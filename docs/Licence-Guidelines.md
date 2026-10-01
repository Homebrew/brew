---
last_review_date: "2026-07-18"
redirect_from:
  - /License-Guidelines
---

# Licence Guidelines

Formulae in `homebrew/core` must use a licence compatible with the [Debian Free Software Guidelines](https://wiki.debian.org/DFSGLicenses) or be released into the public domain under the [DFSG public-domain guidance](https://wiki.debian.org/DFSGLicenses#Public_Domain).

## Specifying a licence

Each licence is identified using an identifier from the [SPDX License List](https://spdx.org/licenses/).

Specify a licence by passing it to the `license` method:

```ruby
license "MIT"
```

The public domain can be indicated using a symbol:

```ruby
license :public_domain
```

If the licence for a formula cannot be represented using an SPDX expression:

```ruby
license :cannot_represent
```

## Complex SPDX licence expressions

Some formulae have multiple licences that need to be combined in different ways. In these cases, a more complex licence expression can be used. These expressions are based on the [SPDX License Expression Guidelines](https://spdx.github.io/spdx-spec/latest/annexes/spdx-license-expressions/).

Add a `+` to indicate that the user can choose a later version of the same licence:

```ruby
license "EPL-1.0+"
```

GNU licences (`GPL`, `LGPL`, `AGPL` and `GFDL`) require either the `-only` or the `-or-later` suffix to indicate whether a later version of the licence is allowed:

```ruby
license "LGPL-2.1-only"
```

```ruby
license "GPL-1.0-or-later"
```

Use `:any_of` to indicate that the user can choose which licence applies:

```ruby
license any_of: ["MIT", "0BSD"]
```

Use `:all_of` to indicate that the user must comply with multiple licences:

```ruby
license all_of: ["MIT", "0BSD"]
```

Use `:with` to indicate a licence exception:

```ruby
license "MIT" => { with: "LLVM-exception" }
```

These expressions can be nested as needed:

```ruby
license any_of: [
  "MIT",
  :public_domain,
  { all_of: ["0BSD", "Zlib", "Artistic-1.0+"],
  "Apache-2.0" => { with: "LLVM-exception" } },
]
```

## Specifying forbidden licences

The `HOMEBREW_FORBIDDEN_LICENSES` environment variable can be set to forbid installation of formulae that require or have dependencies that require certain licences.

`HOMEBREW_FORBIDDEN_LICENSES` should be set to a space-separated list of licences. Use `public_domain` to forbid installation of formulae with a `:public_domain` licence.

For example, the following forbids installation of `MIT`, `Artistic-1.0` and `:public_domain` licences:

```bash
export HOMEBREW_FORBIDDEN_LICENSES="MIT Artistic-1.0 public_domain"
```

In this example Homebrew would refuse to install any formula that specifies the `MIT` licence. Homebrew would also forbid installation of any formula that declares a dependency on a formula that specifies `MIT`, even if the original formula has an allowed licence.

Homebrew interprets complex licence expressions and determines whether the licences permit installation. To continue the above example, Homebrew would not allow installation of a formula with the following licence declarations:

```ruby
license any_of: ["MIT", "Artistic-1.0"]
```

```ruby
license all_of: ["MIT", "0BSD"]
```

Homebrew _would_ allow formulae with the following declaration to be installed:

```ruby
license any_of: ["MIT", "0BSD"]
```

`HOMEBREW_FORBIDDEN_LICENSES` can also forbid future versions of specific licences. For example, to forbid `Artistic-1.0`, `Artistic-2.0` and any future Artistic licences, use:

```bash
export HOMEBREW_FORBIDDEN_LICENSES="Artistic-1.0+"
```

For GNU licences (such as `GPL`, `LGPL`, `AGPL` and `GFDL`), use `-only` or `-or-later`. For example, the following would forbid `GPL-2.0`, `LGPL-2.1` and `LGPL-3.0` formulae from being installed, but would allow `GPL-3.0`:

```bash
export HOMEBREW_FORBIDDEN_LICENSES="GPL-2.0-only LGPL-2.1-or-later"
```
