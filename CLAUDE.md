# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

@AGENTS.md

## Architecture Overview

### Command Dispatch

`bin/brew` (Bash) sets up the environment and execs `Library/Homebrew/brew.rb`, which parses the command name and delegates to a class in `cmd/` (user-facing commands) or `dev-cmd/` (developer commands). All commands subclass `AbstractCommand` (`abstract_command.rb`) and implement a `run` method. The `cmd_args` block declares the command's CLI options, which `CLI::Parser` (`cli/parser.rb`) turns into typed accessor methods on the args object.

### Core Classes

- **`Formula`** (`formula.rb`) — base class for all formulae; defines the DSL (`url`, `sha256`, `bottle`, `depends_on`, etc.) and holds install/test/audit logic.
- **`Formulary`** (`formulary.rb`) — factory that loads and caches `Formula` subclasses from Ruby files in taps.
- **`FormulaInstaller`** (`formula_installer.rb`) — orchestrates downloading, building, bottling, and linking a formula.
- **`Keg`** (`keg.rb`) — represents a specific installed version of a formula under `HOMEBREW_CELLAR/<name>/<version>/`; handles linking, relocation, and cleanup.
- **`Tap`** (`tap.rb`) — a Git repository of formulae/casks (`user/homebrew-repo`); manages the on-disk layout and JSON metadata files (`formula_renames.json`, `tap_migrations.json`, etc.).
- **`Cask::Cask`** (`cask/cask.rb`) / **`Cask::DSL`** (`cask/dsl.rb`) — parallels Formula for GUI apps; `Cask::Installer` handles download, artifact installation, and quarantine.

### OS-Specific Extensions

`extend/os/` holds `prepend` modules that override behaviour per platform. The entry point for each class is a loader file (e.g., `extend/os/formula.rb`) that `prepend`s either the `mac/` or `linux/` variant at runtime. Keep these prepends thin; put shared logic in the base class so it is testable on both platforms without `:needs_linux`/`:needs_macos` tags.

### Key Patterns

- **Output helpers**: use `ohai` (info), `opoo` (warning), `odie` (fatal error + exit), `odebug`, and `oh1` from `Utils::Output::Mixin`. Include the mixin with `include Utils::Output::Mixin`.
- **OS-conditional formula code**: use `on_macos`, `on_linux`, `on_arm`, `on_intel` blocks (from `on_system.rb`) inside formulae rather than inline `OS.mac?` checks; these blocks are evaluated at install time and are understood by the bottle system.
- **Sorbet types**: every non-test file must have `# typed: strict` (or stronger) at the top. Use `sig { ... }` for all public and most private methods. Run `./bin/brew typecheck --update` to regenerate `.rbi` shims after adding new command args.
- **`Cachable`** mixin (`cachable.rb`): gives a class a `Cache` type-template and `cache`/`clear_cache` methods; used by `Formula`, `Keg`, `Tap`, and `Formulary` to avoid redundant disk reads.
- **`system_command` / `safe_system`**: prefer `system_command` (from `shell_command.rb`) for controlled subprocess execution with captured output; use `safe_system` for fire-and-forget calls that should raise on failure.
