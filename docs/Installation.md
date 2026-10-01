---
last_review_date: "2026-09-21"
---

# Installation

Instructions for a supported install of Homebrew are on the [homepage](https://brew.sh/).

The script installs Homebrew to its default prefix (`/opt/homebrew` for Apple Silicon, `/usr/local` for macOS Intel and `/home/linuxbrew/.linuxbrew` for Linux) so that [you don’t need *sudo* after Homebrew's initial installation](FAQ.md#why-does-homebrew-say-sudo-is-bad) when you install formulae.
Some casks and system services still require elevated privileges.
Custom prefixes can also use bottles (binary packages); see their [Tier 1 requirements and stability caveat](Support-Tiers.md#custom-prefixes).
It is a careful script; it can be run even if you have stuff installed in the preferred prefix already.
It tells you exactly what it will do before it does it too.
You have to confirm everything it will do before it starts.

The macOS `.pkg` installer supports only Apple Silicon and also installs Homebrew to its default prefix (`/opt/homebrew`) for the same reasons as above.
It is available on [Homebrew/brew's latest GitHub release](https://github.com/Homebrew/brew/releases/latest).
To specify an alternate install user, such as when the package is installed at the login window before a user has logged in, create `/var/tmp/.homebrew_pkg_user.plist` with a `HOMEBREW_PKG_USER` value before installation:

```sh
sudo defaults write /var/tmp/.homebrew_pkg_user HOMEBREW_PKG_USER penny
sudo chown root:wheel /var/tmp/.homebrew_pkg_user.plist
sudo chmod 600 /var/tmp/.homebrew_pkg_user.plist
sudo chmod -N /var/tmp/.homebrew_pkg_user.plist
```

The file must be a regular non-symlink file owned by `root`, have mode `0600` and have no access control list.
The installer ignores an override that does not meet these requirements and falls back to the active console user.
The selected user must exist before installation and must not be `root`.
When developer tools provide Git, the installer runs repository maintenance as this user.
See [Homebrew for Mac Admins](Homebrew-for-Mac-Admins.md) for deployment through MDM, non-admin accounts and central configuration.

Homebrew provides no security guarantees for installations where users with write permissions to the Homebrew prefix are considered untrusted.
This also applies to installations and upgrades performed with the macOS `.pkg` installer, including through MDM.

## macOS requirements

* An Apple Silicon CPU; using a 64-bit Intel CPU is a [Tier 3](Support-Tiers.md#tier-3) configuration <sup>[1](#1)</sup>
* macOS Sequoia (15) (or higher) installed on officially supported hardware<sup>[2](#2)</sup>
* When building formulae from source, Command Line Tools (CLT) for Xcode (from `xcode-select --install` or
  [https://developer.apple.com/download/all/](https://developer.apple.com/download/all/)) or
  [Xcode](https://itunes.apple.com/us/app/xcode/id497799835) <sup>[3](#3)</sup>
* The Bourne-again shell for installation (i.e. `bash`) <sup>[4](#4)</sup>

## Advanced configuration

The Homebrew installer offers various advanced configuration settings. **Most users can skip this section and instead follow the instructions on the [homepage](https://brew.sh/)!**

### Running without sudo

Homebrew can be installed for a non-admin account.
The shell installer needs a writable prefix; arrange initial provisioning if needed, or use `--path` to select a [compatible custom prefix](Support-Tiers.md#custom-prefixes).
The macOS `.pkg` installer can provision the default prefix for the account selected by `HOMEBREW_PKG_USER` above.
After provisioning, run routine Homebrew commands as that account; formula installation and updates do not require sudo.

On macOS, if the account is not an administrator and its primary group is `staff`, installation and reinstallation remove group and other write permissions from the prefix and cache.
Homebrew also restricts its umask for this account, including subprocesses, while preserving stricter existing umasks.
Permissions for administrator accounts and accounts with custom primary groups are unchanged.

To disable Homebrew's sudo calls explicitly:

```sh
export HOMEBREW_NO_SUDO=1
```

When unset, Homebrew checks sudo access only when an operation needs it.
Homebrew disables sudo only when it is missing, reports a recognised inability to elevate privileges or a non-interactive check explicitly denies access.
Password requirements and inconclusive failures preserve normal behaviour.
Optional filesystem operations try without sudo before retrying with it.
When sudo is disabled, casks requiring it for installers, keyboard layouts or install steps are rejected before installation.
Homebrew does not substitute manual `.pkg` extraction for installation because it would skip installer scripts and package receipts.
For compatible app casks, use a writable destination such as `brew install --cask --appdir="$HOME/Applications" <cask>`.
This setting does not control commands run internally by third-party installers.

### Running as the Homebrew owner

A dedicated account can manage Homebrew while other accounts read and execute its installed software.
Give the owner a writable home directory and write access to the Homebrew directories and any shared app destination.
Non-admin installations use the account's primary group, including a custom group; membership of `admin` or `staff` is not required.
When already running as the owner, invoke `brew` normally.
To select the prefix owner from another account or a deployment process running as root on macOS or Linux, use:

```sh
brew as-brew-user install wget
```

The command uses the owner's home and a clean environment, switching accounts through sudo when necessary.
When sudo is disabled or unavailable, an already-root process switches through macOS `login` or Linux `runuser` instead.
These commands use the selected account's primary and supplementary groups.
Without permission to switch accounts, log in as the owner instead.
No console login is needed for `as-brew-user`.
A root-owned prefix is rejected; directory ownership is not changed.
User services, caches and personal configuration belong to the managing account.
Run `brew doctor` as that account and check group permissions and access control lists before sharing the installation.

### Running as the console user

On macOS, MDM, Munki and Jamf workflows can run Homebrew as the active logged-in console user:

```sh
brew as-console-user install wget
```

The command uses that user's home and a clean environment.
An already-root process can switch users even when sudo is disabled or unavailable, using the same fallback as `as-brew-user`.
Other accounts need sudo access to switch users.
It fails if no supported console user is logged in.
Use `as-brew-user` above when a dedicated account owns Homebrew.

### Git remote mirroring

If you have issues connecting to GitHub.com, you can use Git mirrors for Homebrew's installation and `brew update` by setting `HOMEBREW_BREW_GIT_REMOTE` and/or `HOMEBREW_CORE_GIT_REMOTE` in your shell environment with this script:

```bash
export HOMEBREW_BREW_GIT_REMOTE="..."  # put your Git mirror of Homebrew/brew here
export HOMEBREW_CORE_GIT_REMOTE="..."  # put your Git mirror of Homebrew/homebrew-core here
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

The default Git remote will be used if the corresponding environment variable is unset and works best for most users.

**Note:** if you set these variables you are granting these repositories the same level of trust you currently grant to Homebrew itself. You should be extremely confident that these repositories will not be compromised.

### Default tap cloning

You can instruct Homebrew to return to pre-4.0.0 behaviour by cloning the Homebrew/homebrew-core tap during installation by setting the `HOMEBREW_NO_INSTALL_FROM_API` environment variable with the following:

```bash
export HOMEBREW_NO_INSTALL_FROM_API=1
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

This will make Homebrew install formulae and casks from the `homebrew/core` and `homebrew/cask` taps using local checkouts of these repositories instead of Homebrew’s API. Unless you are a Homebrew maintainer or contributor, you should probably not globally enable this setting. It can easily be enabled later after installation should it be necessary.

### Unattended installation

If you want a non-interactive run of the Homebrew installer that doesn't prompt for passwords (e.g. in automation scripts), prepend [`NONINTERACTIVE=1`](https://github.com/Homebrew/install/#install-homebrew-on-macos-or-linux) to the installation command.

## Alternative installs

### Linux or Windows 10 Subsystem for Linux

Check out the documentation for installing [Homebrew on Linux](Homebrew-on-Linux.md).

## Post-installation steps

When you install Homebrew, it prints some directions for updating your shell's config.
If you don't follow those directions, Homebrew will not work.

You need to update your shell's config file (which file exactly depends on your shell, for example `~/.bashrc` or `~/.zshrc`) to include this:

```sh
eval "$(<Homebrew prefix path>/bin/brew shellenv)"
```

Replace `<Homebrew prefix path>` with the directory where Homebrew is installed on your system.
You can find Homebrew's default install location in [this FAQ entry](FAQ.md#why-should-i-install-homebrew-in-the-default-location).

For more insight, re-run the installer or inspect the [installer's source](https://github.com/Homebrew/install/blob/700c9a145d37a3f0f3bd3b7c208d7adab31bd278/install.sh#L1104-L1120) to see how the installer constructs the path it recommends.

See [this tip in Tips and Tricks](Tips-and-Tricks.md#load-homebrew-from-the-same-dotfiles-on-different-operating-systems) for another way to handle this across multiple operating systems.

## Uninstallation

Uninstallation is documented in the [FAQ](FAQ.md#how-do-i-uninstall-homebrew).

<a data-proofer-ignore name="1"><sup>1</sup></a> For 32-bit or PPC support see [MacPorts](https://www.macports.org) or [Tigerbrew](https://github.com/mistydemeo/tigerbrew).

<a data-proofer-ignore name="2"><sup>2</sup></a> On Apple Silicon, macOS 15 (Sequoia) through 27 (Golden Gate) is best and supported; macOS 11 (Big Sur) – 14 (Sonoma) are unsupported but may work.
All Intel Mac configurations that can run Homebrew, including those using OpenCore Legacy Patcher, are [Tier 3](Support-Tiers.md#tier-3).
macOS 10.15 (Catalina) and older will not run Homebrew at all.

<a data-proofer-ignore name="3"><sup>3</sup></a> Xcode or the CLT is required to build formulae from source. On Apple Silicon, casks and bottles can be installed without developer tools. Intel macOS also requires developer tools for bottle installation. Downloading Xcode may require an Apple Developer account on older versions of Mac OS X. Sign up for free at [Apple's website](https://developer.apple.com/account/).

<a data-proofer-ignore name="4"><sup>4</sup></a> The one-liner installation method found on [brew.sh](https://brew.sh/) uses the Bourne-again shell at `/bin/bash`. Notably, `zsh`, `fish`, `tcsh` and `csh` will not work.
