---
last_review_date: "1970-01-01"
---

# License Guidelines

We only accept formulae that use a [Debian Free Software Guidelines license](https://wiki.debian.org/DFSGLicenses) or are released into the public domain following [DFSG Guidelines on Public Domain software](https://wiki.debian.org/DFSGLicenses#Public_Domain) into `homebrew/core`.

## Specifying a License

All licenses are identified by their license identifier from the [SPDX License List](https://spdx.org/licenses/).

Specify a license by passing it to the `license` method:

```ruby
license "MIT"
```

The public domain can be indicated using a symbol:

```ruby
license :public_domain
```

If the license for a formula cannot be represented using an SPDX expression:

```ruby
license :cannot_represent
```

## Complex SPDX License Expressions

Some formulae have multiple licenses that need to be combined in different ways. In these cases, a more complex license expression can be used. These expressions are based on the [SPDX License Expression Guidelines](https://spdx.github.io/spdx-spec/latest/annexes/spdx-license-expressions/).

Add a `+` to indicate that the user can choose a later version of the same license:

```ruby
license "EPL-1.0+"
```

GNU licenses (`GPL`, `LGPL`, `AGPL` and `GFDL`) require either the `-only` or the `-or-later` suffix to indicate whether a later version of the license is allowed:

```ruby
license "LGPL-2.1-only"
```

```ruby
license "GPL-1.0-or-later"
```

Use `:any_of` to indicate that the user can choose which license applies:

```ruby
license any_of: ["MIT", "0BSD"]
```

Use `:all_of` to indicate that the user must comply with multiple licenses:

```ruby
license all_of: ["MIT", "0BSD"]
```

Use `:with` to indicate a license exception:

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

## Specifying Forbidden Licenses

The `HOMEBREW_FORBIDDEN_LICENSES` environment variable can be set to forbid installation of formulae that require or have dependencies that require certain licenses.

The `HOMEBREW_FORBIDDEN_LICENSES` should be set to a space-separated list of licenses. Use `public_domain` to forbid installation of formulae with a `:public_domain` license.

For example, the following forbids installation of `MIT`, `Artistic-1.0` and `:public_domain` licenses:

```bash
export HOMEBREW_FORBIDDEN_LICENSES="MIT Artistic-1.0 public_domain"
```

In this example Homebrew would refuse to install any formula that specifies the `MIT` license. Homebrew would also forbid installation of any formula that declares a dependency on a formula that specifies `MIT`, even if the original formula has an allowed license.

Homebrew interprets complex license expressions and determines whether the licenses allow installation. To continue the above example, Homebrew would not allow installation of a formula with the following license declarations:

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

`HOMEBREW_FORBIDDEN_LICENSES` can also forbid future versions of specific licenses. For example, to forbid `Artistic-1.0`, `Artistic-2.0` and any future Artistic licenses, use:

```bash
export HOMEBREW_FORBIDDEN_LICENSES="Artistic-1.0+"
```

For GNU licenses (such as `GPL`, `LGPL`, `AGPL` and `GFDL`), use `-only` or `-or-later`. For example, the following would forbid `GPL-2.0`, `LGPL-2.1` and `LGPL-3.0` formulae from being installed, but would allow `GPL-3.0`:

```bash
export HOMEBREW_FORBIDDEN_LICENSES="GPL-2.0-only LGPL-2.1-or-later"
```
