---
last_review_date: "2026-07-18"
redirect_from:
  - /Checksum_Deprecation
---

# Checksum Requirements

Homebrew formulae and casks use SHA-256 checksums to verify downloaded files whose contents are expected to remain stable.
MD5 and SHA-1 are not supported for package integrity verification.

Use the SHA-256 digest of the exact file referenced by `url`:

```sh
shasum -a 256 /path/to/downloaded-file
```

Do not copy a checksum from an untrusted download mirror or disable verification to work around a mismatch.
A mismatch can indicate a corrupted download, an upstream file replaced without a version change or a compromised source.
Investigate which file changed and update the version, URL and checksum together when appropriate.

Formulae and casks in custom taps and local formula or cask files must follow the same requirement.
See the [`Formula#sha256` API](/rubydoc/Formula.html#sha256-class_method) and [Cask Cookbook](Cask-Cookbook.md#stanza-sha256) for syntax and exceptions.

## History

Homebrew removed MD5 checksums from core formulae in 2012 and blocked MD5-verified formulae in 2015.
SHA-1 support was removed in November 2016 after a 21-month migration period.
