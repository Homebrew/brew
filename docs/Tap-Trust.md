---
last_review_date: "2026-06-10"
---

# Tap Trust

Homebrew taps can contain formulae, casks and external commands. Loading them
can run Ruby code from the tap, so Homebrew distinguishes between official taps
and non-official taps that you have explicitly trusted.

Official Homebrew taps and Homebrew's built-in commands are always trusted.
Non-official taps are currently allowed by default, but Homebrew will require
explicit trust for them in Homebrew 6.0.0 or 5.2.0, whichever comes first.
`brew doctor` warns about non-official taps that are not trusted, and install
commands may print a warning before installing from them.

## Why tap trust exists

Formulae, casks and external commands are executable package definitions, not
plain metadata. Homebrew sometimes needs to evaluate Ruby code from a tap to
resolve dependencies, discover available packages or run commands. Trusting a
tap means you accept that code running with your user's privileges whenever
Homebrew needs to load it.

Tap trust reduces the amount of non-official code Homebrew evaluates by
default. This limits the impact of compromised tap repositories, unexpected
repository ownership changes, name collisions with packages from other taps and
commands that are loaded just because their tap is present. It also makes
automation clearer: scripts can trust exactly the tap, formula, cask or command
they intend to use instead of relying on every tapped repository being loaded.

Tap trust is one part of Homebrew's wider approach to [Software Supply Chain Security](Supply-Chain-Security.md).

Prefer trusting the specific formula, cask or command you need. Trust a whole
tap only when you are comfortable with all current and future formulae, casks
and external commands from that tap being loaded by Homebrew.

## Installing from a tap

Installing a fully-qualified formula or cask name trusts only that item:

```sh
brew install user/repo/formula
brew install --cask user/repo/cask
```

To install by short name from a tapped repository, trust the specific item
first:

```sh
brew tap user/repo
brew trust --formula user/repo/formula
brew install formula
```

Use `brew trust --cask user/repo/cask` for casks and
`brew trust --command user/repo/command` for external commands.

You can also trust the whole tap:

```sh
brew tap user/repo
brew trust user/repo
brew install formula
```

Whole-tap trust is broader. It allows Homebrew to load every current and future
formula, cask and external command from that tap. This may be appropriate for a
tap you administer or rely on heavily, but for one-off installs, automation or
software from a vendor you do not fully control, prefer trusting only the item
you need.

## Trusting in a `Brewfile`

You can declare trust in a [`Brewfile`](Brew-Bundle-and-Brewfile.md) with
`trusted: true` on `tap`, `brew` and `cask` entries:

```ruby
tap "user/repo", trusted: true
brew "user/repo/formula", trusted: true
cask "user/repo/cask", trusted: true
```

`brew bundle` trusts each entry before installing it, so non-official taps,
formulae and casks load even when tap trust is required. As on the command line,
prefer trusting the specific formula or cask you need over the whole tap.
`brew bundle dump` writes `trusted: true` for entries you have already trusted.

## Managing trust

List trusted entries:

```sh
brew trust
```

List untrusted taps, formulae, casks and commands:

```sh
brew untrust
```

Stop trusting a tap or item:

```sh
brew untrust user/repo
brew untrust --formula user/repo/formula
```

A trusted tap behaves as it did before tap trust checks were introduced. An
untrusted tap is not loaded when tap trust is required, unless you explicitly
install a fully-qualified formula or cask from that tap. If you trust only a
specific formula, cask or command, Homebrew may load that item without trusting
the rest of the tap.

## Environment variables

Set `HOMEBREW_REQUIRE_TAP_TRUST=1` to require explicit trust now.

`HOMEBREW_NO_REQUIRE_TAP_TRUST=1` keeps allowing non-official taps by default
during the transition. This is not recommended and will be removed in a later
release.
