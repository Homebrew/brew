# Agent Instructions for Homebrew/brew

Most importantly, run `./bin/brew lgtm` to verify any file edits before prompting for input to run all style checks and tests.

This is a Ruby based repository with Bash scripts for faster execution.
It is primarily responsible for providing the `brew` command for the Homebrew package manager.
Please follow these guidelines when contributing:

When running commands in this repository, use `./bin/brew` (not a system `brew` on `PATH`).

## Code Standards

### Required Before Each Commit

- Run `./bin/brew typecheck` to verify types are declared correctly using Sorbet.
  Individual files/directories cannot be checked.
  `./bin/brew typecheck` is fast enough to just be run globally every time.
- Run `./bin/brew style --fix --changed` to lint code formatting using RuboCop.
  Individual files can be checked/fixed by passing them as arguments e.g. `./bin/brew style --fix Library/Homebrew/cmd/reinstall.rb`
- Run `./bin/brew tests --online  --changed` to ensure that RSpec unit tests are passing (although some online tests may be flaky so can be ignored if they pass on a rerun).
  Individual test files can be passed with `--only` e.g. to test `Library/Homebrew/cmd/reinstall.rb` with `Library/Homebrew/test/cmd/reinstall_spec.rb` run `./bin/brew tests --only=cmd/reinstall`.
- Shortcut: `./bin/brew lgtm --online` runs all of the required checks above in one command.
- All of the above can be run via the Homebrew MCP Server (launch with `./bin/brew mcp-server`).

### Sandbox Setup

- When working in a sandboxed environment e.g. OpenAI Codex, copy the contents of `$(./bin/brew --cache)/api/` to a writable location inside the repository (for example, `tmp/cache/api/`) and `export HOMEBREW_CACHE` to that writable directory before running `./bin/brew tests`. This avoids permission errors when the suite tries to write API cache or runtime logs.

### Development Flow

- Write new code (using Sorbet `sig` type signatures and `typed: strict` for new files, but never for RSpec/test/`*_spec.rb` files)
- Write new tests (avoid more than one `:integration_test` per file for speed).
  Write fast tests by preferring a single `expect` per unit test and combine expectations in a single test when it is an integration test or has non-trivial `before` for test setup.
- When adding or tightening tests, verify them with a red/green cycle using the exact `--only=file:line` target for the example you changed.
- Formula classes created in specs may be frozen; avoid stubbing class methods on them with RSpec mocks and prefer instance-level stubs or test setup that does not require class-method stubbing.
- Keep comments minimal; prefer self-documenting code through strings, variable names, etc. over more comments.

## Repository Structure

- `bin/brew`: Homebrew's `brew` command main Bash entry point script
- `completions/`: Generated shell (`bash`/`fish`/`zsh`) completion files. Don't edit directly, regenerate with `./bin/brew generate-man-completions`
- `Library/Homebrew/`: Homebrew's core Ruby (with a little bash) logic.
- `Library/Homebrew/bundle/`: Homebrew's `brew bundle` command.
- `Library/Homebrew/cask/`: Homebrew's Cask classes and DSL.
- `Library/Homebrew/extend/os/`: Homebrew's OS-specific (i.e. macOS or Linux) class extension logic.
- `Library/Homebrew/formula.rb`: Homebrew's Formula class and DSL.
- `docs/`: Documentation for Homebrew users, contributors and maintainers. Consult these for best practices and help.
- `manpages/`: Generated `man` documentation files. Don't edit directly, regenerate with `./bin/brew generate-man-completions`
- `package/`: Files to generate the macOS `.pkg` file.

## Key Guidelines

1. Follow Ruby and Bash best practices and idiomatic patterns.
2. Maintain existing code structure and organisation.
3. Write unit tests for new functionality.
4. Document public APIs and complex logic.
5. Suggest changes to the `docs/` folder when appropriate
6. Follow software principles such as DRY and YAGNI.
7. Keep diffs as minimal as possible.
8. Prefer shelling out via `HOMEBREW_BREW_FILE` instead of requiring `cmd/` or `dev-cmd` when composing brew commands.
9. Inline new or existing methods as methods or local variables unless they are reused 2+ times or needed for unit tests.
