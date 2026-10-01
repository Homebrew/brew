---
last_review_date: "2026-07-18"
---

# Common Issues

This page covers recurring Homebrew problems with current, non-destructive diagnostic steps.
Start with the [Troubleshooting checklist](Troubleshooting.md) and read the full error before changing files or permissions.

* Table of Contents
{:toc}

## Running `brew`

### Missing Command Line Tools

A supported Homebrew development environment on macOS requires the Xcode Command Line Tools to build formulae from source.
Counterintuitively, installing Xcode alone is not enough: the Command Line Tools are a separate package.
Install them with:

```sh
xcode-select --install
```

Casks and bottles can be installed without developer tools, but `brew doctor` will still report the unsupported configuration.

### `bad interpreter: /usr/bin/ruby^M`

The Homebrew checkout has Windows line endings, usually because of a Git configuration setting.
Review GitHub's guide to [configuring Git line endings](https://docs.github.com/en/get-started/getting-started-with-git/configuring-git-to-handle-line-endings), then restore the Homebrew repository with `brew update-reset` as described below.

### Local changes prevent `brew update`

First inspect the repositories reported by `brew update`:

```sh
git -C "$(brew --repository)" status --short
git -C "$(brew --repository USER/REPOSITORY)" status --short
```

Repeat the second command for each tap named in the error, replacing `USER/REPOSITORY` with its tap name.

Unless you are a Homebrew or tap maintainer, any local changes are almost certainly unintentional and resetting is the right fix.
Preserve any work you intentionally made in Homebrew or a tap before continuing.
Do not run arbitrary `git clean` or `git reset --hard` commands copied from old issue reports.

After preserving intentional changes, reset only the affected repositories:

```sh
brew update-reset "$(brew --repository)"
brew update-reset "$(brew --repository USER/REPOSITORY)"
```

Run only the commands that apply, replacing `USER/REPOSITORY` with the affected tap name.
`brew update-reset` fetches and resets each specified repository to its upstream default branch.
It destroys uncommitted and committed local changes in those repositories, so review its help and preserve your work first.
Running `brew update-reset` without a repository resets Homebrew and every tap.

## Installation and downloads

### Git checkout or network failures

Errors such as `early EOF`, `index-pack failed` or a failed connection to GitHub usually indicate a network, proxy, mirror or filtering problem.

1. Confirm that GitHub and the download host are reachable from the same shell.
2. Check proxy environment variables, VPN software, firewalls and network-monitoring tools.
3. Run `brew config` and review any configured Git or bottle mirrors.
4. Retry from a stable network before reporting the problem.

If the failure is reproducible only with Homebrew, follow the [Troubleshooting checklist](Troubleshooting.md) and include the exact command and error output.

### `curl` configuration

A user `curl` configuration can change proxy, certificate, protocol or output behaviour.
Inspect `~/.curlrc` and any `CURL_*` environment variables instead of deleting the configuration blindly.
Temporarily test without custom settings, then correct the specific setting responsible for the failure.

The [curl exit-code reference](https://everything.curl.dev/cmdline/exitcode.html) and [libcurl error reference](https://curl.se/libcurl/c/libcurl-errors.html) explain common transport errors.

## After a macOS upgrade

A macOS upgrade may replace or invalidate the Command Line Tools and libraries used by installed formulae.

1. Install all available macOS updates.
2. Reinstall or update the Xcode Command Line Tools when `brew doctor` reports a problem.
3. Run `brew update`.
4. Run `brew upgrade` to rebuild or reinstall outdated formulae.

After a major macOS upgrade, Homebrew may rebuild some packages (like `pkgconf`) from source to update its system library search paths.
The rebuilt installation records the current macOS version, so subsequent `brew upgrade` runs should not repeat that rebuild for the same version mismatch.

Do not create symlinks for missing versioned libraries.
Those links can hide an incomplete upgrade and cause incompatible software to load the wrong library.

## Multiple Homebrew installations

Migration Assistant or an x86_64 terminal on Apple Silicon can leave both `/usr/local` and `/opt/homebrew` installations active.
Check the current process architecture and executable path:

```sh
arch
command -v brew
brew --prefix
```

An Apple Silicon shell should normally report `arm64` and use `/opt/homebrew`.
Before removing an old Intel installation, run its own executable to record its packages:

```sh
arch -x86_64 /usr/local/bin/brew bundle dump --file=~/intel-Brewfile
```

Review the resulting `~/intel-Brewfile` and reproduce the installation under the correct prefix.
Follow the [official uninstallation instructions](FAQ.md#how-do-i-uninstall-homebrew) only after confirming the replacement works.

## Casks

### A cask download fails

Open the cask's homepage with `brew home <cask>` and test the vendor's download link.

* If the vendor's download also fails, report the failure to the vendor or investigate the network connection.
* If the vendor has published a different version or URL, [submit a cask update](https://github.com/Homebrew/homebrew-cask/blob/HEAD/CONTRIBUTING.md#updating-a-cask).

### A cask checksum does not match

Read the error to find the downloaded file, remove only that cached file and retry once.
If the checksum still differs, compare `brew info <cask>` with the vendor's current release.

A persistent mismatch usually means the cask is outdated or the vendor replaced an existing download.
Do not bypass the checksum.
Submit an update with evidence of the vendor's current version and download.

### Permission denied while installing a cask

Confirm that your user can write to the selected application directory and that `brew doctor` does not report ownership problems.
Use `--appdir` when you intentionally install applications somewhere other than `/Applications`.

Do not recursively change ownership or permissions for the entire Caskroom or Homebrew prefix without first identifying the incorrect path and its expected owner.
Include `ls -ld` output for the failing path when requesting help.

### The declared application or artifact is missing

The vendor may have renamed or moved files inside its archive.
Fetch the cask, inspect the archive and compare its layout with `brew cat <cask>`:

```sh
brew fetch CASK
brew cat CASK
```

Update the relevant artifact stanza to use the current path.
See the [Cask Cookbook artifact reference](Cask-Cookbook.md#at-least-one-artifact-stanza-is-also-required) and [submit a cask update](https://github.com/Homebrew/homebrew-cask/blob/HEAD/CONTRIBUTING.md#updating-a-cask).

## Restoring an installation

If `brew doctor` and the preceding checks do not identify the problem, create and review a package record before reinstalling:

```sh
brew bundle dump
```

Keep the generated `Brewfile` somewhere outside the Homebrew prefix.
Follow the [uninstallation](FAQ.md#how-do-i-uninstall-homebrew) and [installation](Installation.md) documentation, then restore selected packages with `brew bundle install`.
