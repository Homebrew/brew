# Agent Instructions for Homebrew/brew

Most importantly, run `./bin/brew lgtm` to verify any file edits before prompting for input to run all style checks and tests.

This is a Ruby based repository with Bash scripts for faster execution.
It is primarily responsible for providing the `brew` command for the Homebrew package manager.
Please follow these guidelines when contributing:

When running commands in this repository, use `./bin/brew` (not a system `brew` on `PATH`).

When running Ruby directly (e.g. `ruby -e ...`, `gem`, profiling tools), never use the system Ruby. Use `./bin/brew ruby -- <args>` to run Ruby scripts with Homebrew's vendored Ruby and libraries loaded. The system macOS Ruby is an incompatible older version.

Do not use conventional commit prefixes such as `feat:`, `fix:`, `chore:`, `refactor:`, `perf:` or `ci:`; the `Commit Style` GitHub Actions workflow rejects them.

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

### Development Flow

- Write new code (using Sorbet `sig` type signatures and `typed: strict` for new files).
- Write new tests (use at most one `:integration_test` per command, make it a happy-path test and keep it as fast as possible; add another only for essential core functionality in essential non-developer commands). Try `typed: true` as a baseline but revert to `typed: false` if there are not easily fixable errors.
  Write fast tests by preferring a single `expect` per unit test and combine expectations in a single test when it is an integration test or has non-trivial `before` for test setup.
- When adding or tightening tests, verify them with a red/green cycle using the exact `--only=file:line` target for the example you changed.
- Formula classes created in specs may be frozen; avoid stubbing class methods on them with RSpec mocks and prefer instance-level stubs or test setup that does not require class-method stubbing.
- Keep comments minimal; prefer self-documenting code through strings, variable names, etc. over more comments.
- Put a comment immediately above each `shellcheck disable` explaining why it is needed.
- Aim to wrap human-written user-facing terminal output at around 80 characters; this does not apply to generated output or code.

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
10. Avoid `T.must`; prefer explicit nil checks or APIs that return non-nil values.
11. Avoid `T.unsafe(self)` whenever possible; prefer `requires_ancestor` or similar typed module patterns.
12. Avoid `.send` in tests; call methods directly and make the method public or, for dynamic calls, use `.public_send`.
13. Keep `extend/os/*` prepends as thin as possible; put the `prepend` in the OS-specific `linux` or `macos` file rather than the shared `extend/os/*` loader with an inline `if`, and prefer putting substantive logic in shared code outside `extend/` when practical so it can be tested on all platforms instead of relying on `:needs_linux` or `:needs_macos` specs.
14. When Bash logic mirrors Ruby logic, keep both implementations in sync and add two-way comments naming the matching Ruby and Bash locations; keep matching helper filenames aligned where practical.
