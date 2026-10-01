---
last_review_date: "2026-09-21"
description: Deploy and manage Homebrew with MDM, non-admin accounts and central configuration.
---

# Homebrew for Mac Admins: MDM and Non-Admin Accounts

This guide covers provisioning Homebrew through MDM and running it as a standard account or a dedicated Homebrew account.
It also covers central configuration, software restrictions and unattended maintenance with tools such as Jamf and Munki.
The examples use the Apple Silicon prefix `/opt/homebrew`; see [Installation](Installation.md) for platform requirements.

## Choose the managing account

Choose one existing account to own and manage the Homebrew prefix.
It can be the Mac user's standard account or a dedicated account used by your management agent.
Give it a writable home directory for caches, logs and configuration, plus write access to Homebrew's directories.
Non-admin installations use the account's primary group, including a custom group, without requiring `admin` or `staff` membership.
When the primary group is `staff`, installation and reinstallation remove group and other write permissions from the prefix and cache.
Homebrew restricts its umask for these accounts, including subprocesses, while preserving stricter existing umasks.
Administrator accounts and custom primary groups retain their existing permissions; other group members may have write access where directories are group-writable.

Other accounts can read and execute installed software when filesystem permissions allow it.
Avoid having independent users manage the same installation concurrently.
Homebrew provides no security guarantees for installations where users with write access to the prefix are considered untrusted.

## Initial provisioning

