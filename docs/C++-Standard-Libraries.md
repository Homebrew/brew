---
last_review_date: "2026-07-18"
---

# C++ Standard Libraries

C++ libraries must use a compatible compiler, C++ standard library and application binary interface across their dependency graph.
Mixing incompatible C++ runtimes can cause link failures, missing symbols or crashes that are not resolved by changing header or library search paths.

## macOS

Apple Clang and Homebrew bottles on supported macOS versions use `libc++`.
Formulae should use the compiler and standard library selected by Homebrew unless upstream has a documented requirement that cannot be met by the default toolchain.

GNU GCC normally uses its own `libstdc++`.
A formula built with GNU GCC must not pass C++ objects across a dependency boundary that was built with an incompatible runtime unless upstream explicitly supports that combination.

## Linux

Homebrew's Linux toolchain normally uses `libstdc++`.
The same compatibility rule applies: a formula and the C++ libraries whose interfaces it consumes must agree on their runtime and ABI.

## Resolving compatibility errors

After an operating system, compiler or C++ runtime upgrade, reinstall the affected formula and its C++ dependencies with the current Homebrew toolchain.
Do not create replacement symlinks for missing versioned C++ libraries because doing so can load an ABI-incompatible library.

Formula authors should inspect the complete compiler and linker commands before overriding Homebrew's compiler selection.
If upstream requires a specific compiler, declare it as a dependency and test the complete dependency graph on every supported platform.

See the [Formula Cookbook](Formula-Cookbook.md) for build and dependency guidance.
