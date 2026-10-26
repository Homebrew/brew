# RFC: an experimental Python reimplementation of Homebrew core

**Status:** draft / request for comments · **Not proposed for merge as-is**

Repository: <https://github.com/tzhazuma/homebrew-py>

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
- a deliberately small staged-source installer (`bin.install`, `prefix.install`,
  ...); build systems are explicitly unsupported for now;
- `info`, `search`, `list`, `deps`, `install`, `uninstall`, `link`, `unlink`,
  `doctor`, `config` commands and a brew-v2-compatible JSON subset.

## Validation

- 45 tests pass (`pytest -q`).
- 15 real homebrew-core formulae (bash, git, curl, openssl@3, python@3.12, ...)
  parse to exactly the desc/homepage/license/version/dependency values returned
  by `brew info --json=v2` (Homebrew 7.0.9).
- A real cached Homebrew `libslirp 4.9.6` bottle installs offline into a temporary
  prefix; the resulting keg contains the real dylib, headers, pkg-config file and
  receipt.
- Synthetic tests cover checksum failure, malicious tar paths, link conflicts,
  keg-only formulae, dependency ordering and uninstall.

## Non-goals

- A drop-in replacement for `brew` or for Homebrew's Ruby extension points.
- Cask support, services, analytics, tap management (roadmap only).
- Running arbitrary Ruby from formulae or arbitrary build systems.

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
