---
last_review_date: "2026-07-18"
---

# Custom GCC and Cross-Compilers

Homebrew uses the supported platform compiler by default.
Changing `PATH` so an unrelated compiler, linker or build tool shadows the platform toolchain can make builds fail in ways that are difficult to reproduce.

Homebrew provides current GNU GCC through the `gcc` formula and LLVM through the `llvm` formula.
Versioned formulae may exist for software that still requires an older compiler, but they can have narrower platform support and shorter remaining support periods.
Check `brew info <formula>` rather than relying on a compiler list in this document.

On macOS, the unversioned `cc`, `gcc` and `c++` commands are Apple Clang entry points.
Homebrew's GNU compiler executables use versioned names to avoid replacing the platform compiler.
Formulae and build scripts should identify the required compiler explicitly instead of assuming that `gcc` means GNU GCC on every platform.

Cross-compiler formulae use target-prefixed names such as `x86_64-elf-gcc` and are not intended to replace the host compiler.
Other toolchains may be available from third-party taps.
Review the tap's ownership and [trust only the required item](Tap-Trust.md#installing-from-a-tap) before installation.

Formula authors should declare compiler and toolchain dependencies in the formula, keep them isolated from the host toolchain and test generated binaries for the intended target.
Use a third-party tap for a specialised or experimental toolchain that does not meet the criteria for `homebrew/core`.
