---
last_review_date: "2025-03-19"
---

# Homebrew Bundle, `brew bundle` and `Brewfile`

Homebrew Bundle is run with the `brew bundle` command.

It uses `Brewfile`s to provide a declarative interface for installing/upgrading packages with Homebrew and starting services with `brew services`.

Rather than specifying the `brew` commands you wish to run, you can specify the state you wish to reach.

See also the [`brew bundle` section of `man brew`](Manpage.md#bundle-subcommand) or `brew bundle --help`.

## Basic Usage

### `brew bundle`

A simple `Brewfile` might contain a formula:

```ruby
brew "ruby"
```

When you run `brew bundle install` (or: just `brew bundle` for short), this will take instructions from the `Brewfile` to run `brew install ruby` and install Ruby if needed.

```console
$ brew bundle
Installing ruby
`brew bundle` complete! 1 Brewfile dependency now installed.
```

If it's outdated, this will run `brew upgrade ruby`.
If it's already installed, this will be a no-op.

```console
$ brew bundle install
Using ruby
`brew bundle` complete! 1 Brewfile dependency now installed.
```

### `brew bundle check`

You can check if a `brew bundle install` will do anything by running:

```console
$ brew bundle check
The Brewfile's dependencies are satisfied.
```

You can use this behaviour in scripts like so:

```bash
brew bundle check || brew bundle install
```

### Types

As well as supporting formulae (`brew "..."`), you can also use `brew bundle` with casks, taps, Mac App Store apps, VSCode extensions, Go, Cargo and Flatpak packages and to start background services with `brew services`.

```ruby
tap "apple/apple"
brew "apple/apple/game-porting-toolkit"
brew "postgresql@16", restart_service: true
cask "firefox"
mas "Refined GitHub", id: 1519867270
vscode "editorconfig.editorconfig"
go "github.com/charmbracelet/crush"
cargo "ripgrep"
flatpak "com.visualstudio.code"
flatpak "org.godotengine.Godot", remote: "flathub-beta", url: "https://dl.flathub.org/beta-repo/"
flatpak "io.github.dvlv.boxbuddyrs", remote: "flathub-beta"
```

Run `brew bundle` again and this outputs:

```console
$ brew bundle
Using apple/apple
Using apple/apple/game-porting-toolkit
Using postgresql@16
Using firefox
Using Refined GitHub
Using editorconfig.editorconfig
Using github.com/charmbracelet/crush
Using ripgrep
`brew bundle` complete! 8 Brewfile dependencies now installed.
```

### Projects

Adding a `Brewfile` to a project's repository (like you might a `package.json`, `Gemfile` or `requirements.txt`) is a nicer way of encoding project dependencies for developer environments.

It allows you to tell users to run a single command to install all dependencies for a project and start any services.

As Homebrew supports both macOS, Linux and WSL: you can have this single command setup project dependencies on three operating systems and in continuous integration services like GitHub Actions (where it's installed by default on macOS and easily on Linux with [`Homebrew/actions/setup-homebrew`](https://github.com/Homebrew/actions/tree/HEAD/setup-homebrew)).

See [GitHub's "Scripts To Rule Them All" `script/bootstrap` example](https://github.com/github/scripts-to-rule-them-all/blob/HEAD/script/bootstrap)
for how you might use a `Brewfile` and `brew bundle` to install project dependencies with Homebrew.

### `brew bundle dump`

`Brewfile`s can also be used as a way of saving all supported packages into a single file.

You can do this with `brew bundle dump --global --force` to write to e.g. `~/.Brewfile` (check `man brew` for the exact path used in your configuration):

```console
brew bundle dump --global --force
```

If you also pass `--describe`, you can also get the `Brewfile` to contain descriptions of each of the packages:

```console
brew bundle dump --global --force --describe
```

might add something like the following:

```ruby
# Powerful, clean, object-oriented scripting language
brew "ruby"
```

You can then reinstall (and, by default, upgrade) all of these with:

```console
brew bundle --global
````

## Advanced Usage

### `brew bundle cleanup`

If you've used `brew bundle dump` to store all the software you use, you can quickly cleanup anything else with:

```console
$ brew bundle cleanup --global --force
Uninstalling gcc... (1,914 files, 459.8MB)
Uninstalled 1 formula
```

### `brew bundle list`

If you want to get a list of all the formulae in your `Brewfile`, you can use:

```console
$ brew bundle list
apple/apple/game-porting-toolkit
postgresql@16
```

You can get other types with e.g.:

```console
$ brew bundle list --cask
firefox
```

### `brew bundle edit`

To open your `Brewfile` in your text editor, run:

```console
$ brew bundle edit
Editing /some/project/Brewfile
```

### `brew bundle add` and `brew bundle remove`

You can add and remove entries to your `Brewfile` by running `brew bundle add` or `brew bundle remove`:

```console
brew bundle add wget
brew bundle remove wget
```

### `brew bundle exec`

`brew bundle exec` allows you to run a command in an environment customised by your `Brewfile`.

For example, with a `Brewfile` like:

```ruby
brew "node"
```

This will ensure you are always running the correct `node`:

```console
$ brew bundle exec which node
/opt/homebrew/opt/node/bin/node
```

This can be particularly useful when building software that depends on other software in your `Brewfile`.
`brew bundle exec` will ensure that all the necessary paths are setup to find everything in your `Brewfile`, linked or unlinked, keg-only or not.
This avoids dealing with issues around individual user or machine `PATH` configuration.

If you want to avoid explicitly having to run `brew bundle check` or `brew bundle install` before `brew bundle exec`, you can use:

```console
brew bundle exec --check
brew bundle exec --install
```

If you want to start all the services in your `Brewfile` just during the execution of `brew bundle exec`, use:

```console
brew bundle exec --services
```

Note inside `brew bundle exec`, `brew bundle sh` and `brew bundle env` the environment variable `HOMEBREW_INSIDE_BUNDLE` is set to `1` for easy detection.

### `brew bundle sh`

`brew bundle sh` is like `brew bundle exec` but it runs your interactive shell of choice, like `brew sh`:

```console
$ brew bundle sh
brew bundle $ which node
/opt/homebrew/opt/node/bin/node
```

It's got the same backbone as `brew bundle exec` so the same arguments (e.g. `--check`, `--install`, `--services`) apply.

### `brew bundle env`

`brew bundle env` dumps out all the environment variables in a form suitable for adding to a shell.

```console
$ brew bundle env | grep node
export PATH="/opt/homebrew/opt/node/bin:${PATH:-}"
```

You can use this with `eval` to turn your current shell environment into a `brew bundle exec` or `brew bundle sh` one:

```console
$ eval "$(brew bundle env)"
$ echo "${PATH}" | grep node
/opt/homebrew/opt/node/bin:/opt/homebrew/bin:/usr/bin:/bin
```

It's also got the same backbone as `brew bundle exec` so the same arguments (e.g. `--check`, `--install`) apply.

### `brew bundle upgrade` and `HOMEBREW_BUNDLE_NO_UPGRADE=1`

By default, `brew bundle` will attempt to upgrade all software.
You can disable this behaviour by passing `--no-upgrade` or with `export HOMEBREW_BUNDLE_NO_UPGRADE=1` in your environment.

If you do this, you can upgrade everything with:

```console
brew bundle upgrade
```

or selective formulae with e.g.:

```console
brew bundle --upgrade-formulae ruby
```

## Advanced Brewfiles

`Brewfile`s support many other small bits of functionality.

`Brewfile`s are evaluated as Ruby so you can use Ruby logic in them.

Note that some logic may result in different output or behaviour per-machine, though.

Rather than all `Brewfile` functionality one-by-one: here's a commented example of some useful cases:

```ruby
# Run `brew tap` with a custom URL
tap "user/tap-repo", "https://user@bitbucket.org/user/homebrew-tap-repo.git"

# Set arguments passed to all `brew install --cask` commands for `cask "..."`
# In this example, pass `--appdir=~/Applications` and `--require_sha`
cask_args appdir: "~/Applications", require_sha: true

# Pass options to non-Homebrew/core formulae e.g. `brew install denji/nginx/nginx-full --with-rmtp`
# This also runs `brew link --overwrite nginx-full` and `brew services restart nginx-full` afterwards.
brew "denji/nginx/nginx-full", link: :overwrite, args: ["with-rmtp"], restart_service: :always

# Runs `brew install mysql@5.6`, `brew services restart mysql@5.6` only if it was was installed or upgraded,
# `brew link mysql@5.6` and `brew unlink mysql` (if `mysql` is installed)
brew "mysql@5.6", restart_service: :changed, link: true, conflicts_with: ["mysql"]

# Runs `brew install postgresql@16` and then runs a postinstall command if `postgresql@16` was installed or upgraded.
brew "postgresql@16",
     postinstall: "${HOMEBREW_PREFIX}/opt/postgresql@16/bin/postgres -D ${HOMEBREW_PREFIX}/var/postgresql@16"

# Runs `brew install ruby` and, afterwards, writes the installed version to the '.ruby-version` file.
brew "ruby", version_file: ".ruby-version"

# Runs `brew install gnupg` or `brew install glibc` only on the specified OS.
# Note: `brew bundle list` will not output `gnupg` on Linux or `glibc` on macOS` in this case:
# the Ruby logic means they are "hidden" on other platforms.
brew "gnupg" if OS.mac?
brew "glibc" if OS.linux?

# Runs `brew install --cask --appdir=~/my-apps/Applications`
cask "firefox", args: { appdir: "~/my-apps/Applications" }

# Runs `brew upgrade opera` to upgrade an auto-updated or unversioned Opera cask
# to the latest version even if already installed.
# This is used to force an upgrade in software that would typically update itself.
cask "opera", greedy: true

# Runs `brew install --cask java` only if '/usr/libexec/java_home --failfast` fails (i.e there is no Java)
# Note: `brew bundle list` will not output `java` if this `system` command succeeds and
# this `system` command will be run even on `brew bundle check`, not just `brew bundle install`.
cask "java" unless system "/usr/libexec/java_home", "--failfast"

# Runs `brew install --cask` and runs the command if the Google Cloud cask was installed or upgraded.
cask "google-cloud-sdk", postinstall: "${HOMEBREW_PREFIX}/bin/gcloud components update"

# Sets an environment variable to be used e.g. inside `brew bundle exec` or `system` commands in the `Brewfile`.
# Note: HOMEBREW_PREFIX/bin is _not_ in the `PATH` by default so you can set it this way.
ENV["SOME_ENV_VAR"] = "some_value"
```

## Versions

Homebrew is a [rolling release](https://en.wikipedia.org/wiki/Rolling_release) package manager so it does not support installing arbitrary older versions of software.

`brew bundle` does not have a concept of a "`Brewfile` lock file" that can be used to pin versions like e.g. `package-lock.json` or `Gemfile.lock`.

This must be done with solutions outside or built on top of `brew bundle` instead.

## Adding New Packages Support

`brew bundle` currently supports Homebrew, Homebrew Cask, Mac App Store, Visual Studio Code (and forks/variants), Go and Flatpak packages.

We are interested in contributions for other packages' installers/checkers/dumpers but they must:

- be able to install software without user interaction
- be able to check if software is installed
- be able to dump the installed software to a format that can be stored in a `Brewfile`
- not require `sudo` to install (casks are an exception here)
- be extremely widely used
