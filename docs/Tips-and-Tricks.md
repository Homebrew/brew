---
last_review_date: 2025-07-15
redirect_from:
  - /Tips-N'-Tricks
---

# Tips and Tricks

## Install previous versions of formulae

Some formulae in `homebrew/core` are made available as [versioned formulae](Versions.md) using a special naming format, e.g. `gcc@9`. If the version you're looking for isn't available, consider using `brew version-install`.

## Quickly remove something from Homebrew's prefix

```sh
brew unlink <formula>
```

This can be useful if a package can't build against the version of something you have linked into Homebrew's prefix.

And of course, you can simply `brew link <formula>` again afterwards!

## Pre-download a file for a formula

Sometimes it's faster to download a file via means other than the strategies that are available as part of Homebrew. For example, Erlang provides a torrent that'll let you download at 4–5× compared to the normal HTTP method.

Downloads are saved in the `downloads` subdirectory of Homebrew's cache directory (as specified by `brew --cache`, e.g. `~/Library/Caches/Homebrew`) and renamed as `<url-hash>--<formula>-<version>`. The command `brew --cache --build-from-source <formula>` will print the expected path of the cached download, so after downloading the file, you can run `mv the_tarball "$(brew --cache --build-from-source <formula>)"` to relocate it to the cache.

You can also pre-cache the download by using the command `brew fetch <formula>` which also displays its SHA-256 hash. This can be useful for updating formulae to new versions.

## Install stuff without the Xcode CLT

```sh
brew sh          # or: eval "$(brew --env)"
gem install ronn # or c-programs
```

This imports the `brew` environment into your existing shell; `gem` will pick up the environment variables and be able to build. As a bonus, `brew`'s automatically determined optimization flags are set.

## Install only a formula's dependencies (not the formula)

```sh
brew install --only-dependencies <formula>
```

## Use the interactive Homebrew shell

```console
$ brew irb
==> Interactive Homebrew Shell
Example commands available with: `brew irb --examples`
brew(main):001> Formulary.factory("ace").methods - Object.methods
=>
[:test,
 :install,
 :valid_platform?,
...
 :debug?,
 :verbose?,
 :quiet?]
 [:install, :test, :test_defined?, :sbin, :pkgshare, :elisp,
brew(main):002>
```

## Hide the beer mug emoji when finishing a build

```sh
export HOMEBREW_NO_EMOJI=1
```

This sets the `HOMEBREW_NO_EMOJI` environment variable, causing Homebrew to hide all emoji.

The beer emoji can also be replaced with other character(s):

```sh
export HOMEBREW_INSTALL_BADGE="☕️ 🐸"
```

## Migrate a Homebrew installation to a new location

Running `brew bundle dump` will record an installation to a `Brewfile` and `brew bundle install` will install from a `Brewfile`. See `brew bundle --help` for more details.

## Appoint Homebrew Cask to manage a manually-installed app

Run `brew install --cask` with the `--adopt` switch:

```console
$ brew install --cask --adopt textmate
==> Downloading https://github.com/textmate/textmate/releases/download/v2.0.23/TextMate_2.0.23.tbz
...
==> Installing Cask textmate
==> Adopting existing App at '/Applications/TextMate.app'
==> Linking Binary 'mate' to '/opt/homebrew/bin/mate'
🍺  textmate was successfully installed!
```

## Define aliases for Homebrew commands

