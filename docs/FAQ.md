---
last_review_date: "2026-09-13"
---

# FAQ (Frequently Asked Questions)

* Table of Contents
{:toc}

## Is there a glossary of terms around?

The Formula Cookbook has a list of [Homebrew terminology](Formula-Cookbook.md#homebrew-terminology).

## How do I update my local packages?

First update all package definitions (formulae) and Homebrew itself:

    brew update

You can now list which of your installed packages (kegs) are outdated with:

    brew outdated

Upgrade everything with:

    brew upgrade

Or upgrade a specific formula with:

    brew upgrade <formula>

## How do I stop certain formulae from being updated?

To stop something from being updated/upgraded:

    brew pin <formula_or_cask>

If you also do not want Homebrew to automatically learn about newer versions until you choose to, disable auto-updating entirely:

    export HOMEBREW_NO_AUTO_UPDATE=1

For the tradeoffs and alternatives, see [Locking installed formulae at specific versions](Versions.md#locking-installed-formulae-at-specific-versions).

To allow that package to update again:

    brew unpin <formula_or_cask>

Note that pinned, outdated formulae that another formula depends on need to be upgraded when required, as we do not allow formulae to be built against outdated versions. If this is not desired, see [Locking installed formulae at specific versions](Versions.md#locking-installed-formulae-at-specific-versions) instead.

Pinned casks are skipped by `brew upgrade`, but an app’s own updater may still update it outside Homebrew.

## How do I uninstall Homebrew?

To uninstall Homebrew, run the [uninstall script from the Homebrew/install repository](https://github.com/homebrew/install#uninstall-homebrew).

## How do I keep old versions of a formula when upgrading?

Homebrew automatically uninstalls old versions of each formula that is upgraded with `brew upgrade`, and periodically performs additional cleanup every 30 days.

To __disable__ automatic `brew cleanup`:

    export HOMEBREW_NO_INSTALL_CLEANUP=1

To disable automatic `brew cleanup` only for formulae `foo` and `bar`:

    export HOMEBREW_NO_CLEANUP_FORMULAE=foo,bar

When automatic `brew cleanup` is disabled, if you uninstall a formula, it will only remove the latest version you have installed. It will not remove all versions of the formula that you may have installed in the past. Homebrew will continue to attempt to install the newest version it knows about when you run `brew upgrade`. This can be surprising.

In this case, to remove a formula entirely, you may run `brew uninstall --force <formula>`. Be careful as this is a destructive operation.

## Why does `brew upgrade <formula>` or `brew install <formula>` also upgrade a bunch of other stuff?

Homebrew doesn't support arbitrary mixing and matching of formula versions, so everything a formula depends on, and everything that depends on it in turn, needs to be upgraded to the latest version as that's the only combination of formulae we test. As a consequence any given `upgrade` or `install` command can upgrade many other (seemingly unrelated) formulae, especially if something important like `python` or `openssl` also needed an upgrade.

## Where does stuff get downloaded?

    brew --cache

Which is usually: `~/Library/Caches/Homebrew`

## How do I authenticate private Git source downloads?

Prefer HTTPS source URLs and the `gh` credential helper for GitHub.
[GitHub recommends `gh` for HTTPS authentication](https://docs.github.com/en/get-started/git-basics/caching-your-github-credentials-in-git).
Homebrew uses your configured Git helpers and passes `HOMEBREW_GITHUB_API_TOKEN` as `GH_TOKEN` during downloads only when `gh` is on your original `PATH` and a helper is configured for the download URL:

```sh
HOMEBREW_GITHUB_API_TOKEN="$HOMEBREW_MY_TOKEN" brew fetch user/tap/formula
```

Restrict the token to the required repositories: download subprocesses receive it, but local Git inspections, builds and tests do not.
Homebrew also supports SSH through an agent. Before downloading, check that the required key is listed, or load it:

```sh
ssh-add -l
ssh-add ~/.ssh/id_ed25519 # If the required key is missing.
```

The following do not work for sandboxed Git downloads:

* Helpers that read the macOS login keychain: the sandbox blocks keychain access to protect unrelated credentials.
* Bare `GH_TOKEN` or arbitrary token variables: Homebrew filters the environment to limit credential exposure; select the token through `HOMEBREW_GITHUB_API_TOKEN` instead.
* Interactive password or key-passphrase prompts: Homebrew disables them to prevent unattended downloads from hanging.

## My macOS `.app`s don’t find Homebrew utilities

GUI apps on macOS don't have Homebrew's prefix in their `PATH` by default. You can fix this by running `sudo launchctl config user path "$(brew --prefix)/bin:${PATH}"` and then rebooting, as documented in `man launchctl`. Note that this sets the `launchctl` `PATH` for *all users*.

## Why does Homebrew update more frequently after I run a developer command?

Running a developer command (e.g. `brew edit`, `brew create`) enables Homebrew's developer mode. This means:

* Homebrew may auto-run `brew update` before some commands every hour instead of every 24 hours.
* Updates track the latest commit on `main` instead of the latest stable tag.

To switch back to the default behaviour, run `brew developer off`. If you only want to switch back to stable tags, set `HOMEBREW_UPDATE_TO_TAG=1` in your shell environment. To control auto-update frequency, use `HOMEBREW_AUTO_UPDATE_SECS`; to disable auto-updates entirely, set `HOMEBREW_NO_AUTO_UPDATE=1`.

## How do I contribute to Homebrew?

Read our [contribution guidelines](https://github.com/Homebrew/brew/blob/HEAD/CONTRIBUTING.md#contributing-to-homebrew).

## Why do you compile everything?

Homebrew provides pre-built binary packages for many formulae. These are referred to as [bottles](Bottles.md) and are available at <https://github.com/Homebrew/homebrew-core/packages>.

If available, bottled binaries will be used by default except under the following conditions:

* The `--build-from-source` option is invoked.
* No bottle is available for the machine's currently running OS version. (Bottles for macOS are generated only for supported macOS versions.)
* The bottle cannot be relocated to Homebrew's prefix or Cellar.
* Formula options were passed to the install command. For example, `brew install <formula>` will try to find a bottled binary, but `brew install --with-foo <formula>` will trigger a source build.

We aim to bottle everything.

## Why should I install Homebrew in the default location?

Homebrew's default prefix supports its pre-built binary packages (known as [bottles](Bottles.md)) and is used by the installer:

* `/opt/homebrew` for macOS on Apple Silicon,
* `/usr/local` for macOS on Intel, and
* `/home/linuxbrew/.linuxbrew` for Linux.

Compatible [custom prefixes](Support-Tiers.md#custom-prefixes) can also use bottles.

## Why is the default installation prefix `/opt/homebrew` on Apple Silicon?

The prefix `/opt/homebrew` was chosen to allow installations in `/opt/homebrew` for Apple Silicon and `/usr/local` for Rosetta 2 to coexist and use bottles.

## Why is the default installation prefix `/home/linuxbrew/.linuxbrew` on Linux?

The prefix `/home/linuxbrew/.linuxbrew` was chosen to avoid writing to system-owned directories after installation while still allowing most precompiled binaries (bottles) to be used.
Homebrew is designed for one owning account, which can be a [dedicated account](Installation.md#running-as-the-homebrew-owner).
See [Support Tiers](Support-Tiers.md#unsupported) for unsupported multi-user environments.

## Why does Homebrew say sudo is bad?

Homebrew runs formula builds and installations as the owning account because upstream build scripts should not have unrestricted system access.
Some casks and system services need elevated privileges; see [running without sudo](Installation.md#running-without-sudo).

## What are the default ownership and permissions used by Homebrew?

The macOS installer uses the selected account and the `admin` group for administrators, or the account's primary group otherwise.
Casks use the managing account's effective group when it is not an administrator or sudo is disabled.

Ownership on Linux, all subdirectories and files default to the current user and the user group that executed the installation.

Installed executable files commonly use `0755 (u=rwx,g=rx,o=rx)`, allowing other accounts to read and execute them.
The installers also make some managed directories group-writable for administrators and custom primary groups.
For non-admin macOS accounts whose primary group is `staff`, the installers remove group and other write permissions from the prefix and cache, and Homebrew restricts its umask while preserving stricter settings.
Check directory permissions, group membership and access control lists when provisioning a dedicated owner.

When a Homebrew-installed binary is executed, it runs with the privileges of the user who launched it.

Use a [single owning account](Installation.md#running-as-the-homebrew-owner) to manage the installation.

## Why isn’t a particular command documented?

If it’s not in [`man brew`](Manpage.md), it’s probably an [external command](External-Commands.md) with documentation available using `--help`.

## Why haven’t you merged my pull request?

If all maintainer feedback has been addressed and all tests are passing, bump it with a “bump” comment. Sometimes we miss requests and there are plenty of them. In the meantime, rebase your pull request so that it can be more easily merged.

## Can I edit formulae myself?

Yes! It’s easy! If `brew tap` doesn't show `homebrew/core`, set yourself up to edit a local copy:

1. Set `HOMEBREW_NO_INSTALL_FROM_API=1` in your shell environment,
2. Run `brew tap --force homebrew/core` and wait for the clone to complete, then
3. Run `brew edit <formula>` to open the formula in `EDITOR`.

You don’t have to submit modifications back to `homebrew/core`, just edit the formula to what you personally need and `brew install <formula>`. As a bonus, `brew update` will merge your changes with upstream so you can still keep the formula up-to-date __with__ your personal modifications!

Note that if you are editing a core formula or cask you must set `HOMEBREW_NO_INSTALL_FROM_API=1` before using `brew install` or `brew update` otherwise they will ignore your local changes and default to the API.

To undo all changes you have made to any of Homebrew's repositories, run `brew update-reset`. It will revert to the upstream state on all Homebrew's repositories.

## Can I make new formulae?

Yes! It’s easy! If you already have a local copy of `homebrew/core` (see above), just use the [`brew create` command](Manpage.md#create-options-url). Homebrew will then open the formula in `EDITOR` so you can edit it, but it probably already installs; try it: `brew install <formula>`. If you encounter any issues, run the command with the `--debug` switch like so: `brew install --debug <formula>`, which drops you into a debugging shell.

If you want your new formula to be part of `homebrew/core` or want to learn more about writing formulae, then please read the [Formula Cookbook](Formula-Cookbook.md).

## How do I get a formula from someone else’s pull request?

Ensure you have a [local copy of `homebrew/core`](#can-i-edit-formulae-myself), then:

```sh
brew update
brew install gh
cd "$(brew --repository homebrew/core)"
gh pr checkout pull_request_number
```

## Why was a formula deleted or disabled?

Use `brew log <formula>` to find out! Likely because it had [unresolved issues](Acceptable-Formulae.md) and/or [our analytics](https://formulae.brew.sh/analytics/) indicated it was not widely used.

For disabled and deprecated formulae, running `brew info <formula>` will also provide an explanation.

## Why was a cask disabled or removed after a macOS security check?

Official macOS casks must pass Homebrew's Gatekeeper checks without requiring users to bypass them.
A failure is not a malware verdict, but the cask may be deprecated, disabled and eventually removed until upstream provides artefacts that pass.
The [Cask security model](Homebrew-Security-and-Supply-Chain.md#casks-have-a-different-trust-model) explains why this policy differs from formulae and what signing, notarisation and Gatekeeper add.

## Homebrew is a poor name, it's too generic; why was it chosen?

Homebrew's creator @mxcl wasn't too concerned with the beer theme and didn't consider that the project may actually prove popular. By the time Max realised that it was popular, it was too late. However, today, the first Google hit for "homebrew" is not beer related 😉

## What does "keg-only" mean?

It means the formula is installed only into the Cellar and is not linked into the default prefix. This means most tools will not find it. You can see why a formula was installed as keg-only, and instructions for including it in your `PATH`, by running `brew info <formula>`.

You can [modify a tool's build configuration](How-to-Build-Software-Outside-Homebrew-with-Homebrew-keg-only-Dependencies.md) to find keg-only dependencies. Or, you can link in the formula if you need to with `brew link <formula>`, though this can cause unexpected behaviour if you are shadowing macOS software.

## How can I specify different configure arguments for a formula?

`brew edit <formula>` and edit the formula directly. Currently there is no other way to do this.

<a data-proofer-ignore name="why-arent-some-apps-included-during-brew-upgrade"></a>

## How does `brew upgrade` handle apps that update themselves?

Many apps can update themselves without Homebrew:

<img src="assets/img/docs/sparkle-test-app-software-update.png" width="600" alt="Sparkle update window">

An app’s own updater can make Homebrew’s installation record older than the app that is actually installed.
Blindly replacing the app based on that record could downgrade it.

Casks for self-updating apps declare `auto_updates true`.
For a versioned cask that installs a single readable app bundle, Homebrew compares the bundle’s version metadata with the cask's current version.
The default `brew upgrade` includes the cask when the installed app appears older and skips it when the installed app appears to be the same version or newer.

This comparison is not available for every artifact or versioning scheme.
When Homebrew cannot make a reliable comparison, it normally skips the self-updating cask instead of guessing.
To persistently opt out of automatic upgrades for all `auto_updates true` casks, add `export HOMEBREW_NO_UPGRADE_AUTO_UPDATES_CASKS=1` to your shell configuration.
This does not affect upgrades requested with `--greedy` or `--greedy-auto-updates`.

Casks that use [`version :latest`](Cask-Cookbook.md#special-value-latest) have no version number to compare and are excluded from an ordinary `brew upgrade`.
When such a cask is named explicitly or included with `--greedy-latest`, Homebrew downloads the current artifact and, when possible, compares its SHA-256 checksum with the checksum recorded during installation.
It skips reinstalling the cask when the artifact has not changed.

Naming a cask explicitly, using `--greedy-auto-updates` or using the broader `--greedy` option can include casks that the default checks skip.
Set `HOMEBREW_UPGRADE_GREEDY=1` to apply `--greedy` persistently to all cask upgrades, or list selected casks in the space-separated `HOMEBREW_UPGRADE_GREEDY_CASKS` variable.
Refer to the `upgrade` section of the [`brew` manual page](Manpage.md) for the full option details.

## Why don't you rewrite Homebrew in Rust to make it faster?

[We tried](https://github.com/Homebrew/brew-rs/blob/main/README.md).
We built `brew-rs`, a Rust frontend, and benchmarked it against Ruby with zero delegation back to Ruby and cold-cache I/O included.
Rust did win some narrow operations: it was faster at fetching batches of bottles, especially with a warm archive cache.
But fetching is not where users spend their time.

For `brew install`, the operation people actually care about, Ruby was faster on representative comparisons.
A real install does far more than fetch a file: it resolves metadata, pours bottles, links files, writes tabs, runs postinstall and preserves Homebrew's existing semantics.
The Rust frontend only looked faster when it skipped that work or delegated it back to Ruby, and delegating defeats the point.

So a rewrite would mean reimplementing the Cellar layout, tabs, links, caveats, postinstall, cask behaviour, source fallback and tap logic in another language for little or no gain on the path that matters.
The performance work that does help is happening in Ruby: starting useful network and disk I/O sooner, using API-backed bottle metadata earlier and trimming overhead in simple bottle fetch paths without duplicating install semantics in a second frontend.

## Why do my cask apps lose their Dock position / Launchpad position / permission settings when I run `brew upgrade`?

Homebrew has two possible strategies to update cask apps: uninstalling the old version and reinstalling the new one, or replacing the contents of the app with the new contents. With the uninstall/reinstall strategy, [macOS thinks the app is being deleted without any intent to reinstall it](https://github.com/Homebrew/brew/pull/15138), and so it removes some internal metadata for the old app, including where it appears in the Dock and Launchpad and which permissions it's been granted. The content replacement strategy works around this by treating the upgrade as an in-place upgrade. However, starting in macOS Ventura, these in-place upgrades are only allowed when the updater application (in this case, the terminal running Homebrew) has [certain permissions granted](https://github.com/Homebrew/brew/pull/15483). Either the "App Management" or "Full Disk Access" permission will suffice.

Homebrew defaults to in-place upgrades when it has the necessary permissions. Otherwise, it will use the uninstall/reinstall strategy.
