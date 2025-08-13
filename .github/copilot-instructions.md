# Copilot Instructions for Homebrew/brew

This is a Ruby based repository with Bash scripts for faster execution.
It is primarily responsible for providing the `brew` command for the Homebrew package manager.
Please follow these guidelines when contributing:

## Code Standards

### Required Before Each Commit

- Run `brew typecheck` to verify types are declared correctly using Sorbet.
- Run `brew style --fix` to lint code formatting using RuboCop.
  Individual files can be checked/fixed by passing them as arguments.
- Run `brew tests --online` to ensure that RSpec unit tests are passing (although some online tests may be flaky so can be ignored if they pass on a rerun).
  Individual test files can be passed with `--only` e.g. to test `Library/Homebrew/cmd/reinstall.rb` with `Library/Homebrew/test/cmd/reinstall_spec.rb` run `brew tests --only=cmd/reinstall`.

### Development Flow

- Write new code (using Sorbet `sig` type signatures and `typed: strict` files whenever possible, but not for test files)
- Write new tests (avoid more than one `:integration_test` per file for speed)

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

1. Follow Ruby best practices and idiomatic patterns
2. Maintain existing code structure and organisation
3. Write unit tests for new functionality. Use one assertion per test where possible.
4. Document public APIs and complex logic. Suggest changes to the `docs/` folder when appropriate
