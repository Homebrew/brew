---
last_review_date: "2026-07-18"
---

# Acceptable Formulae

This page contains the formula-specific requirements for [`homebrew/core`](https://github.com/Homebrew/homebrew-core).
The [shared package acceptance policy](Package-Acceptance-Policy.md) also applies.

* Table of Contents
{:toc}

## Requirements for `homebrew/core`

### Supported platforms

A formula must build and pass its tests on the current `homebrew/core` continuous-integration matrix for the [supported macOS](Installation.md#macos-requirements) and [Linux](Linux-CI.md) configurations.
An explicit platform restriction may be eligible when upstream does not support a platform and the remaining support is useful and maintainable.

### Software provided by macOS

Software that duplicates a macOS-provided tool or library may be eligible when the formula uses `keg_only :provided_by_macos` and otherwise meets the acceptance criteria.

### Versioned formulae

A versioned formula is eligible when it meets the [versioned formula requirements](Versions.md).

### Forks

A fork that replaces an existing project must meet the [shared fork criteria](Package-Acceptance-Policy.md#forks-that-replace-an-existing-project).
A separately named fork may be eligible when its name clearly distinguishes it from the original project and it meets every other formula requirement.

### Self-updating software

Software that updates itself conflicts with Homebrew's version and upgrade management.
Self-update behaviour must be disabled when this can be done without a fragile or invasive patch.
Software whose supported distribution model requires self-updating may be more appropriate as a cask.

### Versioned and verifiable sources

An install step must not fetch code from a moving default branch or an unversioned, unchecksummed archive.
Sources must use an immutable release archive, tag or revision and downloaded archives must be verified with SHA-256.

Use the dependency mechanism documented for the ecosystem in [Language-Specific Formulae](Language-Specific-Formulae.md).
Some language package managers may install a versioned, locked dependency set during the build, while Python formulae declare checksummed `resource` blocks and install them with dependency resolution disabled.
An install step must not resolve a moving or otherwise unreproducible dependency set.

### Source availability and licences

* A formula in `homebrew/core` must be open source under a licence compatible with the [Debian Free Software Guidelines](https://wiki.debian.org/DFSGLicenses).
* It must either build from source or install portable, platform-independent output such as Java bytecode.
* Proprietary or platform-specific binary-only software belongs in a cask.
* A core formula must not depend on a cask, proprietary software or a runtime step that automatically installs either one.

### Stable releases

* Upstream must identify the packaged version as stable and provide an immutable tag or release.
* Release archives are preferred to Git checkouts and should include the version in the filename when upstream provides that form.
* A new formula must build without downstream-only patches on its supported platforms.

Software without a stable release is difficult to reproduce, bottle and support and is not eligible for `homebrew/core`.

### Native macOS applications

A formula whose primary output is a native macOS `.app` bundle is not eligible.
A supported application bundle published by upstream belongs in [`homebrew/cask`](https://github.com/Homebrew/homebrew-cask).

### Optional graphical interfaces

* When upstream can build both a command-line or library component and an optional graphical interface, the command-line or library component should remain the formula's primary purpose.
* A widely used native graphical interface may be included when it does not impose a disproportionate dependency cost.
* An X11 or XQuartz interface should not be enabled by default as it provides a poor macOS experience.

### Dependencies and full variants

The default formula should carry the dependencies required to build and test the software, satisfy other `homebrew/core` formulae and support functionality that users reasonably expect.
Avoid large dependency trees that only enable optional upstream features for a subset of users.

A separate `*-full` formula is a rare escape hatch for software that needs both a practical default build and a maximal build.
Other `homebrew/core` formulae must depend on the default formula rather than the `*-full` variant.
The sibling formulae should be able to coexist when practical, using `keg_only` when necessary.
Alternative dependency trade-offs that are unsuitable for `homebrew/core` belong in a third-party tap.

### Compiler support

Software must build with the current stable Apple Clang on supported macOS versions unless the formula declares and justifies another supported compiler.
Needing an obsolete compiler usually indicates that upstream has not maintained macOS support.

### Installation behaviour

A formula must automate dependency resolution and installation sufficiently to be useful as a package.
Software that requires extensive manual pre-installation or post-installation steps is not suitable for `homebrew/core` unless those steps can be made reliable and safe.

### Shared and static libraries

* Shared libraries are preferred when upstream can provide either shared or static libraries.
* A formula may install both when static libraries have a demonstrated use.
* Static-only libraries are not appropriate when other formulae depend on them because every dependent must be rebuilt after an update.

### Vendored dependencies

A separate project should not be bundled when a maintained Homebrew formula can provide the same dependency.
Unnecessary vendoring makes security updates harder and can leave multiple outdated copies installed.

Vendored dependencies may be eligible when upstream's supported build cannot use the system dependency or unbundling would make the formula unreliable.
The exception must be visible and the vendored components must be updated with each release.
