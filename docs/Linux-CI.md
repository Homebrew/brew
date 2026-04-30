---
last_review_date: "2026-03-19"
---

# Linux CI in `homebrew/core`

We currently use Ubuntu 24.04 for bottling in `homebrew/core`.

We aim to use the oldest supported Ubuntu LTS version for our CI that provides the GCC version we need.

## Ubuntu vs. other Linux distributions

As of 2022, around 77% of our users are using Ubuntu. This is the reason why we have chosen this distribution for our base CI image.
We have successfully used Ubuntu for CI since version 14.04.
The Ubuntu LTS versions are supported for 5 years. A new LTS version is released every 2 years.

Our bottles are compatible with other distributions like Debian/CentOS, even when compiled on Ubuntu.

## Past and next versions

| Distribution | Glibc | GCC | libstdc++ | LTS standard security maintenance |
|---|---|---|---|---|
| Ubuntu 22.04 | 2.35 | 11 | 6.0.30 (gcc-12) | From 2022 to 2027 |
| Ubuntu 24.04 | 2.39 | 13 | 6.0.33 (gcc-14) | From 2024 to 2029 |
| Ubuntu 26.04 | 2.43 | 15 | 6.0.35 (gcc-16) | From 2026 to 2031 |
| Ubuntu 28.04 | ? | ? | ? | ? |

Here, the `libstdc++` column records the shared library SONAME version (for example, `libstdc++.so.6.0.30`). The GCC version in parentheses is the version of the Ubuntu GCC/libstdc++ runtime package that provides that SONAME; it may differ from the `GCC` column, which lists the default system compiler used in CI.

## Why upgrade to a newer version?

Homebrew is a rolling-release package manager. We try to ship the newest things as quickly as possible, on macOS and Linux.

When a formula needs a newer GCC because our host GCC in CI is too old, we needed to make that formula depend on a newer Homebrew GCC. All C++ dependents of that formula immediately acquire a dependency on Homebrew GCC as well. While we have taken the steps to make sure this no longer holds up GCC updates, it still creates a maintenance burden. This problem is more likely for formula which are very actively maintained and try to use newer features of C++. We decided that we shouldn't have a maintenance burden for formulae which are doing the right thing by staying up to date. It makes a lot of sense for Homebrew maintainers to submit upstream fixes when formulae are not working with newer compilers. It makes a lot less sense for Homebrew maintainers to submit fixes because our host compiler is too old.

Note that `glibc` will need to be installed for more users as their `glibc` version will often be too old. This is not as smooth as using a newer GCC as we don't test this configuration in CI. This is why we want to balance the newest GCC with a more conservative `glibc`.
