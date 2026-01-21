# Copilot Instructions for Homebrew/brew

This is a Ruby based repository with Bash scripts for faster execution.
It is primarily responsible for providing the `brew` command for the Homebrew package manager.
Please follow these guidelines when contributing:

## Code Standards

### Required Before Each Commit

- Run `brew lgtm` to run typecheck, style and tests in one go.
- Run `brew typecheck` to verify types are declared correctly using Sorbet.
  Individual files/directories cannot be checked.
  `brew typecheck` is fast enough to just be run globally every time.
- Run `brew style --fix --changed` to lint code formatting using RuboCop.
  Individual files can be checked/fixed by passing them as arguments e.g. `brew style --fix Library/Homebrew/cmd/reinstall.rb``
- Run `brew tests --online  --changed` to ensure that RSpec unit tests are passing (although some online tests may be flaky so can be ignored if they pass on a rerun).
  Individual test files can be passed with `--only` e.g. to test `Library/Homebrew/cmd/reinstall.rb` with `Library/Homebrew/test/cmd/reinstall_spec.rb` run `brew tests --only=cmd/reinstall`.
- All of the above can be run with the `brew-mcp-server`

### Sandbox Setup

- When working in a sandboxed environment e.g. OpenAI Codex, copy the contents of `$(brew --cache)/api/` to a writable location inside the repository (for example, `tmp/cache/api/`) and `export HOMEBREW_CACHE` to that writable directory before running `brew tests`. This avoids permission errors when the suite tries to write API cache or runtime logs.

### Development Flow

- Write new code (using Sorbet `sig` type signatures and `typed: strict` for new files, but never for RSpec/test/`*_spec.rb` files)
- Write new tests (avoid more than one `:integration_test` per file for speed).
  Write fast tests by preferring a single `expect` per unit test and combine expectations in a single test when it is an integration test or has non-trivial `before` for test setup.
- Keep comments minimal; prefer self-documenting code through strings, variable names, etc. over more comments.

## Repository Structure

- `bin/brew`: Homebrew's `brew` command main Bash entry point script
- `completions/`: Generated shell (`bash`/`fish`/`zsh`) completion files. Don't edit directly, regenerate with `brew generate-man-completions`
- `Library/Homebrew/`: Homebrew's core Ruby (with a little bash) logic.
- `Library/Homebrew/bundle/`: Homebrew's `brew bundle` command.
- `Library/Homebrew/cask/`: Homebrew's Cask classes and DSL.
- `Library/Homebrew/extend/os/`: Homebrew's OS-specific (i.e. macOS or Linux) class extension logic.
- `Library/Homebrew/formula.rb`: Homebrew's Formula class and DSL.
- `docs/`: Documentation for Homebrew users, contributors and maintainers. Consult these for best practices and help.
- `manpages/`: Generated `man` documentation files. Don't edit directly, regenerate with `brew generate-man-completions`
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
9. Inline one-off helpers unless they are reused or needed for tests.
