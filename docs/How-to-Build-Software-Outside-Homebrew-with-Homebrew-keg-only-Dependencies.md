---
last_review_date: "2026-07-18"
---

# Building Software with Homebrew Keg-Only Dependencies

A keg-only formula is installed in its own prefix but is not linked into Homebrew's common `bin`, `lib` and `include` directories.
This prevents a Homebrew package from shadowing software provided by macOS or conflicting with another formula.
See the [FAQ explanation of keg-only formulae](FAQ.md#what-does-keg-only-mean).

- Do not replace macOS tools or libraries with manual symlinks.
- Avoid `brew link --force` because it makes unrelated builds and system commands resolve a different dependency globally.
- Pass the required location only to the build that needs it.

## Discover the prefix

Use `brew --prefix <formula>` rather than embedding `/opt/homebrew`, `/usr/local` or a Cellar version:

```sh
brew --prefix openssl@3
```

The returned `opt` path remains stable when the formula is upgraded.

## Compiler and linker flags

For a build system that accepts compiler and linker flags:

```sh
CPPFLAGS="-I$(brew --prefix openssl@3)/include" \
  LDFLAGS="-L$(brew --prefix openssl@3)/lib" \
  ./configure
```

Use `CPPFLAGS` for C or C++ preprocessor include paths unless upstream explicitly documents `CFLAGS` or `CXXFLAGS`.
These flags affect only that command.

## Executable lookup

Temporarily prepend a keg-only formula's executable directory when a build requires its tools:

```sh
PATH="$(brew --prefix FORMULA)/bin:$PATH" make
```

Do not add a keg-only dependency to a global shell `PATH` unless you want it to override the platform command in every future shell.

## `pkg-config`

When the dependency installs `.pc` metadata, point `pkg-config` to it for one command:

```sh
PKG_CONFIG_PATH="$(brew --prefix openssl@3)/lib/pkgconfig" pkg-config --cflags --libs openssl
```

Some formulae use `lib/pkgconfig`, some use `share/pkgconfig` and some provide no `pkg-config` metadata.
Inspect the formula prefix rather than assuming a file exists.

## CMake

Add the formula prefix to `CMAKE_PREFIX_PATH` when a CMake project uses package configuration or Common Package Specification files:

```sh
CMAKE_PREFIX_PATH="$(brew --prefix openssl@3)" cmake -S . -B build
```

If more than one prefix is required, separate them with the platform's normal path separator and preserve any intentional existing value.

## Language packages

Build Python and other language extensions inside an isolated project environment.
Pass the same include, library or package-discovery settings to that environment's build command.
Do not change ownership of Homebrew or macOS directories to make a language package install succeed.
