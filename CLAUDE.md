# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Homebrew/brew is the package manager for macOS and Linux, written in Ruby with Bash scripts for performance-critical paths. The main entry point is `bin/brew` (Bash), which bootstraps environment variables and dispatches to either Bash commands directly or Ruby via `Library/Homebrew/brew.rb`.

## Essential Commands

### Pre-Commit (all required)
```bash
brew lgtm                          # Run all checks below in one command
brew typecheck                     # Sorbet type checking (always run globally, fast)
brew style --fix --changed         # RuboCop lint + autofix changed files
brew tests --online --changed      # RSpec tests for changed files
```

### Running Individual Tests
```bash
brew tests --only=cmd/reinstall    # Runs Library/Homebrew/test/cmd/reinstall_spec.rb
```

### Style-Checking a Single File
```bash
brew style --fix Library/Homebrew/cmd/reinstall.rb
```

### Regenerating Docs
```bash
brew generate-man-completions      # Regenerates manpages/ and completions/ (don't edit those directly)
```

## Architecture

### Boot Sequence
`bin/brew` (Bash) → sets `HOMEBREW_PREFIX`/`HOMEBREW_REPOSITORY`/`HOMEBREW_LIBRARY` → handles fast-path commands in Bash → execs Ruby with `Library/Homebrew/brew.rb` for Ruby commands.

### Command System
- **User commands**: `Library/Homebrew/cmd/*.rb` — production commands (install, list, etc.)
- **Developer commands**: `Library/Homebrew/dev-cmd/*.rb` — maintenance/dev tools (audit, bump-formula-pr, etc.)
- **External commands**: Taps provide `brew-<command>` executables in their `cmd/` directories
- Commands subclass `AbstractCommand` and define args via a `cmd_args { ... }` DSL block
- CLI parsing is in `Library/Homebrew/cli/` (built on `optparse`)
- Command discovery and routing: `Library/Homebrew/commands.rb`

### Core Object Model
- **Formula** (`Library/Homebrew/formula.rb`): Package definitions with install lifecycle. Loaded via `Formulary` factory.
- **Cask** (`Library/Homebrew/cask/cask.rb`): macOS application bundles. Loaded via `CaskLoader`.
- **Tap** (`Library/Homebrew/tap.rb`): Git-backed repositories containing formulae, casks, and commands. Core taps: `Homebrew/core` and `Homebrew/cask`.

### OS-Specific Code (`extend/os/`)
Platform differences are handled by conditional loading. Files check `OS.mac?`/`OS.linux?` and require platform-specific submodules from `extend/os/mac/` or `extend/os/linux/`.

### API System (`Library/Homebrew/api/`)
REST client for `formulae.brew.sh` that caches JSON in `HOMEBREW_CACHE/api`. Enables formula/cask lookup without cloning tap repos. Responses are JWS-signed.

### Bundle System (`Library/Homebrew/bundle/`)
Manages Brewfiles with pluggable installers for multiple package types (formulae, casks, taps, App Store apps, VS Code extensions, cargo/go packages, etc.). Each type has matching installer, dumper, and checker classes.

## Code Conventions

- **Sorbet types**: Add `sig` type signatures to new code. New files should be `typed: strict` (except `*_spec.rb` test files).
- **No nokogiri**: Use `rexml` for XML parsing (see Gemfile).
- **Composing brew commands**: Shell out via `HOMEBREW_BREW_FILE` instead of requiring files from `cmd/` or `dev-cmd/`.
- **Inline methods**: Only extract to methods or local variables if reused 2+ times or needed for testing.
- **Minimal diffs**: Keep changes focused and small.
- **Tests**: Prefer one `expect` per unit test. Limit to one `:integration_test` per file.
- **Ruby version**: ~> 3.4.0
- **Formatting**: 2-space indent, UTF-8, LF line endings, trailing newline.

## Hooks

Claude Code hooks are configured in `.claude/settings.json`:
- **After edits**: Automatically runs `brew style --changed --fix` and `brew typecheck`
- **On stop**: Runs `brew tests --changed`
