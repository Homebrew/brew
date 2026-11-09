---
description: Configure Homebrew package, tap and licence restrictions with brew.env. Build approval workflows and understand endpoint security boundaries.
last_review_date: "2026-10-25"
---

# Homebrew Package Policies and Supply Chain Protection

Homebrew includes central configuration, package restrictions and explicit trust for third-party taps.
Use these features to make your organisation's normal Homebrew workflow follow a reviewed policy.
Your management system distributes the settings and your existing help desk or Git workflow handles approvals.
Operating-system controls remain necessary when the requirement is to prevent an untrusted user from executing software.

The configuration works on macOS and Linux; cask settings apply to casks that support the platform.
Run the Homebrew commands as the prefix owner.
For root management jobs, use the absolute `brew` path with [`as-brew-user`](Homebrew-for-Mac-Admins.md#run-management-commands-as-the-owner), for example `/opt/homebrew/bin/brew as-brew-user config` on Apple Silicon.

- Table of Contents
{:toc}

## Set central configuration with `brew.env`

Homebrew reads environment files in this order:

| Scope  | Location                                                                                   |
| ------ | ------------------------------------------------------------------------------------------ |
| System | `/etc/homebrew/brew.env`                                                                   |
| Prefix | `$HOMEBREW_PREFIX/etc/homebrew/brew.env`                                                   |
| User   | `~/.homebrew/brew.env`, or the `homebrew/brew.env` file under the configured XDG directory |

Later files override earlier files.
Set `HOMEBREW_SYSTEM_ENV_TAKES_PRIORITY=1` in `/etc/homebrew/brew.env` to load that file again last, overriding conflicting prefix and user settings.
The user file is resolved using the selected account's home and configuration directory.
See the [environment reference](Manpage.md#environment) for XDG configuration and all available variables.

1. Create a reviewed `brew.env` in your configuration repository, substituting your help-desk details:

   ```text
   HOMEBREW_SYSTEM_ENV_TAKES_PRIORITY=1
   HOMEBREW_FORBIDDEN_OWNER=IT support
   HOMEBREW_FORBIDDEN_OWNER_CONTACT=https://support.example.com/homebrew
   ```

   Write literal `NAME=value` lines, without `export` or surrounding shell quotes.
   Values can contain spaces, but shell expansion and command substitution are not supported.
   Use `1` to enable a setting and omit unwanted settings; `0` is not a general way to disable booleans.
2. Deliver that file to `/var/tmp/homebrew-config/brew.env` with your management system's file or package delivery.
   Make this staging directory and file root-owned and writable only by administrators.
3. Install the prepared file as root, readable by the managing account:

   ```sh
   /usr/bin/install -d -o root -g "$(/usr/bin/id -gn root)" -m 0755 /etc/homebrew
   /usr/bin/install -o root -g "$(/usr/bin/id -gn root)" -m 0644 \
     /var/tmp/homebrew-config/brew.env /etc/homebrew/brew.env
   ```

4. Inspect the effective settings as the Homebrew owner:

   ```sh
   brew config
   ```

   Confirm the expected `HOMEBREW_` settings appear, then follow the [package-policy checks](#deploy-a-central-package-policy) before deploying restrictions more widely.

Prefix and user files are useful for account-specific defaults.
The prefix owner can normally modify prefix configuration, so use the system file for centrally maintained settings.
These settings control Homebrew behaviour; they do not prevent the owner from modifying Homebrew itself or executing software outside it.

## Deploy a central package policy

1. Choose restrictions from the table below and record the policy owner and exception process.
2. Prepare a reviewed `brew.env`, replacing the example packages and help-desk address with your choices:

```text
HOMEBREW_SYSTEM_ENV_TAKES_PRIORITY=1
HOMEBREW_FORBIDDEN_FORMULAE=telnet
HOMEBREW_FORBIDDEN_CASKS=transmission
HOMEBREW_FORBIDDEN_TAPS=example/unreviewed
HOMEBREW_FORBIDDEN_OWNER=IT support
HOMEBREW_FORBIDDEN_OWNER_CONTACT=https://support.example.com/homebrew
```

3. Follow the [central configuration deployment steps](#set-central-configuration-with-brewenv) to install the file on a pilot device.
4. Inspect the effective configuration and test the intended restrictions before assigning more devices.

Space-separated lists replace earlier values rather than automatically merging across device groups.

## Choose the restriction that matches the requirement

| Requirement                      | Setting or workflow                        | Scope and limitation                                                  |
| -------------------------------- | ------------------------------------------ | --------------------------------------------------------------------- |
| Block named command-line tools   | `HOMEBREW_FORBIDDEN_FORMULAE`              | Includes formula dependencies; does not remove existing installations |
| Block named applications         | `HOMEBREW_FORBIDDEN_CASKS`                 | Includes cask dependencies; does not block a direct vendor download   |
| Block a package source           | `HOMEBREW_FORBIDDEN_TAPS`                  | Use the remote URL when a tap uses a custom remote                    |
| Refuse local package definitions | Always enabled                             | Formula and cask arguments must be names, including in developer mode |
| Restrict formula licences        | `HOMEBREW_FORBIDDEN_LICENSES`              | Uses declared SPDX metadata, including formula dependencies           |
| Explain policy failures          | `HOMEBREW_FORBIDDEN_OWNER` and its contact | Directs users to the team that owns the restriction                   |
| Control third-party Ruby loading | `brew trust` and `brew untrust`            | Trust is explicit but can be changed by the managing account          |

Formula and cask file paths and URLs are not accepted as package arguments, including for developers.
Use a tap and refer to packages by name.
`HOMEBREW_FORBID_PACKAGES_FROM_PATHS` has no effect.
Explicit local bottle installation and internal loading of verified API source, installed metadata and registered tap files for auditing remain supported through explicit internal APIs.
Ordinary name lookup does not evaluate supplied Ruby content or fall back to installed Ruby files.
Commands that inspect or manage installed casks can still use their recorded metadata when the definition is no longer available.
Unsupported package references warn that a package name is required.
Old loader names emit deprecation notices.
Suppressing these notices does not re-enable implicit source loading.

Homebrew's internal callers use `Formulary.from_path`, `Formulary.from_bottle`, `Formulary.from_contents` and the corresponding `CaskLoader.from_path` and `CaskLoader.from_content` APIs.
Formulae should use `Formula[]` for name lookup; internal source-loading APIs are not supported in formula or cask definitions.
These API distinctions do not sandbox Ruby: code already executing in the Homebrew process can call Ruby's `load` and `eval`.

Inspect effective settings as the Homebrew owner:

```sh
brew config
```

Test restrictions against direct installs and dependencies, since a newly introduced dependency can also block an upgrade.
For licence policies, use SPDX identifiers such as `HOMEBREW_FORBIDDEN_LICENSES=AGPL-3.0-only`; the declared formula licence is not a complete component inventory and casks have no equivalent field.

## Separate tap trust from package approval

[Tap trust](Tap-Trust.md) protects against loading non-official package definitions without an explicit trust decision.
Trust individual formulae, casks or commands when that is sufficient; whole-tap trust covers current and future contents.
Official taps are trusted by default.

Tap trust is not an administrator-controlled allowlist of everything a developer may install.
The managing account can grant trust, including by installing a fully qualified package name.
A Brewfile is also a desired software baseline, not an allowlist: packages absent from it can still be installed.

For an approved-only catalogue, use a dedicated Homebrew owner and fixed installation actions in your management system.
Users request additions through the [self-service approval workflow](Homebrew-Fleet-Management.md#provide-self-service-software-and-approvals).
Do not grant arbitrary `brew` execution as the dedicated owner merely to implement a self-service button.
Users may still download or run software elsewhere unless separate operating-system controls prevent that.

## Resolve group policies and exceptions before deployment

Homebrew does not know MDM groups or exception records.

1. Resolve group conflicts and approved exceptions into one effective `brew.env` per device.
2. Deploy and verify it using the [central configuration steps](#set-central-configuration-with-brewenv).
3. Find existing restricted packages through [inventory](Homebrew-Inventory-and-SBOM.md); restrictions do not remove them.
4. Review their dependants before approving removals, then collect fresh inventory.

## Use mirrors without weakening verification

Homebrew supports `HOMEBREW_API_DOMAIN`, `HOMEBREW_BOTTLE_DOMAIN` and `HOMEBREW_ARTIFACT_DOMAIN` for managed download infrastructure.
Set them in central configuration according to the [environment reference](Manpage.md#environment).
API and bottle mirrors can fall back to their public sources.
`HOMEBREW_ARTIFACT_DOMAIN_NO_FALLBACK=1`, used with `HOMEBREW_ARTIFACT_DOMAIN`, stops artefact downloads when that mirror cannot supply them.

Git repositories, advisory queries and vendor installers may need separate network access.
Mirrors do not replace device-wide network controls or package verification.

For compatible casks, `HOMEBREW_CASK_OPTS=--require-sha` requires a checksum.
Use `HOMEBREW_NO_SUDO=1` when your policy forbids Homebrew from invoking privileged installers, and deliver applications that require them through the MDM instead.
Provision private-tap credentials as described in the [fleet guide](Homebrew-Fleet-Management.md#publish-internal-tools-through-private-taps); plain-text `brew.env` files are not a secret-management service.

### Configure firewall and proxy access

1. Allow the destinations required by your actual packages and configured mirrors, including HTTPS redirects:

| Operation                 | Typical destinations                                                                             |
| ------------------------- | ------------------------------------------------------------------------------------------------ |
| Package metadata          | `formulae.brew.sh` or your configured API mirror                                                 |
| Bottles and portable Ruby | `ghcr.io` and its download destinations, or your mirror                                          |
| Homebrew and tap updates  | `github.com` and your private Git hosts; SSH if you chose SSH remotes                            |
| Source and cask downloads | The upstream hosts in the selected packages' URLs and redirects                                  |
| Vulnerability matching    | `api.osv.dev`, `formulae.brew.sh`, `raw.githubusercontent.com` and, where needed, `repology.org` |

This is a starting point, not a complete static domain allowlist.

2. Test metadata, package and advisory access on a pilot device.

   ```sh
   brew update
   brew fetch git
   brew vulns --json
   ```

3. Review diagnostics and permit the necessary redirects before expanding deployment.

Retain diagnostics when a proxy or firewall denies a request; do not disable TLS or checksum verification to make downloads succeed.
Configure proxy settings for the unattended account, not just an administrator's interactive shell; see the [proxy environment variables](Manpage.md#environment).
Your MDM agent has its own network requirements and may not support the same proxy configuration as Homebrew.

## Apply operating-system execution rules

Package restrictions govern Homebrew operations; use operating-system controls when the requirement is to prevent execution of software downloaded through any route.
For Macs, follow the [binary execution rules](Homebrew-for-Mac-Admins.md#apply-operating-system-execution-rules), accounting for interpreters, package updates and signing identities.

## Apply separate controls to other package ecosystems

Installing a runtime with Homebrew does not route its later downloads through Homebrew's policies or vulnerability scanner.
For project dependencies, use controls such as [`npm audit`](https://docs.npmjs.com/cli/v11/commands/npm-audit/), [pip hash checking](https://pip.pypa.io/en/stable/topics/secure-installs/) and [OSV-Scanner](https://google.github.io/osv-scanner/).
Use your MDM to distribute the applications' own extension controls, such as [Chrome's `ExtensionSettings`](https://support.google.com/chrome/a/answer/9867568?hl=en), [Firefox's `ExtensionSettings`](https://firefox-admin-docs.mozilla.org/reference/policies/extensionsettings/) and [VS Code's allowed-extension policies](https://code.visualstudio.com/docs/enterprise/extensions).
These controls govern supported applications; they do not make Homebrew a scanner for extensions or project dependencies.
Homebrew does not provide a network inspection proxy, runtime malware detector or AI usage monitor.

## Handle release delays and urgent fixes

`HOMEBREW_AUTO_UPDATE_SECS` controls metadata refresh timing, not a minimum upstream release age.
Use [staged patch-management jobs](Homebrew-Vulnerability-Management.md) for Homebrew updates.
For language dependencies, [pnpm's minimum release age](https://pnpm.io/settings/dependency-resolution#minimumreleaseage) and [uv's release cutoff](https://docs.astral.sh/uv/reference/settings/#exclude-newer) apply to their own resolvers.

See [Homebrew Security and Supply Chain](Homebrew-Security-and-Supply-Chain.md) for Homebrew's review, build and distribution protections.
