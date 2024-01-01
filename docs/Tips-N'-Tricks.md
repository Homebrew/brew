# Tips and Tricks

## Install previous versions of formulae

Some formulae in `homebrew/core` are made available as [versioned formulae](Versions.md) using a special naming format, e.g. `gcc@7`. If the version you're looking for isn't available, consider using `brew extract`.

## Quickly remove something from Homebrew's prefix

```sh
brew unlink <formula>
```

This can be useful if a package can't build against the version of something you have linked into Homebrew's prefix.

And of course, you can simply `brew link <formula>` again afterwards!

## Pre-download a file for a formula

Sometimes it's faster to download a file via means other than the strategies that are available as part of Homebrew. For example, Erlang provides a torrent that'll let you download at 4–5× compared to the normal HTTP method.

Downloads are saved in the `downloads` subdirectory of Homebrew's cache directory (as specified by `brew --cache`, e.g. `~/Library/Caches/Homebrew`) and renamed as `<url-hash>--<formula>-<version>`. The command `brew --cache --build-from-source <formula>` will print the expected path of the cached download, so after downloading the file, you can run `mv the_tarball "$(brew --cache --build-from-source <formula>)"` to relocate it to the cache.

You can also pre-cache the download by using the command `brew fetch <formula>` which also displays the SHA-256 hash. This can be useful for updating formulae to new versions.

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
irb(main):001:0> Formulary.factory("ace").methods - Object.methods
=> [:install, :test, :test_defined?, :sbin, :pkgshare, :elisp,
:frameworks, :kext_prefix, :any_version_installed?, :etc, :pkgetc,
...
:on_macos, :on_linux, :debug?, :quiet?, :verbose?, :with_context]
irb(main):002:0>
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

## Editor plugins

### Visual Studio Code

- [Brewfile](https://marketplace.visualstudio.com/items?itemName=sharat.vscode-brewfile) adds Ruby syntax highlighting for [Homebrew Bundle](https://github.com/Homebrew/homebrew-bundle) `Brewfile`s.

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
echo "MANPATH /opt/homebrew/share/man" | sudo tee -a /usr/local/etc/man.d/homebrew.man.conf
```

If you're using Homebrew on macOS Intel, you should also fix permissions afterwards with:

```sh
sudo chown -R "${USER}" /usr/local/etc
```