Create the managing account and its home directory before installing Homebrew.
For MDM deployment, we recommend the [official macOS `.pkg` installer and its `HOMEBREW_PKG_USER` setting](Installation.md#installation).
The selected account must exist before installation; this also supports installation at the login window.
Use the `.pkg` installer if sudo is unavailable on the host.
On Apple Silicon, casks and bottles can be installed without developer tools; install them when you need to build formulae from source.

Alternatively, an MDM agent running as root can use the shell installer to provision Homebrew for an existing standard account.
The shell installer requires an existing usable Git; use the `.pkg` installer on hosts without one.
The prefix must be dedicated to this account; an existing installation must already be owned by and writable by it.
Save the [Homebrew installer](https://github.com/Homebrew/install/blob/HEAD/install.sh) to `/path/to/install.sh`, then run the following as root, replacing `penny` with the target account:

```bash
install_user="penny"
/usr/bin/install -d -o "${install_user}" -g "$(id -gn "${install_user}")" -m 0755 /opt/homebrew
/usr/bin/sudo -i -u "${install_user}" /usr/bin/env NONINTERACTIVE=1 \
  /bin/bash -s -- < /path/to/install.sh
```

The installer uses the target account's login environment and starts in its home directory, avoiding an inaccessible working directory inherited from the MDM agent.
Its files and cache belong to that user.
The account does not need administrator privileges, sudo access or an active login session.
Here, root invokes sudo to switch accounts; the target account does not invoke it.
`NONINTERACTIVE=1` prevents the shell installer from requesting input.

Provision only the directories needed by Homebrew.
When adopting an existing installation, review its ownership and permissions before assigning it to another account.
Use the installer's printed `brew shellenv` instructions for interactive shells and absolute command paths in MDM scripts.

## Run management commands as the owner

When your process already runs as the managing account, invoke `brew` normally.
A management agent running as root can select the prefix owner explicitly:

```sh
/opt/homebrew/bin/brew as-brew-user install --yes wget
/opt/homebrew/bin/brew as-brew-user update
```

`as-brew-user` works without an active console login and rejects a root-owned prefix.
It uses the owner's home directory and a clean environment.
When sudo is available, the command retains its usual sudo behaviour.
When sudo is disabled or unavailable, an already-root caller switches through macOS `login` instead.
The target account's primary and supplementary groups are used.

Use `as-console-user` when the active console user is the intended managing account:

```sh
/opt/homebrew/bin/brew as-console-user install --yes wget
```

It uses the same root-only fallback but fails if no supported console user is logged in.
Neither command changes directory ownership or grants a standard account permission to switch to another account.

Both commands discard inherited environment settings except `HOMEBREW_NO_SUDO` and the identity settings they initialise.
The nested `brew` command then loads its environment files for the selected account.
Use those files for persistent management settings; exporting a variable in the MDM agent's environment generally does not pass it through the switch.

## Set central configuration with `brew.env`

Homebrew reads environment files in this order:

| Scope  | Location                                                                                   |
| ------ | ------------------------------------------------------------------------------------------ |
| System | `/etc/homebrew/brew.env`                                                                   |
| Prefix | `/opt/homebrew/etc/homebrew/brew.env`                                                      |
| User   | `~/.homebrew/brew.env`, or the `homebrew/brew.env` file under the configured XDG directory |

Later files override earlier files.
Set `HOMEBREW_SYSTEM_ENV_TAKES_PRIORITY=1` in `/etc/homebrew/brew.env` to load that file again last, overriding conflicting prefix and user settings.
The user file is resolved using the selected account's home and configuration directory.
See the [environment reference](Manpage.md#environment) for XDG configuration and all available variables.

For example, deploy this file as `/etc/homebrew/brew.env`:

```text
HOMEBREW_SYSTEM_ENV_TAKES_PRIORITY=1
HOMEBREW_FORBIDDEN_OWNER=IT support
HOMEBREW_FORBIDDEN_OWNER_CONTACT=https://support.example.com/homebrew
```

Write literal `NAME=value` lines, without `export` or surrounding shell quotes.
Values can contain spaces, but shell expansion and command substitution are not supported: `$HOME` and `$(id -gn)` would remain literal text.
Use `1` to enable a setting and omit it when it is not wanted.
Some booleans test whether a value is set, so `0` is not a general way to disable them.

Manage the system file and its directory as root, readable by the managing account and writable only by administrators.
For example, deploy a prepared file with:

```sh
/usr/bin/install -d -o root -g wheel -m 0755 /etc/homebrew
/usr/bin/install -o root -g wheel -m 0644 /path/to/brew.env /etc/homebrew/brew.env
```

Prefix and user files are useful for account-specific defaults.
The prefix owner can normally modify prefix configuration, so use the system file for centrally maintained settings.
These settings control Homebrew behaviour; they do not prevent the owner from modifying Homebrew itself or executing software outside it.

## Restrict software and package sources

Choose restrictions that match your deployment rather than enabling every setting.
Lists below are space-separated values in `brew.env`.

| Variable                              | Behaviour                                                                |
| ------------------------------------- | ------------------------------------------------------------------------ |
| `HOMEBREW_FORBID_PACKAGES_FROM_PATHS` | Refuses formulae and casks supplied through file paths.                  |
| `HOMEBREW_FORBIDDEN_FORMULAE`         | Refuses listed formulae, including when required as dependencies.        |
| `HOMEBREW_FORBIDDEN_CASKS`            | Refuses listed casks, including when required as dependencies.           |
| `HOMEBREW_FORBIDDEN_TAPS`             | Refuses installation from listed taps, including dependencies.           |
| `HOMEBREW_FORBIDDEN_LICENSES`         | Refuses formulae with listed SPDX licences, including dependencies.      |
| `HOMEBREW_FORBIDDEN_OWNER`            | Names the person or team responsible for restrictions in error messages. |
| `HOMEBREW_FORBIDDEN_OWNER_CONTACT`    | Adds contact information to restriction messages.                        |

For tap restrictions, a `user/repository` entry matches its default GitHub remote; use the remote URL for a custom remote.
Restrictions do not remove software that is already installed.

Use [tap trust](Tap-Trust.md) to explicitly trust required third-party formulae, casks or commands.
Trusting an entire tap allows its current and future contents to run as the managing account.
Tap trust and the restriction variables have different purposes; neither is a substitute for operating-system application controls.

## Manage software and updates

A centrally maintained [Brewfile](Brew-Bundle-and-Brewfile.md) can describe the software to install:

```sh
/opt/homebrew/bin/brew as-brew-user bundle install --file=/Library/Management/Homebrew/Brewfile
```

Make the Brewfile readable by the managing account and writable by its maintainers.
Installing a Brewfile does not automatically remove packages omitted from it; review `brew bundle cleanup` before using its removal options.
Run management jobs serially and collect both their output and exit status.
If logging through a shell pipeline, enable `pipefail` so a successful logger does not hide a failed Homebrew command.

Homebrew's automatic updates refresh Homebrew and package metadata; `brew upgrade` upgrades installed software.
If you set `HOMEBREW_NO_AUTO_UPDATE=1`, schedule explicit `brew update` runs to keep metadata current.
`HOMEBREW_NO_INSTALL_UPGRADE=1` prevents `brew install` from upgrading an already-installed package, while `HOMEBREW_NO_INSTALL_CLEANUP=1` allows you to schedule cleanup separately.
Disabling these automatic actions creates maintenance work for your management workflow.

For a minimum-version policy on an installed package, use your approved version threshold, for example:

```sh
/opt/homebrew/bin/brew as-brew-user upgrade --yes --minimum-version=2.50.1 git
```

The threshold decides whether an upgrade is needed; it does not pin the package to that exact version.
Account for uninstalled or pinned packages in your management workflow and check the resulting installed version.
Use the [command reference](Manpage.md) to check options available in the Homebrew version deployed to your Macs.

### Vulnerability updates

Run `brew vulns` without formula names to check all installed formulae for known vulnerabilities:

```sh
/opt/homebrew/bin/brew as-brew-user update
/opt/homebrew/bin/brew as-brew-user vulns --list-skipped
```

The scan returns a non-zero status when it finds unresolved vulnerabilities or cannot reliably scan some installed formulae.
Keep its output and exit status; review skipped packages as well as findings.
Casks are not scanned.
Use `--json` for management reports, `--severity=high` to focus on high and critical findings or `--fix-available` to show findings with a released fix.

To apply available upgrades across the installation, including vulnerable formulae, then check again:

```sh
/opt/homebrew/bin/brew as-brew-user upgrade --yes
/opt/homebrew/bin/brew as-brew-user vulns --list-skipped
```

For selective remediation, pass the affected formula names from the scan to `brew upgrade --yes --formula`.
Pinned formulae and vulnerabilities without a fix in the available Homebrew version need separate review.
An upstream fix reported by `--fix-available` does not guarantee that Homebrew already provides it.

## Casks, services and shared destinations

With `HOMEBREW_NO_SUDO=1`, casks requiring privileged installers, keyboard-layout cache changes or privileged install steps fail before installation.
Set it in `brew.env` when you explicitly want to [disable Homebrew's sudo calls](Installation.md#running-without-sudo); Homebrew also detects when sudo is unavailable.
Optional filesystem operations attempt to run without sudo.
Homebrew does not extract `.pkg` payloads as a substitute for running their installers.
Deploy applications requiring privileged installation separately through your MDM.

For compatible app casks, choose a destination writable by the managing account with `--appdir` or `HOMEBREW_CASK_OPTS`.
In `brew.env`, specify the destination as an absolute path to that account's Applications directory; shell variables are not expanded.
A shared destination such as `/Applications` needs suitable permissions provisioned separately.
For casks that must supply checksums, `HOMEBREW_CASK_OPTS=--require-sha` rejects casks without them.

Caches, logs, configuration and user services belong to the managing account.
A dedicated account's user service is not another user's service; plan its login requirements and lifecycle separately from package installation.
Use the [`brew services` reference](Manpage.md#services-subcommand) when choosing user services or system services.

## Network configuration and reporting

For managed download infrastructure, see `HOMEBREW_API_DOMAIN`, `HOMEBREW_BOTTLE_DOMAIN` and `HOMEBREW_ARTIFACT_DOMAIN` in the [environment reference](Manpage.md#environment).
API and bottle mirrors can fall back to upstream sources.
`HOMEBREW_ARTIFACT_DOMAIN_NO_FALLBACK=1`, together with `HOMEBREW_ARTIFACT_DOMAIN`, makes artifact-mirror failures stop downloads instead of falling back.
Validate your mirror's coverage and keep its metadata current.
Use `HOMEBREW_NO_ANALYTICS=1` if your deployment should disable Homebrew analytics.

Collect inventory as the managing account:

```sh
/opt/homebrew/bin/brew as-brew-user info --json=v2 --installed
/opt/homebrew/bin/brew as-brew-user config
/opt/homebrew/bin/brew as-brew-user doctor
```

Use JSON output for inventory integrations and [Querying `brew`](Querying-Brew.md) for examples.
Keep failure output and consult the managing account's `~/Library/Logs/Homebrew` directory when investigating build failures.