Use [`brew alias`](Manpage.md#alias---edit-aliasaliascommand) to define custom commands that run other commands in `brew` or your shell, similar to the `alias` shell builtin.

```shell
# Add aliases
$ brew alias ug='upgrade'
$ brew alias i='install'

# Print all aliases
$ brew alias

# Print one alias
$ brew alias i

# Use your aliases like any other command
$ brew i git

# Remove an alias
$ brew unalias i

# Aliases can include other aliases
$ brew alias show='info'
$ brew alias print='show'
$ brew print git # will run `brew info git`
```

Note that names of stock Homebrew commands can't be used as aliases.

All aliased commands are prefixed with `brew`, unless they start with `!` or `%`:

```shell
$ brew alias ug='upgrade'
# `brew ug` → `brew upgrade`

$ brew alias status='!git status'
# `brew status` → `git status`
```

You may need single quotes to prevent your shell from interpreting `!`, but `%` will work for both quote types.

```shell
# Use shell expansion to preserve a local variable
$ mygit=/path/to/my/git
$ brew alias git="%$mygit"
# `brew git status` → `/path/to/my/git status`
```

Aliases can be opened in `$EDITOR` with the `--edit` flag.

```shell
# Edit alias 'brew foo', creating if necessary
$ brew alias --edit foo
# Create and edit alias 'brew foo'
$ brew alias --edit foo=bar

# This works too
$ brew alias foo --edit
$ brew alias foo=bar --edit

# Open all aliases in $EDITOR
$ brew alias --edit
```

## Editor plugins

### Visual Studio Code

- [Brewfile](https://marketplace.visualstudio.com/items?itemName=sharat.vscode-brewfile) adds Ruby syntax highlighting for `brew bundle`'s `Brewfile`s.

- [Brew Services](https://marketplace.visualstudio.com/items?itemName=beauallison.brew-services) is an extension for starting and stopping Homebrew services.

### Sublime Text

- [Homebrew-formula-syntax](https://github.com/samueljohn/Homebrew-formula-syntax) can be installed with Package Control in Sublime Text 2/3, which adds highlighting for inline patches.

### Vim

- [brew.vim](https://github.com/xu-cheng/brew.vim) adds highlighting to inline patches in Vim.

### Emacs

- [homebrew-mode](https://github.com/dunn/homebrew-mode) provides syntax highlighting for inline patches as well as a number of helper functions for editing formula files.

- [pcmpl-homebrew](https://github.com/hiddenlotus/pcmpl-homebrew) provides completion for emacs shell-mode and eshell-mode.

## macOS Terminal.app: Enable the "Open man Page" contextual menu item

In the macOS Terminal, you can right-click on a command name (like `ls` or `tar`) and pop open its manpage in a new window by selecting "Open man Page".

Terminal needs an extra hint on where to find manpages installed by Homebrew because it doesn't load normal dotfiles like `~/.bash_profile` or `~/.zshrc`.

```sh
sudo mkdir -p /usr/local/etc/man.d
echo "MANPATH $(brew --prefix)/share/man" | sudo tee -a /usr/local/etc/man.d/homebrew.man.conf
```

If you're using Homebrew on macOS Intel, you should also fix permissions afterwards with:

```sh
sudo chown -R "${USER}" /usr/local/etc
```

## Use a caching proxy or mirror for Homebrew and data

You can configure Homebrew to retrieve bottles and the JSON API from a caching proxy or mirror.

For example, in JFrog's Artifactory, accessible at `https://artifacts.example.com`:

- For the bottles, configure a new "remote" repository with `homebrew` as the "repository key" and `https://ghcr.io` (GitHub Packages) as the URL.
  Set the cache expiry to a reasonable length relative to available storage capacity.
- For the JSON API, configure a new "remote" repository with `homebrew-json-api` as the "repository key" and `https://formulae.brew.sh/api` as the URL.
  Set the cache expiry to 15 minutes.

Then, set these environment variables for Homebrew to retrieve from the caching proxy.

```sh
export HOMEBREW_API_DOMAIN=https://artifacts.example.com/artifactory/homebrew-formulae-api
export HOMEBREW_ARTIFACT_DOMAIN=https://artifacts.example.com/artifactory/homebrew
export HOMEBREW_ARTIFACT_DOMAIN_NO_FALLBACK=1
export HOMEBREW_DOCKER_REGISTRY_BASIC_AUTH_TOKEN="$(printf 'anonymous:' | base64)"
```

It's also possible to use an internal mirror of `Homebrew/brew`
by setting an environment variable before running the Homebrew installer:

```sh
export HOMEBREW_BREW_GIT_REMOTE=https://git.example.com/Homebrew-mirrors/brew-mirror
```

Other artifact repositories like Sonatype Nexus Repository Manager doesn't support explicit anonymous auth and
still raise an 401 Unauthorized error, even when public read access is allowed. To mitigate this, set these environment
variables for Homebrew to omit the Authorization header when accessing the artifact repository:

```sh
export HOMEBREW_DOCKER_REGISTRY_BASIC_AUTH_TOKEN=none
```

## Load Homebrew from the same dotfiles on different operating systems

Some users may want to use the same shell initialization files on macOS and Linux.
Use this to detect the likely Homebrew installation directory and load Homebrew when it's found.
You may need to adapt this to your particular shell or other particulars of your environment.

```sh
command -v brew || export PATH="/opt/homebrew/bin:/home/linuxbrew/.linuxbrew/bin:/usr/local/bin"
command -v brew && eval "$(brew shellenv)"
```
