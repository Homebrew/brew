---
last_review_date: "1970-01-01"
---

# Installation

Instructions for a supported install of Homebrew are on the [homepage](https://brew.sh).

The script installs Homebrew to its default, supported, best prefix (`/opt/homebrew` for Apple Silicon, `/usr/local` for macOS Intel and `/home/linuxbrew/.linuxbrew` for Linux) so that [you don’t need *sudo* after Homebrew's initial installation](FAQ.md#why-does-homebrew-say-sudo-is-bad) when you `brew install`. This prefix is required for most bottles (binary packages) to be used. It is a careful script; it can be run even if you have stuff installed in the preferred prefix already. It tells you exactly what it will do before it does it too. You have to confirm everything it will do before it starts.

The macOS `.pkg` installer also installs Homebrew to its default prefix (`/opt/homebrew` for Apple Silicon and `/usr/local` for macOS Intel) for the same reasons as above. It's available on [Homebrew/brew's latest GitHub release](https://github.com/Homebrew/brew/releases/latest). To specify an alternate install user, like in situations where the package is installed at the login window before a user has logged in, write a property list file to `/var/tmp/.homebrew_pkg_user.plist` with the value `HOMEBREW_PKG_USER`. For example, `defaults write /var/tmp/.homebrew_pkg_user HOMEBREW_PKG_USER penny`. The file and user must exist prior to install.

## macOS Requirements

* An Apple Silicon CPU or 64-bit Intel CPU <sup>[1](#1)</sup>
* macOS Ventura (13) (or higher) installed on officially supported hardware<sup>[2](#2)</sup>
  * **Note:** Devices using OpenCore Legacy Patcher are not supported
* Command Line Tools (CLT) for Xcode (from `xcode-select --install` or
  [https://developer.apple.com/download/all/](https://developer.apple.com/download/all/)) or
  [Xcode](https://itunes.apple.com/us/app/xcode/id497799835) <sup>[3](#3)</sup>
* The Bourne-again shell for installation (i.e. `bash`) <sup>[4](#4)</sup>

## Advanced Configuration

The Homebrew installer offers various advanced configuration settings. **Most users can skip this section and instead follow the instructions on the [homepage](https://brew.sh)!**

### Git Remote Mirroring

If you have issues connecting to GitHub.com, you can use Git mirrors for Homebrew's installation and `brew update` by setting `HOMEBREW_BREW_GIT_REMOTE` and/or `HOMEBREW_CORE_GIT_REMOTE` in your shell environment with this script:

```bash
export HOMEBREW_BREW_GIT_REMOTE="..."  # put your Git mirror of Homebrew/brew here
export HOMEBREW_CORE_GIT_REMOTE="..."  # put your Git mirror of Homebrew/homebrew-core here
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

The default Git remote will be used if the corresponding environment variable is unset and works best for most users.

**Note:** if you set these variables you are granting these repositories the same level of trust you currently grant to Homebrew itself. You should be extremely confident that these repositories will not be compromised.

### Default Tap Cloning

You can instruct Homebrew to return to pre-4.0.0 behaviour by cloning the Homebrew/homebrew-core tap during installation by setting the `HOMEBREW_NO_INSTALL_FROM_API` environment variable with the following:

```bash
export HOMEBREW_NO_INSTALL_FROM_API=1
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

This will make Homebrew install formulae and casks from the `homebrew/core` and `homebrew/cask` taps using local checkouts of these repositories instead of Homebrew’s API. Unless you are a Homebrew maintainer or contributor, you should probably not globally enable this setting. It can easily be enabled later after installation should it be necessary.

### Unattended installation

If you want a non-interactive run of the Homebrew installer that doesn't prompt for passwords (e.g. in automation scripts), prepend [`NONINTERACTIVE=1`](https://github.com/Homebrew/install/#install-homebrew-on-macos-or-linux) to the installation command.

## Alternative Installs

### Linux or Windows 10 Subsystem for Linux

Check out [the Homebrew on Linux installation documentation](Homebrew-on-Linux.md).

### Untar anywhere (unsupported)

Technically, you can just extract (or `git clone`) Homebrew wherever you want. However, you shouldn't install outside the default, supported, best prefix. Many things will need to be built from source outside the default prefix. Building from source is slow, energy-inefficient, buggy and unsupported. The main reason Homebrew just works is **because** we use bottles (binary packages) and most of these require using the default prefix. If you decide to use another prefix: don't open any issues, even if you think they are unrelated to your prefix choice. They will be closed without response.

**TL;DR: pick another prefix at your peril!**

```sh
mkdir homebrew && curl -L https://github.com/Homebrew/brew/tarball/master | tar xz --strip-components 1 -C homebrew
```

or:

```sh
git clone https://github.com/Homebrew/brew homebrew
```

then:

```sh
eval "$(homebrew/bin/brew shellenv)"
brew update --force --quiet
chmod -R go-w "$(brew --prefix)/share/zsh"
```

Make sure you avoid installing into:

* Directories with names that contain spaces. Homebrew itself can handle spaces, but many build scripts cannot.
* `/tmp` subdirectories because Homebrew gets upset.
* `/sw` and `/opt/local` because build scripts get confused when Homebrew is there instead of Fink or MacPorts, respectively.

### Multiple installations (unsupported)

Create a Homebrew installation wherever you extract the tarball. Whichever `brew` command is called is where the packages will be installed. You can use this as you see fit, e.g. to have a system set of libs in the default prefix and tweaked formulae for development in `~/homebrew`.

## Post-installation steps

When you install Homebrew, it prints some directions for updating your shell's config.
If you don't follow those directions, Homebrew will not work.

You need to update your shell's config file (which file exactly depends on your shell, for example `~/.bashrc` or `~/.zshrc`) to include this:

```sh
eval "<Homebrew prefix path>/bin/brew shellenv)"
```

Replace `<Homebrew prefix path>` with the directory where Homebrew is installed on your system.
You can find Homebrew's default install location [in this FAQ entry](https://docs.brew.sh/FAQ#why-should-i-install-homebrew-in-the-default-location).

For more insight, re-run the installer or inspect [the installer's source](https://github.com/Homebrew/install/blob/deacfa6a6e62e5f4002baf9e1fac7a96e9aa5d41/install.sh#L1072-L1088)
to see how the installer constructs the path it recommends.

See [Tips N' Tricks > Loading Homebrew from the same dotfiles on different operating systems](Tips-N'-Tricks.md#loading-homebrew-from-the-same-dotfiles-on-different-operating-systems)
for another way to handle this across multiple operating systems.

## Uninstallation

Uninstallation is documented in the [FAQ](FAQ.md#how-do-i-uninstall-homebrew).

<a data-proofer-ignore name="1"><sup>1</sup></a> For 32-bit or PPC support see [Tigerbrew](https://github.com/mistydemeo/tigerbrew).

<a data-proofer-ignore name="2"><sup>2</sup></a> macOS 13 (Ventura) or higher is best and supported, 10.11 (El Capitan) – 12 (Monterey) are unsupported but may work and 10.10 (Yosemite) and older will not run Homebrew at all. For 10.4 (Tiger) – 10.6 (Snow Leopard) see [Tigerbrew](https://github.com/mistydemeo/tigerbrew).

<a data-proofer-ignore name="3"><sup>3</sup></a> You may need to install Xcode, the CLT, or both depending on the formula, to install a bottle (binary package) which is the only supported configuration. Downloading Xcode may require an Apple Developer account on older versions of Mac OS X. Sign up for free at [Apple's website](https://developer.apple.com/account/).

<a data-proofer-ignore name="4"><sup>4</sup></a> The one-liner installation method found on [brew.sh](https://brew.sh) uses the Bourne-again shell at `/bin/bash`. Notably, `zsh`, `fish`, `tcsh` and `csh` will not work.
