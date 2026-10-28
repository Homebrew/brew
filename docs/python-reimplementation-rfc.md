# RFC: an experimental Python reimplementation of Homebrew core

**Status:** draft / request for comments · **Not proposed for merge as-is**

Repository: <https://github.com/tzhazuma/homebrew-py>

Upstream draft PR (closed by template bot; re-submission pending maintainer/user approval): <https://github.com/Homebrew/brew/pull/24362>

## Motivation

Homebrew is one of the most widely used pieces of macOS/Linux infrastructure, and
its formula DSL is effectively a public configuration language. A Python
implementation of the core (formula parsing, dependency resolution, Cellar,
bottle handling, linking) could:

- make it easier for Python-heavy teams to embed Homebrew-compatible part of the
  workflow in their tooling;
- provide a second implementation to cross-check formula metadata and bottle
  behaviour;
- explore whether the Ruby runtime is strictly required for the bottle-only path,
  which is how the vast majority of installs are served.

This is an experiment, not a request to replace Ruby. I would like feedback on
whether this direction is useful and which parts (if any) would be worth
upstreaming, e.g. a shared machine-readable formula/bottle conformance fixture.

## What the prototype does today

A clean-room Python 3.9+ package (`pybrew`) with no runtime dependencies:

- tolerant lexer/parser for the Homebrew formula Ruby DSL (no Ruby execution;
  unknown calls preserved);
- tap discovery and formula lookup;
- recursive dependency resolution with build/test/optional/recommended tags and
  `uses_from_macos`;
- bottle install from ghcr.io OCI or a plain/root URL, with SHA-256 verification,
  safe tar extraction, `@@HOMEBREW_*@@` relocation, receipts, opt links and
  link/unlink with conflict detection;
- source builds from the common `def install` statements: `system` (including
  `*std_configure_args`, `*std_cmake_args`, `*std_meson_args`, `*std_cargo_args`),
  `inreplace`, `ENV` mutation, `bin.install`/`prefix.install` and simple
  `if OS.mac?`/`on_macos` branches; autotools, CMake and Cargo are covered by
  tests, a real meson 1.12.1 project was built manually, and unsupported
  Ruby/build steps fail explicitly instead of pretending to succeed;
- Homebrew services: parse `service do` blocks, generate launchd plists, and
  start/stop/restart/list services through an injectable `launchctl` runner;
- cask support for zip/dmg archives with `.app`, `binary` and `suite` artifacts,
  receipts, uninstall and zap; `.pkg` payloads can be expanded into an explicit
  `--pkg-root` without running package scripts; optional formulae.brew.sh cask
  API fallback so tapping homebrew-cask is not required; cask `outdated` and
  `upgrade` and `reinstall` are implemented, and uninstall runs the safe
  `quit`/`delete` actions;
- services on macOS (launchd) and Linux (systemd user units);
- tap management (`tap`/`untap`/list, local and GitHub URLs);
- `info`, `search`, `list`, `deps`, `install`, `uninstall`, `link`, `unlink`,
  `tap`, `untap`, `cask`, `services`, `doctor`, `config` commands and a
  brew-v2-compatible JSON subset.

## Validation

- 104 tests pass (`pytest -q`).
- 15 real homebrew-core formulae (bash, git, curl, openssl@3, python@3.12, ...)
  parse to exactly the desc/homepage/license/version/dependency values returned
  by `brew info --json=v2` (Homebrew 7.0.9).
- A real cached Homebrew `libslirp 4.9.6` bottle installs offline into a temporary
  prefix; the resulting keg contains the real dylib, headers, pkg-config file and
  receipt. A live ghcr.io download of the same bottle also succeeded, and
  Mach-O load commands are relocated with `install_name_tool` + ad-hoc signing.
- Synthetic tests cover checksum failure, malicious tar paths, link conflicts,
  keg-only formulae, dependency ordering and uninstall.
- Build tests compile real autotools, CMake and Cargo fixtures and verify the
  installed executables; cask tests install a zip and a real dmg and verify app,
  binary, receipt, uninstall and zap; service tests verify plist generation and
  launchctl start/stop through a fake runner; tap tests clone and update a local
  git tap.

## Non-goals

- A drop-in replacement for `brew` or for Homebrew's Ruby extension points.
- Full cask coverage: `.pkg` artifacts, `pkgutil` receipts, login items and
  system-wide installs are not implemented.
- Analytics, advanced Brewfile options, package scripts/system-wide pkg installs
  and arbitrary Ruby/build systems are not implemented yet.
- Running arbitrary Ruby from formulae.

## Questions for Homebrew maintainers

1. Is a Python implementation of the bottle-only path interesting as a
   cross-check/conformance experiment?
2. Would a shared, machine-readable formula/bottle conformance corpus be a
   useful upstream artefact (independent of implementation language)?
3. Are there compatibility guarantees (receipt format, bottle URL semantics,
   relocation rules) that should be documented for alternative implementations?

## Licensing

pybrew is BSD-2-Clause, the same license as Homebrew. It contains no Homebrew
Ruby source; the test corpus keeps unmodified formula fixtures from
homebrew-core with attribution in `NOTICE`.

This PR is intentionally a draft RFC and can be closed without further action.
