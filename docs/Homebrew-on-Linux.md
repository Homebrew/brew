---
logo: https://brew.sh/assets/img/linuxbrew.png
image: https://brew.sh/assets/img/linuxbrew.png
redirect_from:
  - /linux
  - /Linux
  - /Linuxbrew
last_review_date: "2026-07-18"
---

# Homebrew on Linux

The Homebrew package manager may be used on Linux and [Windows Subsystem for Linux (WSL)](https://docs.microsoft.com/en-us/windows/wsl/about) 2. Homebrew was formerly referred to as Linuxbrew when running on Linux or WSL. Homebrew does not use any libraries provided by your host system, except *glibc* and *gcc* if they are new enough. Homebrew can install its own current versions of *glibc* and *gcc* for older distributions of Linux.

[Features](#features), [installation instructions](#install) and [requirements](#requirements) are described below. Terminology (e.g. the difference between the Cellar, a tap and a cask) is [explained in the documentation](Formula-Cookbook.md#homebrew-terminology).

## Features

- Install software not packaged by your host distribution
- Install up-to-date versions of software when your host distribution is old
- Use the same package manager to manage your macOS, Linux and Windows systems

## Install

Instructions for the best, supported install of Homebrew on Linux are on the [homepage](https://brew.sh/).

The installation script installs Homebrew to `/home/linuxbrew/.linuxbrew`, which allows the use of most binary packages (bottles).
The managing account needs write access to the installation; see [running without sudo](Installation.md#running-without-sudo) and [using a dedicated owner](Installation.md#running-as-the-homebrew-owner).

Follow the installer's *Next steps* instructions to add Homebrew to your `PATH` and shell configuration.
For a supported installation using Bash, run:

```sh
eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
echo 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"' >> ~/.bashrc
```

Use `~/.zshrc` instead of `~/.bashrc` when zsh is your login shell.

You're done! Try installing a package:

```sh
brew install hello
```

If you're using an older distribution of Linux, installing your first package will also install a recent version of *glibc* and *gcc*. Use `brew doctor` to troubleshoot common issues.

## Requirements

See [Support Tiers](Support-Tiers.md#linux) for the full list of Linux requirements.

Homebrew expects a working system C compiler and the standard Linux development tools. Homebrew can install its own current version of *gcc* when needed, but this does not replace the system compiler required for bootstrap and post-install steps.

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

Homebrew can run on 32-bit ARM systems such as Raspberry Pi devices, but because they lack bottles they are a [Tier 3 platform](Support-Tiers.md#tier-3).

You may need to install your own Ruby using your system package manager, a PPA or `rbenv/ruby-build` because Homebrew does not distribute Portable Ruby for ARM32.

### 32-bit x86 (unsupported)

Homebrew does not run at all on 32-bit x86 platforms.

### Windows Subsystem for Linux 1 (Tier 3 Support)

Due to [known issues](https://github.com/microsoft/WSL/issues/8219) with WSL 1, you may experience issues running various executables installed by Homebrew. We recommend you switch to WSL 2 instead.

## Homebrew on Linux community

- [Homebrew/discussions (forum)](https://github.com/orgs/Homebrew/discussions/categories/linux)
