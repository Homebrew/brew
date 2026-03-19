# brew-rs

`brew-rs` is the opt-in Rust frontend for a small set of `brew` commands.

It is intentionally built through `brew vendor-install brew-rs`, which runs
standard Cargo commands under the hood instead of a bespoke build wrapper.

## Pre-step

Export both Rust frontend gate variables before building or running `brew-rs`:

```bash
export HOMEBREW_DEVELOPER=1
export HOMEBREW_RUST_FRONTEND=1
```

## Build

```bash
cd Library/Homebrew/rust/brew-rs
./rake build
```

## Enable

```bash
./bin/brew search jq
```

The first supported Rust-backed command will run `brew vendor-install brew-rs`
automatically and skip rebuilding when the vendored binary is already up-to-date.

## Rust Checks

```bash
cd Library/Homebrew/rust/brew-rs
./rake check
```

## Homebrew Checks

```bash
HOMEBREW_NO_AUTO_UPDATE=1 ./bin/brew tests --only=cmd/brew_rs --no-parallel
HOMEBREW_NO_AUTO_UPDATE=1 ./bin/brew typecheck
HOMEBREW_NO_AUTO_UPDATE=1 ./bin/brew lgtm
```

## Benchmark

The `benchmark` task compares the Ruby and Rust frontends with `hyperfine` for
every currently implemented command.

`./rake` uses Homebrew's portable Ruby and runs `ruby -S rake`, installing the
`rake` gem into portable Ruby on first use if needed. The benchmark prints the
normal `hyperfine` output along with each command's stdout/stderr. Outside the
default Homebrew prefix it benchmarks `search`, `info`, and `list`, then skips
`install`, `upgrade`, `uninstall`, and `update`. On a default-prefix Tier 1
install it runs the write benchmarks for real. Mutating commands still delegate
to the existing Homebrew frontend today, so those benchmarks currently measure
the Rust dispatch path plus the delegated Ruby/Bash work. If the vendored
binary is missing, the benchmark task builds it first with `vendor-install`.

```bash
brew install hyperfine
cd Library/Homebrew/rust/brew-rs
./rake benchmark
```

## Tier 1 Smoke Test

Run these on a default-prefix Tier 1 Homebrew install outside this repository checkout:

```bash
brew install hello
brew upgrade hello
brew uninstall hello
brew update --quiet --force
```
