# Rust Frontend Notes

- Build and install `brew-rs` through `./bin/brew vendor-install brew-rs`.
- Keep the vendored binary at `Library/Homebrew/vendor/brew-rs/brew-rs`.
- `brew.sh` should stay a thin gate and dispatch layer.
- Prefer reusing existing Homebrew Ruby and Bash behavior for correctness in v1 instead of mirroring complex logic in Rust.
- Respect existing Homebrew cache, Cellar, Caskroom, logs, temp, and metadata paths.
- Keep Rust command entrypoints in `src/commands/` with one file per command where practical.
- Run tasks from `Library/Homebrew/rust/brew-rs` with `./rake ...`; it uses Homebrew's portable Ruby and runs `ruby -S rake`.
- Use `./rake build` to vendor the binary locally.
- Use `./rake check` for Rust formatting, lint, and Rust tests.
- Use `BREW_RS_STAGE_REPOSITORY=/path/to/Homebrew ./rake stage` to stage into another checkout.
- Use `./rake benchmark` for Ruby vs Rust benchmarks.
- Run `./bin/brew typecheck` and `./bin/brew lgtm` for repo-wide verification.
- Outside the default prefix, benchmarks should cover read commands and skip mutating commands.
