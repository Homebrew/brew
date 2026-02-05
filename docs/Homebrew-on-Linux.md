---
logo: /assets/img/linuxbrew.png
image: /assets/img/linuxbrew.png
redirect_from:
  - /linux
  - /Linux
  - /Linuxbrew
last_review_date: "2025-04-02"
---

# Homebrew on Linux

The Homebrew package manager may be used on Linux and [Windows Subsystem for Linux (WSL)](https://docs.microsoft.com/en-us/windows/wsl/about) 2. Homebrew was formerly referred to as Linuxbrew when running on Linux or WSL. Homebrew does not use any libraries provided by your host system, except *glibc* and *gcc* if they are new enough. Homebrew can install its own current versions of *glibc* and *gcc* for older distributions of Linux.

[Features](#features), [installation instructions](#install) and [requirements](#requirements) are described below. Terminology (e.g. the difference between a Cellar, Tap, Cask and so forth) is [explained in the documentation](Formula-Cookbook.md#homebrew-terminology).

## Features

- Install software not packaged by your host distribution
- Install up-to-date versions of software when your host distribution is old
- Use the same package manager to manage your macOS, Linux, and Windows systems

## Install

Instructions for the best, supported install of Homebrew on Linux are on the [homepage](https://brew.sh/).

The installation script installs Homebrew to `/home/linuxbrew/.linuxbrew` using *sudo*. Homebrew does not use *sudo* after installation. Using `/home/linuxbrew/.linuxbrew` allows the use of most binary packages (bottles) which will not work when installing in e.g. your personal home directory.

Technically, you can install Homebrew wherever you want. However, you shouldn't install outside the default, supported, best prefix. Many things will need to be built from source outside the default prefix. Building from source is slow, energy-inefficient, buggy and unsupported. The main reason Homebrew just works is **because** we use bottles (binary packages) and most of these require using the default prefix. If you decide to use another prefix: don't open any issues, even if you think they are unrelated to your prefix choice. They will be closed without response.

The prefix `/home/linuxbrew/.linuxbrew` was chosen so that users without admin access can ask an admin to create a `linuxbrew` role account and still benefit from precompiled binaries. If you do not have admin privileges, consider asking your admin staff to create a `linuxbrew` role account for you with home directory set to `/home/linuxbrew`.

Follow the *Next steps* instructions to add Homebrew to your `PATH` and to your bash shell rcfile, either `~/.bashrc` for `bash` or `~/.zshrc` for `zsh`.

```sh
test -d ~/.linuxbrew && eval "$(~/.linuxbrew/bin/brew shellenv)"
test -d /home/linuxbrew/.linuxbrew && eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
echo "eval \"\$($(brew --prefix)/bin/brew shellenv)\"" >> ~/.bashrc
```

You're done! Try installing a package:

```sh
brew install hello
```

If you're using an older distribution of Linux, installing your first package will also install a recent version of *glibc* and *gcc*. Use `brew doctor` to troubleshoot common issues.

> [!NOTE]
> Please note that unlike macOS, Homebrew does not use a sandbox when building on Linux, so formulae may install outside the Homebrew prefix.

## Requirements

See [Support Tiers](Support-Tiers.md#linux) for the full list of Linux requirements.

To install build tools, paste at a terminal prompt:

- **Debian or Ubuntu**

  ```sh
  sudo apt-get install build-essential procps curl file git
  ```

- **Fedora**

  ```sh
  sudo dnf group install development-tools
  sudo dnf install procps-ng curl file
  ```

- **CentOS Stream or RHEL**

  ```sh
  sudo dnf group install 'Development Tools'
  sudo dnf install procps-ng curl file
  ```

- **Arch Linux**

  ```sh
  sudo pacman -S base-devel procps-ng curl file git
  ```

### ARM32 (Tier 3 Support)

Homebrew can run on 32-bit ARM systems (e.g. Raspberry Pi and others), but as they lack bottles (binary packages) they are a [Tier 3 supported platform](Support-Tiers.md#tier-3).

You may need to install your own Ruby using your system package manager, a PPA, or `rbenv/ruby-build` as we don't distribute a Homebrew Portable Ruby for ARM32.

### 32-bit x86 (Unsupported)

Homebrew does not run at all on 32-bit x86 platforms.

### Windows Subsystem for Linux 1 (Tier 3 Support)

Due to [known issues](https://github.com/microsoft/WSL/issues/8219) with WSL 1, you may experience issues running various executables installed by Homebrew. We recommend you switch to WSL 2 instead.

## Homebrew on Linux Community

- [@HomebrewOnLinux on Twitter](https://twitter.com/HomebrewOnLinux)
- [Homebrew/discussions (forum)](https://github.com/orgs/Homebrew/discussions/categories/linux)
