# brew(1) -- The Missing Package Manager for macOS (or Linux)

## SYNOPSIS

`brew` `--version`  
`brew` *`command`* \[`--verbose`\|`-v`\] \[*`options`*\] \[*`formula`*\] ...

## DESCRIPTION

Homebrew is the easiest and most flexible way to install the UNIX tools Apple
didn't include with macOS. It can also install software not packaged for your
Linux distribution without requiring `sudo`.

## TERMINOLOGY

**formula**

: Homebrew package definition that builds from upstream sources

**cask**

: Homebrew package definition that installs macOS native applications

**prefix**

: path in which Homebrew is installed, e.g. `/opt/homebrew` or
  `/home/linuxbrew/.linuxbrew`

**keg**

: installation destination directory of a given **formula** version, e.g.
  `/opt/homebrew/Cellar/foo/0.1`

**rack**

: directory containing one or more versioned **kegs**, e.g.
  `/opt/homebrew/Cellar/foo`

**keg-only**

: a **formula** is *keg-only* if it is not symlinked into Homebrew's prefix

**opt prefix**

: a symlink to the active version of a **keg**, e.g. `/opt/homebrew/opt/foo`

**Cellar**

: directory containing one or more named **racks**, e.g. `/opt/homebrew/Cellar`

**Caskroom**

: directory containing one or more named **casks**, e.g.
  `/opt/homebrew/Caskroom`

**external command**

: `brew` subcommand defined outside of the Homebrew/brew GitHub repository

**tap**

: directory (and usually Git repository) of **formulae**, **casks** and/or
  **external commands**

**bottle**

: pre-built **keg** poured into a **rack** of the **Cellar** instead of building
  from upstream sources

## ESSENTIAL COMMANDS

For the full command list, see the [COMMANDS](#commands) section.

With `--verbose` or `--debug`, many commands print extra debugging information.
Note that these options should only appear after a command.

Some command behaviour can be customised with environment variables; see the
[ENVIRONMENT](#environment) section.

### `install` *`formula`*

Install *`formula`*.

*`formula`* is usually the name of the formula to install, but it has other
syntaxes which are listed in the [SPECIFYING FORMULAE](#specifying-formulae)
section.

### `uninstall` *`formula`*

Uninstall *`formula`*.

### `list`

List all installed formulae.

### `search` \[*`text`*\|`/`*`text`*`/`\]

Perform a substring search of cask tokens and formula names for *`text`*. If
*`text`* is flanked by slashes, it is interpreted as a regular expression. The
search for *`text`* is extended online to `homebrew/core` and `homebrew/cask`.
If no search term is provided, all locally available formulae are listed.

## COMMANDS

### `alias` \[*`alias`* ... \| *`alias`*=*`command`*\]

Show existing aliases. If no aliases are given, print the whole list.

`--edit`

: Edit aliases in a text editor. Either one or all aliases may be opened at
  once. If the given alias doesn't exist it'll be pre-populated with a template.

### `analytics` \[*`subcommand`*\]

Control Homebrew's anonymous aggregate user behaviour analytics. Read more at
<https://docs.brew.sh/Analytics>.

`brew analytics` \[`state`\]

: Display the current state of Homebrew's analytics.

`brew analytics` (`on`\|`off`)

: Turn Homebrew's analytics on or off respectively.

### `autoremove` \[`--dry-run`\]

Uninstall formulae that were only installed as a dependency of another formula
and are now no longer needed.

`-n`, `--dry-run`

: List what would be uninstalled, but do not actually uninstall anything.

### `casks`

List all locally installable casks including short names.

### `cleanup` \[*`options`*\] \[*`formula`*\|*`cask`* ...\]

Remove stale lock files and outdated downloads for all formulae and casks, and
remove old versions of installed formulae. If arguments are specified, only do
this for the given formulae and casks. Removes all downloads more than 120 days
old. This can be adjusted with `$HOMEBREW_CLEANUP_MAX_AGE_DAYS`.

`--prune`

: Remove all cache files older than specified *`days`*. If you want to remove
  everything, use `--prune=all`.

`-n`, `--dry-run`

: Show what would be removed, but do not actually remove anything.

`-s`, `--scrub`

: Scrub the cache, including downloads for even the latest versions. Note that
  downloads for any installed formulae or casks will still not be deleted. If
  you want to delete those too: `rm -rf "$(brew --cache)"`

`--prune-prefix`

: Only prune the symlinks and directories from the prefix and remove no other
  files.

### `command` *`command`* \[...\]

Display the path to the file being used when invoking `brew` *`cmd`*.

### `commands` \[`--quiet`\] \[`--include-aliases`\]

Show lists of built-in and external commands.

`-q`, `--quiet`

: List only the names of commands without category headers.

`--include-aliases`

: Include aliases of internal commands.

### `completions` \[*`subcommand`*\]

Control whether Homebrew automatically links external tap shell completion
files. Read more at <https://docs.brew.sh/Shell-Completion>.

`brew completions` \[`state`\]

: Display the current state of Homebrew's completions.

`brew completions` (`link`\|`unlink`)

: Link or unlink Homebrew's completions.

### `config`, `--config`

Show Homebrew and system configuration info useful for debugging. If you file a
bug report, you will be required to provide this information.

### `deps` \[*`options`*\] \[*`formula`*\|*`cask`* ...\]

Show dependencies for *`formula`*. When given multiple formula arguments, show
the intersection of dependencies for each formula. By default, `deps` shows all
required and recommended dependencies.

If any version of each formula argument is installed and no other options are
passed, this command displays their actual runtime dependencies (similar to
`brew linkage`), which may differ from the current versions' stated dependencies
if the installed versions are outdated.

*Note:* `--missing` and `--skip-recommended` have precedence over `--include-*`.

`-n`, `--topological`

: Sort dependencies in topological order.

`-1`, `--direct`

: Show only the direct dependencies declared in the formula.

`--union`

: Show the union of dependencies for multiple *`formula`*, instead of the
  intersection.

`--full-name`

: List dependencies by their full name.

`--include-implicit`

: Include implicit dependencies used to download and unpack source files.

`--include-build`

: Include `:build` dependencies for *`formula`*.

`--include-optional`

: Include `:optional` dependencies for *`formula`*.

`--include-test`

: Include `:test` dependencies for *`formula`* (non-recursive).

`--skip-recommended`

: Skip `:recommended` dependencies for *`formula`*.

`--include-requirements`

: Include requirements in addition to dependencies for *`formula`*.

`--tree`

: Show dependencies as a tree. When given multiple formula arguments, show
  individual trees for each formula.

`--graph`

: Show dependencies as a directed graph.

`--dot`

: Show text-based graph description in DOT format.

`--annotate`

: Mark any build, test, implicit, optional, or recommended dependencies as such
  in the output.

`--installed`

: List dependencies for formulae that are currently installed. If *`formula`* is
  specified, list only its dependencies that are currently installed.

`--missing`

: Show only missing dependencies.

`--eval-all`

: Evaluate all available formulae and casks, whether installed or not, to list
  their dependencies.

`--for-each`

: Switch into the mode used by the `--eval-all` option, but only list
  dependencies for each provided *`formula`*, one formula per line. This is used
  for debugging the `--installed`/`--eval-all` display mode.

`--HEAD`

: Show dependencies for HEAD version instead of stable version.

`--os`

: Show dependencies for the given operating system.

`--arch`

: Show dependencies for the given CPU architecture.

`--formula`

: Treat all named arguments as formulae.

`--cask`

: Treat all named arguments as casks.

### `desc` \[*`options`*\] *`formula`*\|*`cask`*\|*`text`*\|`/`*`regex`*`/` \[...\]

Display *`formula`*'s name and one-line description. The cache is created on the
first search, making that search slower than subsequent ones.

`-s`, `--search`

: Search both names and descriptions for *`text`*. If *`text`* is flanked by
  slashes, it is interpreted as a regular expression.

`-n`, `--name`

: Search just names for *`text`*. If *`text`* is flanked by slashes, it is
  interpreted as a regular expression.

`-d`, `--description`

: Search just descriptions for *`text`*. If *`text`* is flanked by slashes, it
  is interpreted as a regular expression.

`--eval-all`

: Evaluate all available formulae and casks, whether installed or not, to search
  their descriptions. Implied if `$HOMEBREW_EVAL_ALL` is set.

`--formula`

: Treat all named arguments as formulae.

`--cask`

: Treat all named arguments as casks.

### `developer` \[*`subcommand`*\]

Control Homebrew's developer mode. When developer mode is enabled, `brew update`
will update Homebrew to the latest commit on the `master` branch instead of the
latest stable version along with some other behaviour changes.

`brew developer` \[`state`\]

: Display the current state of Homebrew's developer mode.

`brew developer` (`on`\|`off`)

: Turn Homebrew's developer mode on or off respectively.

### `docs`

Open Homebrew's online documentation at <https://docs.brew.sh> in a browser.

### `doctor`, `dr` \[`--list-checks`\] \[`--audit-debug`\] \[*`diagnostic_check`* ...\]

Check your system for potential problems. Will exit with a non-zero status if
any potential problems are found.

Please note that these warnings are just used to help the Homebrew maintainers
with debugging if you file an issue. If everything you use Homebrew for is
working fine: please don't worry or file an issue; just ignore this.

`--list-checks`

: List all audit methods, which can be run individually if provided as
  arguments.

`-D`, `--audit-debug`

: Enable debugging and profiling of audit methods.

### `fetch` \[*`options`*\] *`formula`*\|*`cask`* \[...\]

Download a bottle (if available) or source packages for *`formula`*e and
binaries for *`cask`*s. For files, also print SHA-256 checksums.

`--os`

: Download for the given operating system. (Pass `all` to download for all
  operating systems.)

`--arch`

: Download for the given CPU architecture. (Pass `all` to download for all
  architectures.)

`--bottle-tag`

: Download a bottle for given tag.

`--HEAD`

: Fetch HEAD version instead of stable version.

`-f`, `--force`

: Remove a previously cached version and re-fetch.

`-v`, `--verbose`

: Do a verbose VCS checkout, if the URL represents a VCS. This is useful for
  seeing if an existing VCS cache has been updated.

`--retry`

: Retry if downloading fails or re-download if the checksum of a previously
  cached version no longer matches. Tries at most 5 times with exponential
  backoff.

`--deps`

: Also download dependencies for any listed *`formula`*.

`-s`, `--build-from-source`

: Download source packages rather than a bottle.

`--build-bottle`

: Download source packages (for eventual bottling) rather than a bottle.

`--force-bottle`

: Download a bottle if it exists for the current or newest version of macOS,
  even if it would not be used during installation.

`--[no-]quarantine`

: Disable/enable quarantining of downloads (default: enabled).

`--formula`

: Treat all named arguments as formulae.

`--cask`

: Treat all named arguments as casks.

### `formulae`

List all locally installable formulae including short names.

### `gist-logs` \[*`options`*\] *`formula`*

Upload logs for a failed build of *`formula`* to a new Gist. Presents an error
message if no logs are found.

`--with-hostname`

: Include the hostname in the Gist.

`-n`, `--new-issue`

: Automatically create a new issue in the appropriate GitHub repository after
  creating the Gist.

`-p`, `--private`

: The Gist will be marked private and will not appear in listings but will be
  accessible with its link.

### `help` \[*`command`* ...\]

Outputs the usage instructions for `brew` *`command`*. Equivalent to `brew
--help` *`command`*.

### `home`, `homepage` \[`--formula`\] \[`--cask`\] \[*`formula`*\|*`cask`* ...\]

Open a *`formula`* or *`cask`*'s homepage in a browser, or open Homebrew's own
homepage if no argument is provided.

`--formula`

: Treat all named arguments as formulae.

`--cask`

: Treat all named arguments as casks.

### `info`, `abv` \[*`options`*\] \[*`formula`*\|*`cask`* ...\]

Display brief statistics for your Homebrew installation. If a *`formula`* or
*`cask`* is provided, show summary of information about it.

`--analytics`

: List global Homebrew analytics data or, if specified, installation and build
  error data for *`formula`* (provided neither `$HOMEBREW_NO_ANALYTICS` nor
  `$HOMEBREW_NO_GITHUB_API` are set).

`--days`

: How many days of analytics data to retrieve. The value for *`days`* must be
  `30`, `90` or `365`. The default is `30`.

`--category`

: Which type of analytics data to retrieve. The value for *`category`* must be
  `install`, `install-on-request` or `build-error`; `cask-install` or
  `os-version` may be specified if *`formula`* is not. The default is `install`.

`--github`

: Open the GitHub source page for *`formula`* and *`cask`* in a browser. To view
  the history locally: `brew log -p` *`formula`* or *`cask`*

`--fetch-manifest`

: Fetch GitHub Packages manifest for extra information when *`formula`* is not
  installed.

`--json`

: Print a JSON representation. Currently the default value for *`version`* is
  `v1` for *`formula`*. For *`formula`* and *`cask`* use `v2`. See the docs for
  examples of using the JSON output: <https://docs.brew.sh/Querying-Brew>

`--installed`

: Print JSON of formulae that are currently installed.

`--eval-all`

: Evaluate all available formulae and casks, whether installed or not, to print
  their JSON. Implied if `$HOMEBREW_EVAL_ALL` is set.

`--variations`

: Include the variations hash in each formula's JSON output.

`-v`, `--verbose`

: Show more verbose analytics data for *`formula`*.

`--formula`

: Treat all named arguments as formulae.

`--cask`

: Treat all named arguments as casks.

### `install` \[*`options`*\] *`formula`*\|*`cask`* \[...\]

Install a *`formula`* or *`cask`*. Additional options specific to a *`formula`*
may be appended to the command.

Unless `$HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK` is set, `brew upgrade` or `brew
reinstall` will be run for outdated dependents and dependents with broken
linkage, respectively.

Unless `$HOMEBREW_NO_INSTALL_CLEANUP` is set, `brew cleanup` will then be run
for the installed formulae or, every 30 days, for all formulae.

Unless `$HOMEBREW_NO_INSTALL_UPGRADE` is set, `brew install` *`formula`* will
upgrade *`formula`* if it is already installed but outdated.

`-d`, `--debug`

: If brewing fails, open an interactive debugging session with access to IRB or
  a shell inside the temporary build directory.

`--display-times`

: Print install times for each package at the end of the run.

`-f`, `--force`

: Install formulae without checking for previously installed keg-only or
  non-migrated versions. When installing casks, overwrite existing files
  (binaries and symlinks are excluded, unless originally from the same cask).

`-v`, `--verbose`

: Print the verification and post-install steps.

`-n`, `--dry-run`

: Show what would be installed, but do not actually install anything.

`--formula`

: Treat all named arguments as formulae.

`--ignore-dependencies`

: An unsupported Homebrew development option to skip installing any dependencies
  of any kind. If the dependencies are not already present, the formula will
  have issues. If you're not developing Homebrew, consider adjusting your PATH
  rather than using this option.

`--only-dependencies`

: Install the dependencies with specified options but do not install the formula
  itself.

`--cc`

: Attempt to compile using the specified *`compiler`*, which should be the name
  of the compiler's executable, e.g. `gcc-9` for GCC 9. In order to use LLVM's
  clang, specify `llvm_clang`. To use the Apple-provided clang, specify `clang`.
  This option will only accept compilers that are provided by Homebrew or
  bundled with macOS. Please do not file issues if you encounter errors while
  using this option.

`-s`, `--build-from-source`

: Compile *`formula`* from source even if a bottle is provided. Dependencies
  will still be installed from bottles if they are available.

`--force-bottle`

: Install from a bottle if it exists for the current or newest version of macOS,
  even if it would not normally be used for installation.

`--include-test`

: Install testing dependencies required to run `brew test` *`formula`*.

`--HEAD`

: If *`formula`* defines it, install the HEAD version, aka. main, trunk,
  unstable, master.

`--fetch-HEAD`

: Fetch the upstream repository to detect if the HEAD installation of the
  formula is outdated. Otherwise, the repository's HEAD will only be checked for
  updates when a new stable or development version has been released.

`--keep-tmp`

: Retain the temporary files created during installation.

`--debug-symbols`

: Generate debug symbols on build. Source will be retained in a cache directory.

`--build-bottle`

: Prepare the formula for eventual bottling during installation, skipping any
  post-install steps.

`--skip-post-install`

: Install but skip any post-install steps.

`--skip-link`

: Install but skip linking the keg into the prefix.

`--bottle-arch`

: Optimise bottles for the specified architecture rather than the oldest
  architecture supported by the version of macOS the bottles are built on.

`-i`, `--interactive`

: Download and patch *`formula`*, then open a shell. This allows the user to run
  `./configure --help` and otherwise determine how to turn the software package
  into a Homebrew package.

`-g`, `--git`

: Create a Git repository, useful for creating patches to the software.

`--overwrite`

: Delete files that already exist in the prefix while linking.

`--cask`

: Treat all named arguments as casks.

`--[no-]binaries`

: Disable/enable linking of helper executables (default: enabled).

`--require-sha`

: Require all casks to have a checksum.

`--[no-]quarantine`

: Disable/enable quarantining of downloads (default: enabled).

`--adopt`

: Adopt existing artifacts in the destination that are identical to those being
  installed. Cannot be combined with `--force`.

`--skip-cask-deps`

: Skip installing cask dependencies.

`--zap`

: For use with `brew reinstall --cask`. Remove all files associated with a cask.
  *May remove files which are shared between applications.*

### `leaves` \[`--installed-on-request`\] \[`--installed-as-dependency`\]

List installed formulae that are not dependencies of another installed formula
or cask.

`-r`, `--installed-on-request`

: Only list leaves that were manually installed.

`-p`, `--installed-as-dependency`

: Only list leaves that were installed as dependencies.

### `link`, `ln` \[*`options`*\] *`installed_formula`* \[...\]

Symlink all of *`formula`*'s installed files into Homebrew's prefix. This is
done automatically when you install formulae but can be useful for manual
installations.

`--overwrite`

: Delete files that already exist in the prefix while linking.

`-n`, `--dry-run`

: List files which would be linked or deleted by `brew link --overwrite` without
  actually linking or deleting any files.

`-f`, `--force`

: Allow keg-only formulae to be linked.

`--HEAD`

: Link the HEAD version of the formula if it is installed.

### `list`, `ls` \[*`options`*\] \[*`installed_formula`*\|*`installed_cask`* ...\]

List all installed formulae and casks. If *`formula`* is provided, summarise the
paths within its current keg. If *`cask`* is provided, list its artifacts.

`--formula`

: List only formulae, or treat all named arguments as formulae.

`--cask`

: List only casks, or treat all named arguments as casks.

`--full-name`

: Print formulae with fully-qualified names. Unless `--full-name`, `--versions`
  or `--pinned` are passed, other options (i.e. `-1`, `-l`, `-r` and `-t`) are
  passed to `ls`(1) which produces the actual output.

`--versions`

: Show the version number for installed formulae, or only the specified formulae
  if *`formula`* are provided.

`--multiple`

: Only show formulae with multiple versions installed.

`--pinned`

: List only pinned formulae, or only the specified (pinned) formulae if
  *`formula`* are provided. See also `pin`, `unpin`.

`--installed-on-request`

: List the formulae installed on request.

`--installed-as-dependency`

: List the formulae installed as dependencies.

`--poured-from-bottle`

: List the formulae installed from a bottle.

`--built-from-source`

: List the formulae compiled from source.

`-1`

: Force output to be one entry per line. This is the default when output is not
  to a terminal.

`-l`

: List formulae and/or casks in long format. Has no effect when a formula or
  cask name is passed as an argument.

`-r`

: Reverse the order of the formulae and/or casks sort to list the oldest entries
  first. Has no effect when a formula or cask name is passed as an argument.

`-t`

: Sort formulae and/or casks by time modified, listing most recently modified
  first. Has no effect when a formula or cask name is passed as an argument.

### `log` \[*`options`*\] \[*`formula`*\|*`cask`*\]

Show the `git log` for *`formula`* or *`cask`*, or show the log for the Homebrew
repository if no formula or cask is provided.

`-p`, `--patch`

: Also print patch from commit.

`--stat`

: Also print diffstat from commit.

`--oneline`

: Print only one line per commit.

`-1`

: Print only one commit.

`-n`, `--max-count`

: Print only a specified number of commits.

`--formula`

: Treat all named arguments as formulae.

`--cask`

: Treat all named arguments as casks.

### `migrate` \[*`options`*\] *`installed_formula`*\|*`installed_cask`* \[...\]

Migrate renamed packages to new names, where *`formula`* are old names of
packages.

`-f`, `--force`

: Treat installed *`formula`* and provided *`formula`* as if they are from the
  same taps and migrate them anyway.

`-n`, `--dry-run`

: Show what would be migrated, but do not actually migrate anything.

`--formula`

: Only migrate formulae.

`--cask`

: Only migrate casks.

### `missing` \[`--hide=`\] \[*`formula`* ...\]

Check the given *`formula`* kegs for missing dependencies. If no *`formula`* are
provided, check all kegs. Will exit with a non-zero status if any kegs are found
to be missing dependencies.

`--hide`

: Act as if none of the specified *`hidden`* are installed. *`hidden`* should be
  a comma-separated list of formulae.

### `nodenv-sync`

Create symlinks for Homebrew's installed NodeJS versions in
`~/.nodenv/versions`.

Note that older version symlinks will also be created so e.g. NodeJS 19.1.0 will
also be symlinked to 19.0.0.

### `options` \[*`options`*\] \[*`formula`* ...\]

Show install options specific to *`formula`*.

`--compact`

: Show all options on a single line separated by spaces.

`--installed`

: Show options for formulae that are currently installed.

`--eval-all`

: Evaluate all available formulae and casks, whether installed or not, to show
  their options.

`--command`

: Show options for the specified *`command`*.

### `outdated` \[*`options`*\] \[*`formula`*\|*`cask`* ...\]

List installed casks and formulae that have an updated version available. By
default, version information is displayed in interactive shells and suppressed
otherwise.

`-q`, `--quiet`

: List only the names of outdated kegs (takes precedence over `--verbose`).

`-v`, `--verbose`

: Include detailed version information.

`--formula`

: List only outdated formulae.

`--cask`

: List only outdated casks.

`--json`

: Print output in JSON format. There are two versions: `v1` and `v2`. `v1` is
  deprecated and is currently the default if no version is specified. `v2`
  prints outdated formulae and casks.

`--fetch-HEAD`

: Fetch the upstream repository to detect if the HEAD installation of the
  formula is outdated. Otherwise, the repository's HEAD will only be checked for
  updates when a new stable or development version has been released.

`-g`, `--greedy`

: Also include outdated casks with `auto_updates true` or `version :latest`.

`--greedy-latest`

: Also include outdated casks including those with `version :latest`.

`--greedy-auto-updates`

: Also include outdated casks including those with `auto_updates true`.

### `pin` *`installed_formula`* \[...\]

Pin the specified *`formula`*, preventing them from being upgraded when issuing
the `brew upgrade` *`formula`* command. See also `unpin`.

*Note:* Other packages which depend on newer versions of a pinned formula might
not install or run correctly.

### `postinstall`, `post_install` *`installed_formula`* \[...\]

Rerun the post-install steps for *`formula`*.

### `pyenv-sync`

Create symlinks for Homebrew's installed Python versions in `~/.pyenv/versions`.

Note that older patch version symlinks will be created and linked to the minor
version so e.g. Python 3.11.0 will also be symlinked to 3.11.3.

### `rbenv-sync`

Create symlinks for Homebrew's installed Ruby versions in `~/.rbenv/versions`.

Note that older version symlinks will also be created so e.g. Ruby 3.2.1 will
also be symlinked to 3.2.0.

### `readall` \[*`options`*\] \[*`tap`* ...\]

Import all items from the specified *`tap`*, or from all installed taps if none
is provided. This can be useful for debugging issues across all items when
making significant changes to `formula.rb`, testing the performance of loading
all items or checking if any current formulae/casks have Ruby issues.

`--os`

: Read using the given operating system. (Pass `all` to simulate all operating
  systems.)

`--arch`

: Read using the given CPU architecture. (Pass `all` to simulate all
  architectures.)

`--aliases`

: Verify any alias symlinks in each tap.

`--syntax`

: Syntax-check all of Homebrew's Ruby files (if no *`tap`* is passed).

`--eval-all`

: Evaluate all available formulae and casks, whether installed or not. Implied
  if `$HOMEBREW_EVAL_ALL` is set.

`--no-simulate`

: Don't simulate other system configurations when checking formulae and casks.

### `reinstall` \[*`options`*\] *`formula`*\|*`cask`* \[...\]

Uninstall and then reinstall a *`formula`* or *`cask`* using the same options it
was originally installed with, plus any appended options specific to a
*`formula`*.

Unless `$HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK` is set, `brew upgrade` or `brew
reinstall` will be run for outdated dependents and dependents with broken
linkage, respectively.

Unless `$HOMEBREW_NO_INSTALL_CLEANUP` is set, `brew cleanup` will then be run
for the reinstalled formulae or, every 30 days, for all formulae.

`-d`, `--debug`

: If brewing fails, open an interactive debugging session with access to IRB or
  a shell inside the temporary build directory.

`--display-times`

: Print install times for each package at the end of the run.

`-f`, `--force`

: Install without checking for previously installed keg-only or non-migrated
  versions.

`-v`, `--verbose`

: Print the verification and post-install steps.

`--formula`

: Treat all named arguments as formulae.

`-s`, `--build-from-source`

: Compile *`formula`* from source even if a bottle is available.

`-i`, `--interactive`

: Download and patch *`formula`*, then open a shell. This allows the user to run
  `./configure --help` and otherwise determine how to turn the software package
  into a Homebrew package.

`--force-bottle`

: Install from a bottle if it exists for the current or newest version of macOS,
  even if it would not normally be used for installation.

`--keep-tmp`

: Retain the temporary files created during installation.

`--debug-symbols`

: Generate debug symbols on build. Source will be retained in a cache directory.

`-g`, `--git`

: Create a Git repository, useful for creating patches to the software.

`--cask`

: Treat all named arguments as casks.

`--[no-]binaries`

: Disable/enable linking of helper executables (default: enabled).

`--require-sha`

: Require all casks to have a checksum.

`--[no-]quarantine`

: Disable/enable quarantining of downloads (default: enabled).

`--adopt`

: Adopt existing artifacts in the destination that are identical to those being
  installed. Cannot be combined with `--force`.

`--skip-cask-deps`

: Skip installing cask dependencies.

`--zap`

: For use with `brew reinstall --cask`. Remove all files associated with a cask.
  *May remove files which are shared between applications.*

### `search`, `-S` \[*`options`*\] *`text`*\|`/`*`regex`*`/` \[...\]

Perform a substring search of cask tokens and formula names for *`text`*. If
*`text`* is flanked by slashes, it is interpreted as a regular expression.

`--formula`

: Search for formulae.

`--cask`

: Search for casks.

`--desc`

: Search for formulae with a description matching *`text`* and casks with a name
  or description matching *`text`*.

`--eval-all`

: Evaluate all available formulae and casks, whether installed or not, to search
  their descriptions. Implied if `$HOMEBREW_EVAL_ALL` is set.

`--pull-request`

: Search for GitHub pull requests containing *`text`*.

`--open`

: Search for only open GitHub pull requests.

`--closed`

: Search for only closed GitHub pull requests.

`--repology`

: Search for *`text`* in the given database.

`--macports`

: Search for *`text`* in the given database.

`--fink`

: Search for *`text`* in the given database.

`--opensuse`

: Search for *`text`* in the given database.

`--fedora`

: Search for *`text`* in the given database.

`--archlinux`

: Search for *`text`* in the given database.

`--debian`

: Search for *`text`* in the given database.

`--ubuntu`

: Search for *`text`* in the given database.

### `setup-ruby` \[*`command`* ...\]

Installs and configures Homebrew's Ruby. If `command` is passed, it will only
run Bundler if necessary for that command.

### `shellenv` \[*`shell`* ...\]

Valid shells: bash\|csh\|fish\|pwsh\|sh\|tcsh\|zsh

Print export statements. When run in a shell, this installation of Homebrew will
be added to your `PATH`, `MANPATH`, and `INFOPATH`.

The variables `$HOMEBREW_PREFIX`, `$HOMEBREW_CELLAR` and `$HOMEBREW_REPOSITORY`
are also exported to avoid querying them multiple times. To help guarantee
idempotence, this command produces no output when Homebrew's `bin` and `sbin`
directories are first and second respectively in your `PATH`. Consider adding
evaluation of this command's output to your dotfiles (e.g. `~/.bash_profile` or
~/.zprofile` on macOS and ~/.bashrc` or ~/.zshrc` on Linux) with:
  `eval "$(brew shellenv)"\`

The shell can be specified explicitly with a supported shell name parameter.
Unknown shells will output POSIX exports.

### `tab` \[*`options`*\] *`installed_formula`*\|*`installed_cask`* \[...\]

Edit tab information for installed formulae or casks.

This can be useful when you want to control whether an installed formula should
be removed by `brew autoremove`. To prevent removal, mark the formula as
installed on request; to allow removal, mark the formula as not installed on
request.

`--installed-on-request`

: Mark *`installed_formula`* or *`installed_cask`* as installed on request.

`--no-installed-on-request`

: Mark *`installed_formula`* or *`installed_cask`* as not installed on request.

`--formula`

: Only mark formulae.

`--cask`

: Only mark casks.

### `tap` \[*`options`*\] \[*`user`*`/`*`repo`*\] \[*`URL`*\]

Tap a formula repository. If no arguments are provided, list all installed taps.

With *`URL`* unspecified, tap a formula repository from GitHub using HTTPS.
Since so many taps are hosted on GitHub, this command is a shortcut for `brew
tap` *`user`*`/`*`repo`* `https://github.com/`*`user`*`/homebrew-`*`repo`*.

With *`URL`* specified, tap a formula repository from anywhere, using any
transport protocol that `git`(1) handles. The one-argument form of `tap`
simplifies but also limits. This two-argument command makes no assumptions, so
taps can be cloned from places other than GitHub and using protocols other than
HTTPS, e.g. SSH, git, HTTP, FTP(S), rsync.

`--custom-remote`

: Install or change a tap with a custom remote. Useful for mirrors.

`--repair`

: Add missing symlinks to tap manpages and shell completions. Correct git remote
  refs for any taps where upstream HEAD branch has been renamed.

`--eval-all`

: Evaluate all the formulae, casks and aliases in the new tap to check validity.
  Implied if `$HOMEBREW_EVAL_ALL` is set.

`-f`, `--force`

: Force install core taps even under API mode.

### `tap-info` \[`--installed`\] \[`--json`\] \[*`tap`* ...\]

Show detailed information about one or more *`tap`*s. If no *`tap`* names are
provided, display brief statistics for all installed taps.

`--installed`

: Show information on each installed tap.

`--json`

: Print a JSON representation of *`tap`*. Currently the default and only
  accepted value for *`version`* is `v1`. See the docs for examples of using the
  JSON output: <https://docs.brew.sh/Querying-Brew>

### `unalias` *`alias`* \[...\]

Remove aliases.

### `uninstall`, `remove`, `rm` \[*`options`*\] *`installed_formula`*\|*`installed_cask`* \[...\]

Uninstall a *`formula`* or *`cask`*.

`-f`, `--force`

: Delete all installed versions of *`formula`*. Uninstall even if *`cask`* is
  not installed, overwrite existing files and ignore errors when removing files.

`--zap`

: Remove all files associated with a *`cask`*. *May remove files which are
  shared between applications.*

`--ignore-dependencies`

: Don't fail uninstall, even if *`formula`* is a dependency of any installed
  formulae.

`--formula`

: Treat all named arguments as formulae.

`--cask`

: Treat all named arguments as casks.

### `unlink` \[`--dry-run`\] *`installed_formula`* \[...\]

Remove symlinks for *`formula`* from Homebrew's prefix. This can be useful for
temporarily disabling a formula: `brew unlink` *`formula`* `&&` *`commands`* `&&
brew link` *`formula`*

`-n`, `--dry-run`

: List files which would be unlinked without actually unlinking or deleting any
  files.

### `unpin` *`installed_formula`* \[...\]

Unpin *`formula`*, allowing them to be upgraded by `brew upgrade` *`formula`*.
See also `pin`.

### `untap` \[`--force`\] *`tap`* \[...\]

Remove a tapped formula repository.

`-f`, `--force`

: Untap even if formulae or casks from this tap are currently installed.

### `update`, `up` \[*`options`*\]

Fetch the newest version of Homebrew and all formulae from GitHub using `git`(1)
and perform any necessary migrations.

`--merge`

: Use `git merge` to apply updates (rather than `git rebase`).

`--auto-update`

: Run on auto-updates (e.g. before `brew install`). Skips some slower steps.

`-f`, `--force`

: Always do a slower, full update check (even if unnecessary).

`-v`, `--verbose`

: Print the directories checked and `git` operations performed.

`-d`, `--debug`

: Display a trace of all shell commands as they are executed.

### `update-reset` \[*`repository`* ...\]

Fetch and reset Homebrew and all tap repositories (or any specified
*`repository`*) using `git`(1) to their latest `origin/HEAD`.

*Note:* this will destroy all your uncommitted or committed changes.

### `upgrade` \[*`options`*\] \[*`installed_formula`*\|*`installed_cask`* ...\]

Upgrade outdated casks and outdated, unpinned formulae using the same options
they were originally installed with, plus any appended brew formula options. If
*`cask`* or *`formula`* are specified, upgrade only the given *`cask`* or
*`formula`* kegs (unless they are pinned; see `pin`, `unpin`).

Unless `$HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK` is set, `brew upgrade` or `brew
reinstall` will be run for outdated dependents and dependents with broken
linkage, respectively.

Unless `$HOMEBREW_NO_INSTALL_CLEANUP` is set, `brew cleanup` will then be run
for the upgraded formulae or, every 30 days, for all formulae.

`-d`, `--debug`

: If brewing fails, open an interactive debugging session with access to IRB or
  a shell inside the temporary build directory.

`--display-times`

: Print install times for each package at the end of the run.

`-f`, `--force`

: Install formulae without checking for previously installed keg-only or
  non-migrated versions. When installing casks, overwrite existing files
  (binaries and symlinks are excluded, unless originally from the same cask).

`-v`, `--verbose`

: Print the verification and post-install steps.

`-n`, `--dry-run`

: Show what would be upgraded, but do not actually upgrade anything.

`--formula`

: Treat all named arguments as formulae. If no named arguments are specified,
  upgrade only outdated formulae.

`-s`, `--build-from-source`

: Compile *`formula`* from source even if a bottle is available.

`-i`, `--interactive`

: Download and patch *`formula`*, then open a shell. This allows the user to run
  `./configure --help` and otherwise determine how to turn the software package
  into a Homebrew package.

`--force-bottle`

: Install from a bottle if it exists for the current or newest version of macOS,
  even if it would not normally be used for installation.

`--fetch-HEAD`

: Fetch the upstream repository to detect if the HEAD installation of the
  formula is outdated. Otherwise, the repository's HEAD will only be checked for
  updates when a new stable or development version has been released.

`--keep-tmp`

: Retain the temporary files created during installation.

`--debug-symbols`

: Generate debug symbols on build. Source will be retained in a cache directory.

`--overwrite`

: Delete files that already exist in the prefix while linking.

`--cask`

: Treat all named arguments as casks. If no named arguments are specified,
  upgrade only outdated casks.

`--skip-cask-deps`

: Skip installing cask dependencies.

`-g`, `--greedy`

: Also include casks with `auto_updates true` or `version :latest`.

`--greedy-latest`

: Also include casks with `version :latest`.

`--greedy-auto-updates`

: Also include casks with `auto_updates true`.

`--[no-]binaries`

: Disable/enable linking of helper executables (default: enabled).

`--require-sha`

: Require all casks to have a checksum.

`--[no-]quarantine`

: Disable/enable quarantining of downloads (default: enabled).

### `uses` \[*`options`*\] *`formula`* \[...\]

Show formulae and casks that specify *`formula`* as a dependency; that is, show
dependents of *`formula`*. When given multiple formula arguments, show the
intersection of formulae that use *`formula`*. By default, `uses` shows all
formulae and casks that specify *`formula`* as a required or recommended
dependency for their stable builds.

*Note:* `--missing` and `--skip-recommended` have precedence over `--include-*`.

`--recursive`

: Resolve more than one level of dependencies.

`--installed`

: Only list formulae and casks that are currently installed.

`--missing`

: Only list formulae and casks that are not currently installed.

`--eval-all`

: Evaluate all available formulae and casks, whether installed or not, to show
  their dependents.

`--include-implicit`

: Include formulae that have *`formula`* as an implicit dependency for
  downloading and unpacking source files.

`--include-build`

: Include formulae that specify *`formula`* as a `:build` dependency.

`--include-test`

: Include formulae that specify *`formula`* as a `:test` dependency.

`--include-optional`

: Include formulae that specify *`formula`* as an `:optional` dependency.

`--skip-recommended`

: Skip all formulae that specify *`formula`* as a `:recommended` dependency.

`--formula`

: Include only formulae.

`--cask`

: Include only casks.

### `--cache` \[*`options`*\] \[*`formula`*\|*`cask`* ...\]

Display Homebrew's download cache. See also `$HOMEBREW_CACHE`.

If a *`formula`* or *`cask`* is provided, display the file or directory used to
cache it.

`--os`

: Show cache file for the given operating system. (Pass `all` to show cache
  files for all operating systems.)

`--arch`

: Show cache file for the given CPU architecture. (Pass `all` to show cache
  files for all architectures.)

`-s`, `--build-from-source`

: Show the cache file used when building from source.

`--force-bottle`

: Show the cache file used when pouring a bottle.

`--bottle-tag`

: Show the cache file used when pouring a bottle for the given tag.

`--HEAD`

: Show the cache file used when building from HEAD.

`--formula`

: Only show cache files for formulae.

`--cask`

: Only show cache files for casks.

### `--caskroom` \[*`cask`* ...\]

Display Homebrew's Caskroom path.

If *`cask`* is provided, display the location in the Caskroom where *`cask`*
would be installed, without any sort of versioned directory as the last path.

### `--cellar` \[*`formula`* ...\]

Display Homebrew's Cellar path. *Default:* `$(brew --prefix)/Cellar`, or if that
directory doesn't exist, `$(brew --repository)/Cellar`.

If *`formula`* is provided, display the location in the Cellar where *`formula`*
would be installed, without any sort of versioned directory as the last path.

### `--env`, `environment` \[`--shell=`\] \[`--plain`\] \[*`formula`* ...\]

Summarise Homebrew's build environment as a plain list.

If the command's output is sent through a pipe and no shell is specified, the
list is formatted for export to `bash`(1) unless `--plain` is passed.

`--shell`

: Generate a list of environment variables for the specified shell, or
  `--shell=auto` to detect the current shell.

`--plain`

: Generate plain output even when piped.

### `--prefix` \[`--unbrewed`\] \[`--installed`\] \[*`formula`* ...\]

Display Homebrew's install path. *Default:*

* macOS ARM: `/opt/homebrew`
* macOS Intel: `/usr/local`
* Linux: `/home/linuxbrew/.linuxbrew`

If *`formula`* is provided, display the location where *`formula`* is or would
be installed.

`--unbrewed`

: List files in Homebrew's prefix not installed by Homebrew.

`--installed`

: Outputs nothing and returns a failing status code if *`formula`* is not
  installed.

### `--repository`, `--repo` \[*`tap`* ...\]

Display where Homebrew's Git repository is located.

If *`user`*`/`*`repo`* are provided, display where tap *`user`*`/`*`repo`*'s
directory is located.

### `--version`, `-v`

Print the version numbers of Homebrew, Homebrew/homebrew-core and
Homebrew/homebrew-cask (if tapped) to standard output.

## DEVELOPER COMMANDS

### `audit` \[*`options`*\] \[*`formula`*\|*`cask`* ...\]

Check *`formula`* or *`cask`* for Homebrew coding style violations. This should
be run before submitting a new formula or cask. If no *`formula`* or *`cask`*
are provided, check all locally available formulae and casks and skip style
checks. Will exit with a non-zero status if any errors are found.

`--os`

: Audit the given operating system. (Pass `all` to audit all operating systems.)

`--arch`

: Audit the given CPU architecture. (Pass `all` to audit all architectures.)

`--strict`

: Run additional, stricter style checks.

`--git`

: Run additional, slower style checks that navigate the Git repository.

`--online`

: Run additional, slower style checks that require a network connection.

`--installed`

: Only check formulae and casks that are currently installed.

`--eval-all`

: Evaluate all available formulae and casks, whether installed or not, to audit
  them. Implied if `HOMEBREW_EVAL_ALL` is set.

`--new`

: Run various additional style checks to determine if a new formula or cask is
  eligible for Homebrew. This should be used when creating new formulae or casks
  and implies `--strict` and `--online`.

`--[no-]signing`

: Audit for app signatures, which are required by macOS on ARM.

`--token-conflicts`

: Audit for token conflicts.

`--tap`

: Check formulae and casks within the given tap, specified as
  *`user`*`/`*`repo`*.

`--fix`

: Fix style violations automatically using RuboCop's auto-correct feature.

`--display-filename`

: Prefix every line of output with the file or formula name being audited, to
  make output easy to grep.

`--skip-style`

: Skip running non-RuboCop style checks. Useful if you plan on running `brew
  style` separately. Enabled by default unless a formula is specified by name.

`-D`, `--audit-debug`

: Enable debugging and profiling of audit methods.

`--only`

: Specify a comma-separated *`method`* list to only run the methods named
  `audit_`*`method`*.

`--except`

: Specify a comma-separated *`method`* list to skip running the methods named
  `audit_`*`method`*.

`--only-cops`

: Specify a comma-separated *`cops`* list to check for violations of only the
  listed RuboCop cops.

`--except-cops`

: Specify a comma-separated *`cops`* list to skip checking for violations of the
  listed RuboCop cops.

`--formula`

: Treat all named arguments as formulae.

`--cask`

: Treat all named arguments as casks.

### `bottle` \[*`options`*\] *`installed_formula`*\|*`file`* \[...\]

Generate a bottle (binary package) from a formula that was installed with
`--build-bottle`. If the formula specifies a rebuild version, it will be
incremented in the generated DSL. Passing `--keep-old` will attempt to keep it
at its original value, while `--no-rebuild` will remove it.

`--skip-relocation`

: Do not check if the bottle can be marked as relocatable.

`--force-core-tap`

: Build a bottle even if *`formula`* is not in `homebrew/core` or any installed
  taps.

`--no-rebuild`

: If the formula specifies a rebuild version, remove it from the generated DSL.

`--keep-old`

: If the formula specifies a rebuild version, attempt to preserve its value in
  the generated DSL.

`--json`

: Write bottle information to a JSON file, which can be used as the value for
  `--merge`.

`--merge`

: Generate an updated bottle block for a formula and optionally merge it into
  the formula file. Instead of a formula name, requires the path to a JSON file
  generated with `brew bottle --json` *`formula`*.

`--write`

: Write changes to the formula file. A new commit will be generated unless
  `--no-commit` is passed.

`--no-commit`

: When passed with `--write`, a new commit will not generated after writing
  changes to the formula file.

`--only-json-tab`

: When passed with `--json`, the tab will be written to the JSON file but not
  the bottle.

`--no-all-checks`

: Don't try to create an `all` bottle or stop a no-change upload.

`--committer`

: Specify a committer name and email in `git`'s standard author format.

`--root-url`

: Use the specified *`URL`* as the root of the bottle's URL instead of
  Homebrew's default.

`--root-url-using`

: Use the specified download strategy class for downloading the bottle's URL
  instead of Homebrew's default.

### `bump` \[*`options`*\] \[*`formula`*\|*`cask`* ...\]

Displays out-of-date packages and the latest version available. If the returned
current and livecheck versions differ or when querying specific packages, also
displays whether a pull request has been opened with the URL.

`--full-name`

: Print formulae/casks with fully-qualified names.

`--no-pull-requests`

: Do not retrieve pull requests from GitHub.

`--formula`

: Check only formulae.

`--cask`

: Check only casks.

`--eval-all`

: Evaluate all formulae and casks.

`--repology`

: Use Repology to check for outdated packages.

`--tap`

: Check formulae and casks within the given tap, specified as
  *`user`*`/`*`repo`*.

`--installed`

: Check formulae and casks that are currently installed.

`--no-fork`

: Don't try to fork the repository.

`--open-pr`

: Open a pull request for the new version if none have been opened yet.

`--start-with`

: Letter or word that the list of package results should alphabetically follow.

### `bump-cask-pr` \[*`options`*\] *`cask`*

Create a pull request to update *`cask`* with a new version.

A best effort to determine the *`SHA-256`* will be made if the value is not
supplied by the user.

`-n`, `--dry-run`

: Print what would be done rather than doing it.

`--write-only`

: Make the expected file modifications without taking any Git actions.

`--commit`

: When passed with `--write-only`, generate a new commit after writing changes
  to the cask file.

`--no-audit`

: Don't run `brew audit` before opening the PR.

`--no-style`

: Don't run `brew style --fix` before opening the PR.

`--no-browse`

: Print the pull request URL instead of opening in a browser.

`--no-fork`

: Don't try to fork the repository.

`--version`

: Specify the new *`version`* for the cask.

`--version-arm`

: Specify the new cask *`version`* for the ARM architecture.

`--version-intel`

: Specify the new cask *`version`* for the Intel architecture.

`--message`

: Prepend *`message`* to the default pull request message.

`--url`

: Specify the *`URL`* for the new download.

`--sha256`

: Specify the *`SHA-256`* checksum of the new download.

`--fork-org`

: Use the specified GitHub organization for forking.

### `bump-formula-pr` \[*`options`*\] \[*`formula`*\]

Create a pull request to update *`formula`* with a new URL or a new tag.

If a *`URL`* is specified, the *`SHA-256`* checksum of the new download should
also be specified. A best effort to determine the *`SHA-256`* will be made if
not supplied by the user.

If a *`tag`* is specified, the Git commit *`revision`* corresponding to that tag
should also be specified. A best effort to determine the *`revision`* will be
made if the value is not supplied by the user.

If a *`version`* is specified, a best effort to determine the *`URL`* and
*`SHA-256`* or the *`tag`* and *`revision`* will be made if both values are not
supplied by the user.

*Note:* this command cannot be used to transition a formula from a
URL-and-SHA-256 style specification into a tag-and-revision style specification,
nor vice versa. It must use whichever style specification the formula already
uses.

`-n`, `--dry-run`

: Print what would be done rather than doing it.

`--write-only`

: Make the expected file modifications without taking any Git actions.

`--commit`

: When passed with `--write-only`, generate a new commit after writing changes
  to the formula file.

`--no-audit`

: Don't run `brew audit` before opening the PR.

`--strict`

: Run `brew audit --strict` before opening the PR.

`--online`

: Run `brew audit --online` before opening the PR.

`--no-browse`

: Print the pull request URL instead of opening in a browser.

`--no-fork`

: Don't try to fork the repository.

`--mirror`

: Use the specified *`URL`* as a mirror URL. If *`URL`* is a comma-separated
  list of URLs, multiple mirrors will be added.

`--fork-org`

: Use the specified GitHub organization for forking.

`--version`

: Use the specified *`version`* to override the value parsed from the URL or
  tag. Note that `--version=0` can be used to delete an existing version
  override from a formula if it has become redundant.

`--message`

: Prepend *`message`* to the default pull request message.

`--url`

: Specify the *`URL`* for the new download. If a *`URL`* is specified, the
  *`SHA-256`* checksum of the new download should also be specified.

`--sha256`

: Specify the *`SHA-256`* checksum of the new download.

`--tag`

: Specify the new git commit *`tag`* for the formula.

`--revision`

: Specify the new commit *`revision`* corresponding to the specified git *`tag`*
  or specified *`version`*.

`-f`, `--force`

: Remove all mirrors if `--mirror` was not specified.

`--install-dependencies`

: Install missing dependencies required to update resources.

`--python-package-name`

: Use the specified *`package-name`* when finding Python resources for
  *`formula`*. If no package name is specified, it will be inferred from the
  formula's stable URL.

`--python-extra-packages`

: Include these additional Python packages when finding resources.

`--python-exclude-packages`

: Exclude these Python packages when finding resources.

### `bump-revision` \[*`options`*\] *`formula`* \[...\]

Create a commit to increment the revision of *`formula`*. If no revision is
present, "revision 1" will be added.

`-n`, `--dry-run`

: Print what would be done rather than doing it.

`--remove-bottle-block`

: Remove the bottle block in addition to bumping the revision.

`--write-only`

: Make the expected file modifications without taking any Git actions.

`--message`

: Append *`message`* to the default commit message.

### `bump-unversioned-casks` \[*`options`*\] *`cask`*\|*`tap`* \[...\]

Check all casks with unversioned URLs in a given *`tap`* for updates.

`-n`, `--dry-run`

: Do everything except caching state and opening pull requests.

`--limit`

: Maximum runtime in minutes.

`--state-file`

: File for caching state.

### `cat` \[`--formula`\] \[`--cask`\] *`formula`*\|*`cask`* \[...\]

Display the source of a *`formula`* or *`cask`*.

`--formula`

: Treat all named arguments as formulae.

`--cask`

: Treat all named arguments as casks.

### `contributions` \[--user=*`email|username`*\] \[*`--repositories`*`=`\] \[*`--csv`*\]

Summarise contributions to Homebrew repositories.

`--repositories`

: Specify a comma-separated list of repositories to search. Supported
  repositories: `brew`, `core`, `cask`, `bundle`, `command-not-found`,
  `test-bot` and `services`. Omitting this flag, or specifying
  `--repositories=primary`, searches only the main repositories: brew,core,cask.
  Specifying `--repositories=all`, searches all repositories.

`--from`

: Date (ISO-8601 format) to start searching contributions. Omitting this flag
  searches the last year.

`--to`

: Date (ISO-8601 format) to stop searching contributions.

`--user`

: Specify a comma-separated list of GitHub usernames or email addresses to find
  contributions from. Omitting this flag searches maintainers.

`--csv`

: Print a CSV of contributions across repositories over the time period.

### `create` \[*`options`*\] *`URL`*

Generate a formula or, with `--cask`, a cask for the downloadable file at
*`URL`* and open it in the editor. Homebrew will attempt to automatically derive
the formula name and version, but if it fails, you'll have to make your own
template. The `wget` formula serves as a simple example. For the complete API,
see: <https://rubydoc.brew.sh/Formula>

`--autotools`

: Create a basic template for an Autotools-style build.

`--cask`

: Create a basic template for a cask.

`--cmake`

: Create a basic template for a CMake-style build.

`--crystal`

: Create a basic template for a Crystal build.

`--go`

: Create a basic template for a Go build.

`--meson`

: Create a basic template for a Meson-style build.

`--node`

: Create a basic template for a Node build.

`--perl`

: Create a basic template for a Perl build.

`--python`

: Create a basic template for a Python build.

`--ruby`

: Create a basic template for a Ruby build.

`--rust`

: Create a basic template for a Rust build.

`--zig`

: Create a basic template for a Zig build.

`--no-fetch`

: Homebrew will not download *`URL`* to the cache and will thus not add its
  SHA-256 to the formula for you, nor will it check the GitHub API for GitHub
  projects (to fill out its description and homepage).

`--HEAD`

: Indicate that *`URL`* points to the package's repository rather than a file.

`--set-name`

: Explicitly set the *`name`* of the new formula or cask.

`--set-version`

: Explicitly set the *`version`* of the new formula or cask.

`--set-license`

: Explicitly set the *`license`* of the new formula.

`--tap`

: Generate the new formula within the given tap, specified as
  *`user`*`/`*`repo`*.

`-f`, `--force`

: Ignore errors for disallowed formula names and names that shadow aliases.

### `debugger` \[`--open`\] *`command`* \[...\]

Run the specified Homebrew command in debug mode.

To pass flags to the command, use `--` to separate them from the `brew` flags.
For example: `brew debugger -- list --formula`.

`-O`, `--open`

: Start remote debugging over a Unix socket.

### `dispatch-build-bottle` \[*`options`*\] *`formula`* \[...\]

Build bottles for these formulae with GitHub Actions.

`--tap`

: Target tap repository (default: `homebrew/core`).

`--timeout`

: Build timeout (in minutes, default: 60).

`--issue`

: If specified, post a comment to this issue number if the job fails.

`--macos`

: macOS version (or comma-separated list of versions) the bottle should be built
  for.

`--workflow`

: Dispatch specified workflow (default: `dispatch-build-bottle.yml`).

`--upload`

: Upload built bottles.

`--linux`

: Dispatch bottle for Linux (using GitHub runners).

`--linux-self-hosted`

: Dispatch bottle for Linux (using self-hosted runner).

`--linux-wheezy`

: Use Debian Wheezy container for building the bottle on Linux.

### `edit` \[*`options`*\] \[*`formula`*\|*`cask`*\|*`tap`* ...\]

Open a *`formula`*, *`cask`* or *`tap`* in the editor set by `EDITOR` or
`HOMEBREW_EDITOR`, or open the Homebrew repository for editing if no argument is
provided.

`--formula`

: Treat all named arguments as formulae.

`--cask`

: Treat all named arguments as casks.

`--print-path`

: Print the file path to be edited, without opening an editor.

### `extract` \[`--version=`\] \[`--git-revision=`\] \[`--force`\] *`formula`* *`tap`*

Look through repository history to find the most recent version of *`formula`*
and create a copy in *`tap`*. Specifically, the command will create the new
formula file at *`tap`*`/Formula/`*`formula`*`@`*`version`*`.rb`. If the tap is
not installed yet, attempt to install/clone the tap before continuing. To
extract a formula from a tap that is not `homebrew/core` use its fully-qualified
form of *`user`*`/`*`repo`*`/`*`formula`*.

`--git-revision`

: Search for the specified *`version`* of *`formula`* starting at *`revision`*
  instead of HEAD.

`--version`

: Extract the specified *`version`* of *`formula`* instead of the most recent.

`-f`, `--force`

: Overwrite the destination formula if it already exists.

### `formula` *`formula`* \[...\]

Display the path where *`formula`* is located.

### `formula-analytics`

Query Homebrew's analytics.

`--days-ago`

: Query from the specified days ago until the present. The default is 30 days.

`--install`

: Output the number of specifically requested installations or installation as
  dependencies of the formula. This is the default.

`--cask-install`

: Output the number of installations of casks.

`--install-on-request`

: Output the number of specifically requested installations of the formula.

`--build-error`

: Output the number of build errors for the formulae.

`--os-version`

: Output OS versions.

`--homebrew-devcmdrun-developer`

: Output devcmdrun/HOMEBREW\_DEVELOPER.

`--homebrew-os-arch-ci`

: Output OS/Architecture/CI.

`--homebrew-prefixes`

: Output Homebrew prefixes.

`--homebrew-versions`

: Output Homebrew versions.

`--brew-command-run`

: Output `brew` commands run.

`--brew-command-run-options`

: Output `brew` commands run with options.

`--brew-test-bot-test`

: Output `brew test-bot` steps run.

`--json`

: Output JSON. This is required: plain text support has been removed.

`--all-core-formulae-json`

: Output a different JSON format containing the JSON data for all
  Homebrew/homebrew-core formulae.

`--setup`

: Install the necessary gems, require them and exit without running a query.

### `generate-analytics-api`

Generates analytics API data files for formulae.brew.sh.

The generated files are written to the current directory.

### `generate-cask-api` \[`--dry-run`\]

Generate `homebrew/cask` API data files for <https://formulae.brew.sh>. The
generated files are written to the current directory.

`-n`, `--dry-run`

: Generate API data without writing it to files.

### `generate-formula-api` \[`--dry-run`\]

Generate `homebrew/core` API data files for <https://formulae.brew.sh>. The
generated files are written to the current directory.

`-n`, `--dry-run`

: Generate API data without writing it to files.

### `generate-man-completions`

Generate Homebrew's manpages and shell completions.

### `install-bundler-gems` \[`--groups=`\] \[`--add-groups=`\]

Install Homebrew's Bundler gems.

`--groups`

: Installs the specified comma-separated list of gem groups (default: last
  used). Replaces any previously installed groups.

`--add-groups`

: Installs the specified comma-separated list of gem groups, in addition to
  those already installed.

### `irb` \[`--examples`\] \[`--pry`\]

Enter the interactive Homebrew Ruby shell.

`--examples`

: Show several examples.

`--pry`

: Use Pry instead of IRB. Implied if `HOMEBREW_PRY` is set.

### `linkage` \[*`options`*\] \[*`installed_formula`* ...\]

Check the library links from the given *`formula`* kegs. If no *`formula`* are
provided, check all kegs. Raises an error if run on uninstalled formulae.

`--test`

: Show only missing libraries and exit with a non-zero status if any missing
  libraries are found.

`--strict`

: Exit with a non-zero status if any undeclared dependencies with linkage are
  found.

`--reverse`

: For every library that a keg references, print its dylib path followed by the
  binaries that link to it.

`--cached`

: Print the cached linkage values stored in `HOMEBREW_CACHE`, set by a previous
  `brew linkage` run.

### `livecheck`, `lc` \[*`options`*\] \[*`formula`*\|*`cask`* ...\]

Check for newer versions of formulae and/or casks from upstream. If no formula
or cask argument is passed, the list of formulae and casks to check is taken
from `HOMEBREW_LIVECHECK_WATCHLIST` or `~/.homebrew/livecheck_watchlist.txt`.

`--full-name`

: Print formulae and casks with fully-qualified names.

`--tap`

: Check formulae and casks within the given tap, specified as
  *`user`*`/`*`repo`*.

`--eval-all`

: Evaluate all available formulae and casks, whether installed or not, to check
  them.

`--installed`

: Check formulae and casks that are currently installed.

`--newer-only`

: Show the latest version only if it's newer than the formula/cask.

`--json`

: Output information in JSON format.

`-r`, `--resources`

: Also check resources for formulae.

`-q`, `--quiet`

: Suppress warnings, don't print a progress bar for JSON output.

`--formula`

: Only check formulae.

`--cask`

: Only check casks.

`--extract-plist`

: Enable checking multiple casks with ExtractPlist strategy.

`--autobump`

: Include packages that are autobumped by BrewTestBot. By default these are
  skipped.

### `pr-automerge` \[*`options`*\]

Find pull requests that can be automatically merged using `brew pr-publish`.

`--tap`

: Target tap repository (default: `homebrew/core`).

`--workflow`

: Workflow file to use with `brew pr-publish`.

`--with-label`

: Pull requests must have this label.

`--without-labels`

: Pull requests must not have these labels (default: `do not merge`, `new
  formula`, `automerge-skip`, `pre-release`, `CI-published-bottle-commits`).

`--without-approval`

: Pull requests do not require approval to be merged.

`--publish`

: Run `brew pr-publish` on matching pull requests.

`--autosquash`

: Instruct `brew pr-publish` to automatically reformat and reword commits in the
  pull request to the preferred format.

`--ignore-failures`

: Include pull requests that have failing status checks.

### `pr-publish` \[*`options`*\] *`pull_request`* \[...\]

Publish bottles for a pull request with GitHub Actions. Requires write access to
the repository.

`--autosquash`

: If supported on the target tap, automatically reformat and reword commits to
  our preferred format.

`--large-runner`

: Run the upload job on a large runner.

`--branch`

: Branch to use the workflow from (default: `master`).

`--message`

: Message to include when autosquashing revision bumps, deletions and rebuilds.

`--tap`

: Target tap repository (default: `homebrew/core`).

`--workflow`

: Target workflow filename (default: `publish-commit-bottles.yml`).

### `pr-pull` \[*`options`*\] *`pull_request`* \[...\]

Download and publish bottles and apply the bottle commit from a pull request
with artifacts generated by GitHub Actions. Requires write access to the
repository.

`--no-upload`

: Download the bottles but don't upload them.

`--no-commit`

: Do not generate a new commit before uploading.

`--no-cherry-pick`

: Do not cherry-pick commits from the pull request branch.

`-n`, `--dry-run`

: Print what would be done rather than doing it.

`--clean`

: Do not amend the commits from pull requests.

`--keep-old`

: If the formula specifies a rebuild version, attempt to preserve its value in
  the generated DSL.

`--autosquash`

: Automatically reformat and reword commits in the pull request to our preferred
  format.

`--branch-okay`

: Do not warn if pulling to a branch besides the repository default (useful for
  testing).

`--resolve`

: When a patch fails to apply, leave in progress and allow user to resolve,
  instead of aborting.

`--warn-on-upload-failure`

: Warn instead of raising an error if the bottle upload fails. Useful for
  repairing bottle uploads that previously failed.

`--retain-bottle-dir`

: Does not clean up the tmp directory for the bottle so it can be used later.

`--committer`

: Specify a committer name and email in `git`'s standard author format.

`--message`

: Message to include when autosquashing revision bumps, deletions and rebuilds.

`--artifact-pattern`

: Download artifacts with the specified pattern (default: `bottles{,_*}`).

`--tap`

: Target tap repository (default: `homebrew/core`).

`--root-url`

: Use the specified *`URL`* as the root of the bottle's URL instead of
  Homebrew's default.

`--root-url-using`

: Use the specified download strategy class for downloading the bottle's URL
  instead of Homebrew's default.

`--workflows`

: Retrieve artifacts from the specified workflow (default: `tests.yml`). Can be
  a comma-separated list to include multiple workflows.

`--ignore-missing-artifacts`

: Comma-separated list of workflows which can be ignored if they have not been
  run.

### `pr-upload` \[*`options`*\]

Apply the bottle commit and publish bottles to a host.

`--keep-old`

: If the formula specifies a rebuild version, attempt to preserve its value in
  the generated DSL. When using GitHub Packages, this also appends the manifest
  to the existing list.

`-n`, `--dry-run`

: Print what would be done rather than doing it.

`--no-commit`

: Do not generate a new commit before uploading.

`--warn-on-upload-failure`

: Warn instead of raising an error if the bottle upload fails. Useful for
  repairing bottle uploads that previously failed.

`--upload-only`

: Skip running `brew bottle` before uploading.

`--committer`

: Specify a committer name and email in `git`'s standard author format.

`--root-url`

: Use the specified *`URL`* as the root of the bottle's URL instead of
  Homebrew's default.

`--root-url-using`

: Use the specified download strategy class for downloading the bottle's URL
  instead of Homebrew's default.

### `prof` \[`--stackprof`\] \[`--vernier`\] *`command`* \[...\]

Run Homebrew with a Ruby profiler. For example, `brew prof readall`.

`--stackprof`

: Use `stackprof` instead of `ruby-prof` (the default).

`--vernier`

: Use `vernier` instead of `ruby-prof` (the default).

### `release` \[`--major`\] \[`--minor`\]

Create a new draft Homebrew/brew release with the appropriate version number and
release notes.

By default, `brew release` will bump the patch version number. Pass `--major` or
`--minor` to bump the major or minor version numbers, respectively. The command
will fail if the previous major or minor release was made less than one month
ago.

*Note:* Requires write access to the Homebrew/brew repository.

`--major`

: Create a major release.

`--minor`

: Create a minor release.

### `rubocop`

Installs, configures and runs Homebrew's `rubocop`.

### `ruby` \[*`options`*\] (`-e` *`text`*\|*`file`*)

Run a Ruby instance with Homebrew's libraries loaded. For example, `brew ruby -e
"puts :gcc.f.deps"` or `brew ruby script.rb`.

Run e.g. `brew ruby -- --version` to pass arbitrary arguments to `ruby`.

`-r`

: Load a library using `require`.

`-e`

: Execute the given text string as a script.

### `rubydoc` \[`--only-public`\] \[`--open`\]

Generate Homebrew's RubyDoc documentation.

`--only-public`

: Only generate public API documentation.

`--open`

: Open generated documentation in a browser.

### `sh` \[`--env=`\] \[`--cmd=`\] \[*`file`*\]

Enter an interactive shell for Homebrew's build environment. Use
years-battle-hardened build logic to help your `./configure && make && make
install` and even your `gem install` succeed. Especially handy if you run
Homebrew in an Xcode-only configuration since it adds tools like `make` to your
`PATH` which build systems would not find otherwise.

`--env`

: Use the standard `PATH` instead of superenv's when `std` is passed.

`-c`, `--cmd`

: Execute commands in a non-interactive shell.

### `style` \[*`options`*\] \[*`file`*\|*`tap`*\|*`formula`*\|*`cask`* ...\]

Check formulae or files for conformance to Homebrew style guidelines.

Lists of *`file`*, *`tap`* and *`formula`* may not be combined. If none are
provided, `style` will run style checks on the whole Homebrew library, including
core code and all formulae.

`--fix`

: Fix style violations automatically using RuboCop's auto-correct feature.

`--reset-cache`

: Reset the RuboCop cache.

`--formula`

: Treat all named arguments as formulae.

`--cask`

: Treat all named arguments as casks.

`--only-cops`

: Specify a comma-separated *`cops`* list to check for violations of only the
  listed RuboCop cops.

`--except-cops`

: Specify a comma-separated *`cops`* list to skip checking for violations of the
  listed RuboCop cops.

### `tap-new` \[*`options`*\] *`user`*`/`*`repo`*

Generate the template files for a new tap.

`--no-git`

: Don't initialize a Git repository for the tap.

`--pull-label`

: Label name for pull requests ready to be pulled (default: `pr-pull`).

`--branch`

: Initialize Git repository and setup GitHub Actions workflows with the
  specified branch name (default: `main`).

`--github-packages`

: Upload bottles to GitHub Packages.

### `test` \[*`options`*\] *`installed_formula`* \[...\]

Run the test method provided by an installed formula. There is no standard
output or return code, but generally it should notify the user if something is
wrong with the installed formula.

*Example:* `brew install jruby && brew test jruby`

`-f`, `--force`

: Test formulae even if they are unlinked.

`--HEAD`

: Test the HEAD version of a formula.

`--keep-tmp`

: Retain the temporary files created for the test.

`--retry`

: Retry if a testing fails.

### `tests` \[*`options`*\]

Run Homebrew's unit and integration tests.

`--coverage`

: Generate code coverage reports.

`--generic`

: Run only OS-agnostic tests.

`--online`

: Include tests that use the GitHub API and tests that use any of the taps for
  official external commands.

`--debug`

: Enable debugging using `ruby/debug`, or surface the standard `odebug` output.

`--changed`

: Only runs tests on files that were changed from the master branch.

`--fail-fast`

: Exit early on the first failing test.

`--only`

: Run only `<test_script>_spec.rb`. Appending `:<line_number>` will start at a
  specific line.

`--profile`

: Run the test suite serially to find the *`n`* slowest tests.

`--seed`

: Randomise tests with the specified *`value`* instead of a random seed.

### `typecheck`, `tc` \[*`options`*\] \[*`tap`* ...\]

Check for typechecking errors using Sorbet.

`--fix`

: Automatically fix type errors.

`-q`, `--quiet`

: Silence all non-critical errors.

`--update`

: Update RBI files.

`--update-all`

: Update all RBI files rather than just updated gems.

`--suggest-typed`

: Try upgrading `typed` sigils.

`--lsp`

: Start the Sorbet LSP server.

`--dir`

: Typecheck all files in a specific directory.

`--file`

: Typecheck a single file.

`--ignore`

: Ignores input files that contain the given string in their paths (relative to
  the input path passed to Sorbet).

### `unbottled` \[*`options`*\] \[*`formula`* ...\]

Show the unbottled dependents of formulae.

`--tag`

: Use the specified bottle tag (e.g. `big_sur`) instead of the current OS.

`--dependents`

: Skip getting analytics data and sort by number of dependents instead.

`--total`

: Print the number of unbottled and total formulae.

`--lost`

: Print the `homebrew/core` commits where bottles were lost in the last week.

`--eval-all`

: Evaluate all available formulae and casks, whether installed or not, to check
  them. Implied if `HOMEBREW_EVAL_ALL` is set.

### `unpack` \[*`options`*\] *`formula`* \[...\]

Unpack the source files for *`formula`* into subdirectories of the current
working directory.

`--destdir`

: Create subdirectories in the directory named by *`path`* instead.

`--patch`

: Patches for *`formula`* will be applied to the unpacked source.

`-g`, `--git`

: Initialise a Git repository in the unpacked source. This is useful for
  creating patches for the software.

`-f`, `--force`

: Overwrite the destination directory if it already exists.

### `update-license-data`

Update SPDX license data in the Homebrew repository.

### `update-maintainers`

Update the list of maintainers in the `Homebrew/brew` README.

### `update-python-resources` \[*`options`*\] *`formula`* \[...\]

Update versions for PyPI resource blocks in *`formula`*.

`-p`, `--print-only`

: Print the updated resource blocks instead of changing *`formula`*.

`-s`, `--silent`

: Suppress any output.

`--ignore-errors`

: Record all discovered resources, even those that can't be resolved
  successfully. This option is ignored for homebrew/core formulae.

`--ignore-non-pypi-packages`

: Don't fail if *`formula`* is not a PyPI package.

`--install-dependencies`

: Install missing dependencies required to update resources.

`--version`

: Use the specified *`version`* when finding resources for *`formula`*. If no
  version is specified, the current version for *`formula`* will be used.

`--package-name`

: Use the specified *`package-name`* when finding resources for *`formula`*. If
  no package name is specified, it will be inferred from the formula's stable
  URL.

`--extra-packages`

: Include these additional packages when finding resources.

`--exclude-packages`

: Exclude these packages when finding resources.

### `update-sponsors`

Update the list of GitHub Sponsors in the `Homebrew/brew` README.

### `update-test` \[*`options`*\]

Run a test of `brew update` with a new repository clone. If no options are
passed, use `origin/master` as the start commit.

`--to-tag`

: Set `HOMEBREW_UPDATE_TO_TAG` to test updating between tags.

`--keep-tmp`

: Retain the temporary directory containing the new repository clone.

`--commit`

: Use the specified *`commit`* as the start commit.

`--before`

: Use the commit at the specified *`date`* as the start commit.

### `vendor-gems` \[`--update=`\] \[`--no-commit`\]

Install and commit Homebrew's vendored gems.

`--update`

: Update the specified list of vendored gems to the latest version.

`--no-commit`

: Do not generate a new commit upon completion.

### `verify` \[*`options`*\] *`formula`* \[...\]

Verify the build provenance of bottles using GitHub's attestation tools. This is
done by first fetching the given bottles and then verifying their provenance.

Note that this command depends on the GitHub CLI. Run `brew install gh`.

`--os`

: Download for the given operating system.(Pass `all` to download for all
  operating systems.)

`--arch`

: Download for the given CPU architecture.(Pass `all` to download for all
  architectures.)

`--bottle-tag`

: Download a bottle for given tag.

`--deps`

: Also download dependencies for any listed *`formula`*.

`-f`, `--force`

: Remove a previously cached version and re-fetch.

`-j`, `--json`

: Return JSON for the attestation data for each bottle.

## GLOBAL CASK OPTIONS

These options are applicable to the `install`, `reinstall` and `upgrade`
subcommands with the `--cask` switch.

`--appdir`

: Target location for Applications (default: `/Applications`).

`--keyboard-layoutdir`

: Target location for Keyboard Layouts (default: `/Library/Keyboard Layouts`).

`--colorpickerdir`

: Target location for Color Pickers (default: `~/Library/ColorPickers`).

`--prefpanedir`

: Target location for Preference Panes (default: `~/Library/PreferencePanes`).

`--qlplugindir`

: Target location for Quick Look Plugins (default: `~/Library/QuickLook`).

`--mdimporterdir`

: Target location for Spotlight Plugins (default: `~/Library/Spotlight`).

`--dictionarydir`

: Target location for Dictionaries (default: `~/Library/Dictionaries`).

`--fontdir`

: Target location for Fonts (default: `~/Library/Fonts`).

`--servicedir`

: Target location for Services (default: `~/Library/Services`).

`--input-methoddir`

: Target location for Input Methods (default: `~/Library/Input Methods`).

`--internet-plugindir`

: Target location for Internet Plugins (default: `~/Library/Internet Plug-Ins`).

`--audio-unit-plugindir`

: Target location for Audio Unit Plugins (default:
  `~/Library/Audio/Plug-Ins/Components`).

`--vst-plugindir`

: Target location for VST Plugins (default: `~/Library/Audio/Plug-Ins/VST`).

`--vst3-plugindir`

: Target location for VST3 Plugins (default: `~/Library/Audio/Plug-Ins/VST3`).

`--screen-saverdir`

: Target location for Screen Savers (default: `~/Library/Screen Savers`).

`--language`

: Comma-separated list of language codes to prefer for cask installation. The
  first matching language is used, otherwise it reverts to the cask's default
  language. The default value is the language of your system.

## GLOBAL OPTIONS

These options are applicable across multiple subcommands.

`-d`, `--debug`

: Display any debugging information.

`-q`, `--quiet`

: Make some output more quiet.

`-v`, `--verbose`

: Make some output more verbose.

`-h`, `--help`

: Show this message.

## OFFICIAL EXTERNAL COMMANDS

### `bundle` \[*`subcommand`*\]

Bundler for non-Ruby dependencies from Homebrew, Homebrew Cask, Mac App Store,
Whalebrew and Visual Studio Code.

`brew bundle` \[`install`\]

: Install and upgrade (by default) all dependencies from the `Brewfile`.

You can specify the `Brewfile` location using `--file` or by setting the
`$HOMEBREW_BUNDLE_FILE` environment variable.

You can skip the installation of dependencies by adding space-separated values
to one or more of the following environment variables:
`$HOMEBREW_BUNDLE_BREW_SKIP`, `$HOMEBREW_BUNDLE_CASK_SKIP`,
`$HOMEBREW_BUNDLE_MAS_SKIP`, `$HOMEBREW_BUNDLE_WHALEBREW_SKIP`,
`$HOMEBREW_BUNDLE_TAP_SKIP`.

`brew bundle upgrade`

: Shorthand for `brew bundle install --upgrade`.

`brew bundle dump`

: Write all installed casks/formulae/images/taps into a `Brewfile` in the
  current directory or to a custom file specified with the `--file` option.

`brew bundle cleanup`

: Uninstall all dependencies not present in the `Brewfile`.

This workflow is useful for maintainers or testers who regularly install lots of
formulae.

Unless `--force` is passed, this returns a 1 exit code if anything would be
removed.

`brew bundle check`

: Check if all dependencies present in the `Brewfile` are installed.

This provides a successful exit code if everything is up-to-date, making it
useful for scripting.

`brew bundle list`

: List all dependencies present in the `Brewfile`.

By default, only Homebrew formula dependencies are listed.

`brew bundle edit`

: Edit the `Brewfile` in your editor.

`brew bundle exec` *`command`*

: Run an external command in an isolated build environment based on the
  `Brewfile` dependencies.

This sanitized build environment ignores unrequested dependencies, which makes
sure that things you didn't specify in your `Brewfile` won't get picked up by
commands like `bundle install`, `npm install`, etc. It will also add compiler
flags which will help with finding keg-only dependencies like `openssl`,
`icu4c`, etc.

`brew bundle sh`

: Run your shell in a `brew bundle exec` environment.

`brew bundle env`

: Print the environment variables that would be set in a `brew bundle exec`
  environment.

`--file`

: Read from or write to the `Brewfile` from this location. Use `--file=-` to
  pipe to stdin/stdout.

`--global`

: Read from or write to the `Brewfile` from `$HOMEBREW_BUNDLE_FILE_GLOBAL` (if
  set), `${XDG_CONFIG_HOME}/homebrew/Brewfile` (if `$XDG_CONFIG_HOME` is set),
  `~/.homebrew/Brewfile` or `~/.Brewfile` otherwise.

`-v`, `--verbose`

: `install` prints output from commands as they are run. `check` lists all
  missing dependencies.

`--no-upgrade`

: `install` does not run `brew upgrade` on outdated dependencies. `check` does
  not check for outdated dependencies. Note they may still be upgraded by `brew
  install` if needed. This is enabled by default if
  `$HOMEBREW_BUNDLE_NO_UPGRADE` is set.

`--upgrade`

: `install` runs `brew upgrade` on outdated dependencies, even if
  `$HOMEBREW_BUNDLE_NO_UPGRADE` is set.

`--install`

: Run `install` before continuing to other operations e.g. `exec`.

`-f`, `--force`

: `install` runs with `--force`/`--overwrite`. `dump` overwrites an existing
  `Brewfile`. `cleanup` actually performs its cleanup operations.

`--cleanup`

: `install` performs cleanup operation, same as running `cleanup --force`. This
  is enabled by default if `$HOMEBREW_BUNDLE_INSTALL_CLEANUP` is set and
  `--global` is passed.

`--all`

: `list` all dependencies.

`--formula`

: `list` or `dump` Homebrew formula dependencies.

`--cask`

: `list` or `dump` Homebrew cask dependencies.

`--tap`

: `list` or `dump` Homebrew tap dependencies.

`--mas`

: `list` or `dump` Mac App Store dependencies.

`--whalebrew`

: `list` or `dump` Whalebrew dependencies.

`--vscode`

: `list` or `dump` VSCode extensions.

`--no-vscode`

: `dump` without VSCode extensions. This is enabled by default if
  `$HOMEBREW_BUNDLE_DUMP_NO_VSCODE` is set.

`--describe`

: `dump` adds a description comment above each line, unless the dependency does
  not have a description. This is enabled by default if
  `$HOMEBREW_BUNDLE_DUMP_DESCRIBE` is set.

`--no-restart`

: `dump` does not add `restart_service` to formula lines.

`--zap`

: `cleanup` casks using the `zap` command instead of `uninstall`.

### `command-not-found-init`

Print instructions for setting up the command-not-found hook for your shell. If
the output is not to a tty, print the appropriate handler script for your shell.

### `services` \[*`subcommand`*\]

Manage background services with macOS' `launchctl`(1) daemon manager or Linux's
`systemctl`(1) service manager.

If `sudo` is passed, operate on `/Library/LaunchDaemons` or
`/usr/lib/systemd/system` (started at boot). Otherwise, operate on
`~/Library/LaunchAgents` or `~/.config/systemd/user` (started at login).

\[`sudo`\] `brew services` \[`list`\] (`--json`) (`--debug`)

: List information about all managed services for the current user (or root).
  Provides more output from Homebrew and `launchctl`(1) or `systemctl`(1) if run
  with `--debug`.

\[`sudo`\] `brew services info` (*`formula`*\|`--all`\|`--json`)

: List all managed services for the current user (or root).

\[`sudo`\] `brew services run` (*`formula`*\|`--all`)

: Run the service *`formula`* without registering to launch at login (or boot).

\[`sudo`\] `brew services start` (*`formula`*\|`--all`\|`--file=`)

: Start the service *`formula`* immediately and register it to launch at login
  (or boot).

\[`sudo`\] `brew services stop` (*`formula`*\|`--all`)

: Stop the service *`formula`* immediately and unregister it from launching at
  login (or boot).

\[`sudo`\] `brew services kill` (*`formula`*\|`--all`)

: Stop the service *`formula`* immediately but keep it registered to launch at
  login (or boot).

\[`sudo`\] `brew services restart` (*`formula`*\|`--all`)

: Stop (if necessary) and start the service *`formula`* immediately and register
  it to launch at login (or boot).

\[`sudo`\] `brew services cleanup`

: Remove all unused services.

`--file`

: Use the service file from this location to `start` the service.

`--sudo-service-user`

: When run as root on macOS, run the service(s) as this user.

`--max-wait`

: Wait at most this many seconds for `stop` to finish stopping a service. Omit
  this flag or set this to zero (0) seconds to wait indefinitely.

`--all`

: Run *`subcommand`* on all services.

`--json`

: Output as JSON.

`--no-wait`

: Don't wait for `stop` to finish stopping the service.

### `test-bot` \[*`options`*\] \[*`formula`*\]

Tests the full lifecycle of a Homebrew change to a tap (Git repository). For
example, for a GitHub Actions pull request that changes a formula `brew
test-bot` will ensure the system is cleaned and set up to test the formula,
install the formula, run various tests and checks on it, bottle (package) the
binaries and test formulae that depend on it to ensure they aren't broken by
these changes.

Only supports GitHub Actions as a CI provider. This is because Homebrew uses
GitHub Actions and it's freely available for public and private use with macOS
and Linux workers.

`--dry-run`

: Print what would be done rather than doing it.

`--cleanup`

: Clean all state from the Homebrew directory. Use with care!

`--skip-setup`

: Don't check if the local system is set up correctly.

`--build-from-source`

: Build from source rather than building bottles.

`--build-dependents-from-source`

: Build dependents from source rather than testing bottles.

`--junit`

: generate a JUnit XML test results file.

`--keep-old`

: Run `brew bottle --keep-old` to build new bottles for a single platform.

`--skip-relocation`

: Run `brew bottle --skip-relocation` to build new bottles that don't require
  relocation.

`--only-json-tab`

: Run `brew bottle --only-json-tab` to build new bottles that do not contain a
  tab.

`--local`

: Ask Homebrew to write verbose logs under `./logs/` and set `$HOME` to
  `./home/`

`--tap`

: Use the Git repository of the given tap. Defaults to the core tap for syntax
  checking.

`--fail-fast`

: Immediately exit on a failing step.

`-v`, `--verbose`

: Print test step output in real time. Has the side effect of passing output as
  raw bytes instead of re-encoding in UTF-8.

`--test-default-formula`

: Use a default testing formula when not building a tap and no other formulae
  are specified.

`--root-url`

: Use the specified *`URL`* as the root of the bottle's URL instead of
  Homebrew's default.

`--git-name`

: Set the Git author/committer names to the given name.

`--git-email`

: Set the Git author/committer email to the given email.

`--publish`

: Publish the uploaded bottles.

`--skip-online-checks`

: Don't pass `--online` to `brew audit` and skip `brew livecheck`.

`--skip-new`

: Don't pass `--new` to `brew audit` for new formulae.

`--skip-new-strict`

: Don't pass `--strict` to `brew audit` for new formulae.

`--skip-dependents`

: Don't test any dependents.

`--skip-livecheck`

: Don't test livecheck.

`--skip-recursive-dependents`

: Only test the direct dependents.

`--skip-checksum-only-audit`

: Don't audit checksum-only changes.

`--skip-stable-version-audit`

: Don't audit the stable version.

`--skip-revision-audit`

: Don't audit the revision.

`--only-cleanup-before`

: Only run the pre-cleanup step. Needs `--cleanup`.

`--only-setup`

: Only run the local system setup check step.

`--only-tap-syntax`

: Only run the tap syntax check step.

`--stable`

: Only run the tap syntax checks needed on stable brew.

`--only-formulae`

: Only run the formulae steps.

`--only-formulae-detect`

: Only run the formulae detection steps.

`--only-formulae-dependents`

: Only run the formulae dependents steps.

`--only-bottles-fetch`

: Only run the bottles fetch steps. This optional post-upload test checks that
  all the bottles were uploaded correctly. It is not run unless requested and
  only needs to be run on a single machine. The bottle commit to be tested must
  be on the tested branch.

`--only-cleanup-after`

: Only run the post-cleanup step. Needs `--cleanup`.

`--testing-formulae`

: Use these testing formulae rather than running the formulae detection steps.

`--added-formulae`

: Use these added formulae rather than running the formulae detection steps.

`--deleted-formulae`

: Use these deleted formulae rather than running the formulae detection steps.

`--skipped-or-failed-formulae`

: Use these skipped or failed formulae from formulae steps for a formulae
  dependents step.

`--tested-formulae`

: Use these tested formulae from formulae steps for a formulae dependents step.

### `which-formula` \[`--explain`\] *`command`* \[...\]

Show which formula(e) provides the given command.

`--explain`

: Output explanation of how to get *`command`* by installing one of the
  providing formulae.

### `which-update` \[*`options`*\] \[*`database`*\]

Database update for `brew which-formula`.

`--stats`

: Print statistics about the database contents (number of commands and formulae,
  list of missing formulae).

`--commit`

: Commit the changes using `git`.

`--update-existing`

: Update database entries with outdated formula versions.

`--install-missing`

: Install and update formulae that are missing from the database and don't have
  bottles.

`--eval-all`

: Evaluate all installed taps, rather than just the core tap.

`--max-downloads`

: Specify a maximum number of formulae to download and update.

## CUSTOM EXTERNAL COMMANDS

Homebrew, like `git`(1), supports external commands. These are executable
scripts that reside somewhere in the `PATH`, named `brew-`*`cmdname`* or
`brew-`*`cmdname`*`.rb`, which can be invoked like `brew` *`cmdname`*. This
allows you to create your own commands without modifying Homebrew's internals.

Instructions for creating your own commands can be found in the docs:
<https://docs.brew.sh/External-Commands>

## SPECIFYING FORMULAE

Many Homebrew commands accept one or more *`formula`* arguments. These arguments
can take several different forms:

* The name of a formula: e.g. `git`, `node`, `wget`.

* The fully-qualified name of a tapped formula: Sometimes a formula from a
  tapped repository may conflict with one in `homebrew/core`. You can still
  access these formulae by using a special syntax, e.g. `homebrew/dupes/vim` or
  `homebrew/versions/node4`.

* An arbitrary file: Homebrew can install formulae from a local path. It can
  point to either a formula file or a bottle. Prefix relative paths with `./` to
  prevent them from being interpreted as a formula or tap name.

## SPECIFYING CASKS

Many Homebrew Cask commands accept one or more *`cask`* arguments. These can be
specified the same way as the *`formula`* arguments described in `SPECIFYING
FORMULAE` above.

## ENVIRONMENT

Note that environment variables must have a value set to be detected. For
example, run `export HOMEBREW_NO_INSECURE_REDIRECT=1` rather than just `export
HOMEBREW_NO_INSECURE_REDIRECT`.

`HOMEBREW_*` environment variables can also be set in Homebrew's environment
files:

* `/etc/homebrew/brew.env` (system-wide)

* `${HOMEBREW_PREFIX}/etc/homebrew/brew.env` (prefix-specific)

* `$XDG_CONFIG_HOME/homebrew/brew.env` if `$XDG_CONFIG_HOME` is set or
  `~/.homebrew/brew.env` otherwise (user-specific)

User-specific environment files take precedence over prefix-specific files and
prefix-specific files take precedence over system-wide files (unless
`HOMEBREW_SYSTEM_ENV_TAKES_PRIORITY` is set, see below).

Note that these files do not support shell variable expansion e.g. `$HOME` or
command execution e.g. `$(cat file)`.

`HOMEBREW_ALLOWED_TAPS`

: A space-separated list of taps. Homebrew will refuse to install a formula
  unless it and all of its dependencies are in an official tap or in a tap on
  this list.

`HOMEBREW_API_AUTO_UPDATE_SECS`

: Check Homebrew's API for new formulae or cask data every
  `$HOMEBREW_API_AUTO_UPDATE_SECS` seconds. Alternatively, disable API
  auto-update checks entirely with `$HOMEBREW_NO_AUTO_UPDATE`.
  
  *Default:* `450`.

`HOMEBREW_API_DOMAIN`

: Use this URL as the download mirror for Homebrew JSON API. If metadata files
  at that URL are temporarily unavailable, the default API domain will be used
  as a fallback mirror.
  
  *Default:* `https://formulae.brew.sh/api`.

`HOMEBREW_ARCH`

: Linux only: Pass this value to a type name representing the compiler's
  `-march` option.
  
  *Default:* `native`.

`HOMEBREW_ARTIFACT_DOMAIN`

: Prefix all download URLs, including those for bottles, with this value. For
  example, `export HOMEBREW_ARTIFACT_DOMAIN=http://localhost:8080` will cause a
  formula with the URL `https://example.com/foo.tar.gz` to instead download from
  `http://localhost:8080/https://example.com/foo.tar.gz`. Bottle URLs however,
  have their domain replaced with this prefix. This results in e.g.
  `https://ghcr.io/v2/homebrew/core/gettext/manifests/0.21` to instead be
  downloaded from
  `http://localhost:8080/v2/homebrew/core/gettext/manifests/0.21`

`HOMEBREW_ARTIFACT_DOMAIN_NO_FALLBACK`

: When `$HOMEBREW_ARTIFACT_DOMAIN` and `$HOMEBREW_ARTIFACT_DOMAIN_NO_FALLBACK`
  are both set, if the request to `$HOMEBREW_ARTIFACT_DOMAIN` fails then
  Homebrew will error rather than trying any other/default URLs.

`HOMEBREW_AUTO_UPDATE_SECS`

: Run `brew update` once every `$HOMEBREW_AUTO_UPDATE_SECS` seconds before some
  commands, e.g. `brew install`, `brew upgrade` and `brew tap`. Alternatively,
  disable auto-update entirely with `$HOMEBREW_NO_AUTO_UPDATE`.
  
  *Default:* `86400` (24 hours), `3600` (1 hour) if a developer command has been
  run or `300` (5 minutes) if `$HOMEBREW_NO_INSTALL_FROM_API` is set.

`HOMEBREW_BAT`

: If set, use `bat` for the `brew cat` command.

`HOMEBREW_BAT_CONFIG_PATH`

: Use this as the `bat` configuration file.
  
  *Default:* `$BAT_CONFIG_PATH`.

`HOMEBREW_BAT_THEME`

: Use this as the `bat` theme for syntax highlighting.
  
  *Default:* `$BAT_THEME`.

`HOMEBREW_BOOTSNAP`

: If set, use Bootsnap to speed up repeated `brew` calls. A no-op on Linux when
  not using Homebrew's vendored, relocatable Ruby.

`HOMEBREW_BOTTLE_DOMAIN`

: Use this URL as the download mirror for bottles. If bottles at that URL are
  temporarily unavailable, the default bottle domain will be used as a fallback
  mirror. For example, `export HOMEBREW_BOTTLE_DOMAIN=http://localhost:8080`
  will cause all bottles to download from the prefix `http://localhost:8080/`.
  If bottles are not available at `$HOMEBREW_BOTTLE_DOMAIN` they will be
  downloaded from the default bottle domain.
  
  *Default:* `https://ghcr.io/v2/homebrew/core`.

`HOMEBREW_BREW_GIT_REMOTE`

: Use this URL as the Homebrew/brew `git`(1) remote.
  
  *Default:* `https://github.com/Homebrew/brew`.

`HOMEBREW_BREW_WRAPPER`

: If set, use wrapper to call `brew` rather than auto-detecting it.

`HOMEBREW_BROWSER`

: Use this as the browser when opening project homepages.
  
  *Default:* `$BROWSER` or the OS's default browser.

`HOMEBREW_BUNDLE_USER_CACHE`

: If set, use this directory as the `bundle`(1) user cache.

`HOMEBREW_CACHE`

: Use this directory as the download cache.
  
  *Default:* macOS: `~/Library/Caches/Homebrew`, Linux:
  `$XDG_CACHE_HOME/Homebrew` or `~/.cache/Homebrew`.

`HOMEBREW_CASK_OPTS`

: Append these options to all `cask` commands. All `--*dir` options,
  `--language`, `--require-sha`, `--no-quarantine` and `--no-binaries` are
  supported. For example, you might add something like the following to your
  `~/.profile`, `~/.bash_profile`, or `~/.zshenv`:
  
  `export HOMEBREW_CASK_OPTS="--appdir=${HOME}/Applications
  --fontdir=/Library/Fonts"`

`HOMEBREW_CLEANUP_MAX_AGE_DAYS`

: Cleanup all cached files older than this many days.
  
  *Default:* `120`.

`HOMEBREW_CLEANUP_PERIODIC_FULL_DAYS`

: If set, `brew install`, `brew upgrade` and `brew reinstall` will cleanup all
  formulae when this number of days has passed.
  
  *Default:* `30`.

`HOMEBREW_COLOR`

: If set, force colour output on non-TTY outputs.

`HOMEBREW_CORE_GIT_REMOTE`

: Use this URL as the Homebrew/homebrew-core `git`(1) remote.
  
  *Default:* `https://github.com/Homebrew/homebrew-core`.

`HOMEBREW_CURLRC`

: If set to an absolute path (i.e. beginning with `/`), pass it with `--config`
  when invoking `curl`(1). If set but *not* a valid path, do not pass
  `--disable`, which disables the use of `.curlrc`.

`HOMEBREW_CURL_PATH`

: Linux only: Set this value to a new enough `curl` executable for Homebrew to
  use.
  
  *Default:* `curl`.

`HOMEBREW_CURL_RETRIES`

: Pass the given retry count to `--retry` when invoking `curl`(1).
  
  *Default:* `3`.

`HOMEBREW_CURL_VERBOSE`

: If set, pass `--verbose` when invoking `curl`(1).

`HOMEBREW_DEBUG`

: If set, always assume `--debug` when running commands.

`HOMEBREW_DEVELOPER`

: If set, tweak behaviour to be more relevant for Homebrew developers (active or
  budding) by e.g. turning warnings into errors.

`HOMEBREW_DISABLE_DEBREW`

: If set, the interactive formula debugger available via `--debug` will be
  disabled.

`HOMEBREW_DISABLE_LOAD_FORMULA`

: If set, refuse to load formulae. This is useful when formulae are not trusted
  (such as in pull requests).

`HOMEBREW_DISPLAY`

: Use this X11 display when opening a page in a browser, for example with `brew
  home`. Primarily useful on Linux.
  
  *Default:* `$DISPLAY`.

`HOMEBREW_DISPLAY_INSTALL_TIMES`

: If set, print install times for each formula at the end of the run.

`HOMEBREW_DOCKER_REGISTRY_BASIC_AUTH_TOKEN`

: Use this base64 encoded username and password for authenticating with a Docker
  registry proxying GitHub Packages. If `$HOMEBREW_DOCKER_REGISTRY_TOKEN` is
  set, it will be used instead.

`HOMEBREW_DOCKER_REGISTRY_TOKEN`

: Use this bearer token for authenticating with a Docker registry proxying
  GitHub Packages. Preferred over `$HOMEBREW_DOCKER_REGISTRY_BASIC_AUTH_TOKEN`.

`HOMEBREW_EDITOR`

: Use this editor when editing a single formula, or several formulae in the same
  directory.
  
  *Note:* `brew edit` will open all of Homebrew as discontinuous files and
  directories. Visual Studio Code can handle this correctly in project mode, but
  many editors will do strange things in this case.
  
  *Default:* `$EDITOR` or `$VISUAL`.

`HOMEBREW_EVAL_ALL`

: If set, `brew` commands evaluate all formulae and casks, executing their
  arbitrary code, by default without requiring `--eval-all`. Required to cache
  formula and cask descriptions.

`HOMEBREW_FAIL_LOG_LINES`

: Output this many lines of output on formula `system` failures.
  
  *Default:* `15`.

`HOMEBREW_FORBIDDEN_CASKS`

: A space-separated list of casks. Homebrew will refuse to install a cask if it
  or any of its dependencies is on this list.

`HOMEBREW_FORBIDDEN_FORMULAE`

: A space-separated list of formulae. Homebrew will refuse to install a formula
  or cask if it or any of its dependencies is on this list.

`HOMEBREW_FORBIDDEN_LICENSES`

: A space-separated list of SPDX license identifiers. Homebrew will refuse to
  install a formula if it or any of its dependencies has a license on this list.

`HOMEBREW_FORBIDDEN_OWNER`

: The person who has set any `$HOMEBREW_FORBIDDEN_*` variables.
  
  *Default:* `you`.

`HOMEBREW_FORBIDDEN_OWNER_CONTACT`

: How to contact the `$HOMEBREW_FORBIDDEN_OWNER`, if set and necessary.

`HOMEBREW_FORBIDDEN_TAPS`

: A space-separated list of taps. Homebrew will refuse to install a formula if
  it or any of its dependencies is in a tap on this list.

`HOMEBREW_FORBID_PACKAGES_FROM_PATHS`

: If set, Homebrew will refuse to read formulae or casks provided from file
  paths, e.g. `brew install ./package.rb`.

`HOMEBREW_FORCE_API_AUTO_UPDATE`

: If set, update the Homebrew API formula or cask data even if
  `$HOMEBREW_NO_AUTO_UPDATE` is set.

`HOMEBREW_FORCE_BREWED_CA_CERTIFICATES`

: If set, always use a Homebrew-installed `ca-certificates` rather than the
  system version. Automatically set if the system version is too old.

`HOMEBREW_FORCE_BREWED_CURL`

: If set, always use a Homebrew-installed `curl`(1) rather than the system
  version. Automatically set if the system version of `curl` is too old.

`HOMEBREW_FORCE_BREWED_GIT`

: If set, always use a Homebrew-installed `git`(1) rather than the system
  version. Automatically set if the system version of `git` is too old.

`HOMEBREW_FORCE_BREW_WRAPPER`

: If set, require `$HOMEBREW_BREW_WRAPPER` to be set to the same value as
  `$HOMEBREW_FORCE_BREW_WRAPPER` for non-trivial `brew` commands.

`HOMEBREW_FORCE_VENDOR_RUBY`

: If set, always use Homebrew's vendored, relocatable Ruby version even if the
  system version of Ruby is new enough.

`HOMEBREW_FORMULA_BUILD_NETWORK`

: If set, controls network access to the sandbox for formulae builds. Overrides
  any controls set through DSL usage inside formulae. Must be `allow` or `deny`.
  If no value is set through this environment variable or DSL usage, the default
  behavior is `allow`.

`HOMEBREW_FORMULA_POSTINSTALL_NETWORK`

: If set, controls network access to the sandbox for formulae postinstall.
  Overrides any controls set through DSL usage inside formulae. Must be `allow`
  or `deny`. If no value is set through this environment variable or DSL usage,
  the default behavior is `allow`.

`HOMEBREW_FORMULA_TEST_NETWORK`

: If set, controls network access to the sandbox for formulae test. Overrides
  any controls set through DSL usage inside formulae. Must be `allow` or `deny`.
  If no value is set through this environment variable or DSL usage, the default
  behavior is `allow`.

`HOMEBREW_GITHUB_API_TOKEN`

: Use this personal access token for the GitHub API, for features such as `brew
  search`. You can create one at <https://github.com/settings/tokens>. If set,
  GitHub will allow you a greater number of API requests. For more information,
  see: <https://docs.github.com/en/rest/overview/rate-limits-for-the-rest-api>
  
  *Note:* Homebrew doesn't require permissions for any of the scopes, but some
  developer commands may require additional permissions.

`HOMEBREW_GITHUB_PACKAGES_TOKEN`

: Use this GitHub personal access token when accessing the GitHub Packages
  Registry (where bottles may be stored).

`HOMEBREW_GITHUB_PACKAGES_USER`

: Use this username when accessing the GitHub Packages Registry (where bottles
  may be stored).

`HOMEBREW_GIT_COMMITTER_EMAIL`

: Set the Git committer email to this value.

`HOMEBREW_GIT_COMMITTER_NAME`

: Set the Git committer name to this value.

`HOMEBREW_GIT_EMAIL`

: Set the Git author name and, if `$HOMEBREW_GIT_COMMITTER_EMAIL` is unset,
  committer email to this value.

`HOMEBREW_GIT_NAME`

: Set the Git author name and, if `$HOMEBREW_GIT_COMMITTER_NAME` is unset,
  committer name to this value.

`HOMEBREW_GIT_PATH`

: Linux only: Set this value to a new enough `git` executable for Homebrew to
  use.
  
  *Default:* `git`.

`HOMEBREW_INSTALL_BADGE`

: Print this text before the installation summary of each successful build.
  
  *Default:* The "Beer Mug" emoji.

`HOMEBREW_LIVECHECK_AUTOBUMP`

: If set, `brew livecheck` will include data for packages that are autobumped by
  BrewTestBot.

`HOMEBREW_LIVECHECK_WATCHLIST`

: Consult this file for the list of formulae to check by default when no formula
  argument is passed to `brew livecheck`.
  
  *Default:* `${XDG_CONFIG_HOME}/homebrew/livecheck_watchlist.txt` if
  `$XDG_CONFIG_HOME` is set or `~/.homebrew/livecheck_watchlist.txt` otherwise.

`HOMEBREW_LOCK_CONTEXT`

: If set, Homebrew will add this output as additional context for locking
  errors. This is useful when running `brew` in the background.

`HOMEBREW_LOGS`

: Use this directory to store log files.
  
  *Default:* macOS: `~/Library/Logs/Homebrew`, Linux:
  `${XDG_CACHE_HOME}/Homebrew/Logs` or `~/.cache/Homebrew/Logs`.

`HOMEBREW_MAKE_JOBS`

: Use this value as the number of parallel jobs to run when building with
  `make`(1).
  
  *Default:* The number of available CPU cores.

`HOMEBREW_NO_ANALYTICS`

: If set, do not send analytics. Google Analytics were destroyed. For more
  information, see: <https://docs.brew.sh/Analytics>

`HOMEBREW_NO_AUTOREMOVE`

: If set, calls to `brew cleanup` and `brew uninstall` will not automatically
  remove unused formula dependents.

`HOMEBREW_NO_AUTO_UPDATE`

: If set, do not automatically update before running some commands, e.g. `brew
  install`, `brew upgrade` and `brew tap`. Preferably, run this less often by
  setting `$HOMEBREW_AUTO_UPDATE_SECS` to a value higher than the default. Note
  that setting this and e.g. tapping new taps may result in a broken
  configuration. Please ensure you always run `brew update` before reporting any
  issues.

`HOMEBREW_NO_BOOTSNAP`

: If set, do not use Bootsnap to speed up repeated `brew` calls.

`HOMEBREW_NO_CLEANUP_FORMULAE`

: A comma-separated list of formulae. Homebrew will refuse to clean up or
  autoremove a formula if it appears on this list.

`HOMEBREW_NO_COLOR`

: If set, do not print text with colour added.
  
  *Default:* `$NO_COLOR`.

`HOMEBREW_NO_EMOJI`

: If set, do not print `$HOMEBREW_INSTALL_BADGE` on a successful build.

`HOMEBREW_NO_ENV_HINTS`

: If set, do not print any hints about changing Homebrew's behaviour with
  environment variables.

`HOMEBREW_NO_FORCE_BREW_WRAPPER`

: If set, disables `$HOMEBREW_FORCE_BREW_WRAPPER` behaviour, even if set.

`HOMEBREW_NO_GITHUB_API`

: If set, do not use the GitHub API, e.g. for searches or fetching relevant
  issues after a failed install.

`HOMEBREW_NO_INSECURE_REDIRECT`

: If set, forbid redirects from secure HTTPS to insecure HTTP.
  
  *Note:* while ensuring your downloads are fully secure, this is likely to
  cause from-source SourceForge, some GNU & GNOME-hosted formulae to fail to
  download.

`HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK`

: If set, do not check for broken linkage of dependents or outdated dependents
  after installing, upgrading or reinstalling formulae. This will result in
  fewer dependents (and their dependencies) being upgraded or reinstalled but
  may result in more breakage from running `brew install` *`formula`* or `brew
  upgrade` *`formula`*.

`HOMEBREW_NO_INSTALL_CLEANUP`

: If set, `brew install`, `brew upgrade` and `brew reinstall` will never
  automatically cleanup installed/upgraded/reinstalled formulae or all formulae
  every `$HOMEBREW_CLEANUP_PERIODIC_FULL_DAYS` days. Alternatively,
  `$HOMEBREW_NO_CLEANUP_FORMULAE` allows specifying specific formulae to not
  clean up.

`HOMEBREW_NO_INSTALL_FROM_API`

: If set, do not install formulae and casks in homebrew/core and homebrew/cask
  taps using Homebrew's API and instead use (large, slow) local checkouts of
  these repositories.

`HOMEBREW_NO_INSTALL_UPGRADE`

: If set, `brew install` *`formula|cask`* will not upgrade *`formula|cask`* if
  it is installed but outdated.

`HOMEBREW_NO_UPDATE_REPORT_NEW`

: If set, `brew update` will not show the list of newly added formulae/casks.

`HOMEBREW_NO_VERIFY_ATTESTATIONS`

: If set, Homebrew will not verify cryptographic attestations of build
  provenance for bottles from homebrew-core.

`HOMEBREW_PIP_INDEX_URL`

: If set, `brew install` *`formula`* will use this URL to download PyPI package
  resources.
  
  *Default:* `https://pypi.org/simple`.

`HOMEBREW_PRY`

: If set, use Pry for the `brew irb` command.

`HOMEBREW_SIMULATE_MACOS_ON_LINUX`

: If set, running Homebrew on Linux will simulate certain macOS code paths. This
  is useful when auditing macOS formulae while on Linux.

`HOMEBREW_SKIP_OR_LATER_BOTTLES`

: If set along with `$HOMEBREW_DEVELOPER`, do not use bottles from older
  versions of macOS. This is useful in development on new macOS versions.

`HOMEBREW_SORBET_RUNTIME`

: If set, enable runtime typechecking using Sorbet. Set by default for
  `$HOMEBREW_DEVELOPER` or when running some developer commands.

`HOMEBREW_SSH_CONFIG_PATH`

: If set, Homebrew will use the given config file instead of `~/.ssh/config`
  when fetching Git repositories over SSH.
  
  *Default:* `~/.ssh/config`

`HOMEBREW_SUDO_THROUGH_SUDO_USER`

: If set, Homebrew will use the `SUDO_USER` environment variable to define the
  user to `sudo`(8) through when running `sudo`(8).

`HOMEBREW_SVN`

: Use this as the `svn`(1) binary.
  
  *Default:* A Homebrew-built Subversion (if installed), or the system-provided
  binary.

`HOMEBREW_SYSTEM_ENV_TAKES_PRIORITY`

: If set in Homebrew's system-wide environment file (`/etc/homebrew/brew.env`),
  the system-wide environment file will be loaded last to override any prefix or
  user settings.

`HOMEBREW_TEMP`

: Use this path as the temporary directory for building packages. Changing this
  may be needed if your system temporary directory and Homebrew prefix are on
  different volumes, as macOS has trouble moving symlinks across volumes when
  the target does not yet exist. This issue typically occurs when using
  FileVault or custom SSD configurations.
  
  *Default:* macOS: `/private/tmp`, Linux: `/tmp`.

`HOMEBREW_UPDATE_TO_TAG`

: If set, always use the latest stable tag (even if developer commands have been
  run).

`HOMEBREW_UPGRADE_GREEDY`

: If set, pass `--greedy` to all cask upgrade commands.

`HOMEBREW_UPGRADE_GREEDY_CASKS`

: A space-separated list of casks. Homebrew will act as if `--greedy` was passed
  when upgrading any cask on this list.

`HOMEBREW_VERBOSE`

: If set, always assume `--verbose` when running commands.

`HOMEBREW_VERBOSE_USING_DOTS`

: If set, verbose output will print a `.` no more than once a minute. This can
  be useful to avoid long-running Homebrew commands being killed due to no
  output.

`HOMEBREW_VERIFY_ATTESTATIONS`

: If set, Homebrew will use the `gh` tool to verify cryptographic attestations
  of build provenance for bottles from homebrew-core.

`SUDO_ASKPASS`

: If set, pass the `-A` option when calling `sudo`(8).

`all_proxy`

: Use this SOCKS5 proxy for `curl`(1), `git`(1) and `svn`(1) when downloading
  through Homebrew.

`ftp_proxy`

: Use this FTP proxy for `curl`(1), `git`(1) and `svn`(1) when downloading
  through Homebrew.

`http_proxy`

: Use this HTTP proxy for `curl`(1), `git`(1) and `svn`(1) when downloading
  through Homebrew.

`https_proxy`

: Use this HTTPS proxy for `curl`(1), `git`(1) and `svn`(1) when downloading
  through Homebrew.

`no_proxy`

: A comma-separated list of hostnames and domain names excluded from proxying by
  `curl`(1), `git`(1) and `svn`(1) when downloading through Homebrew.

## USING HOMEBREW BEHIND A PROXY

Set the `http_proxy`, `https_proxy`, `all_proxy`, `ftp_proxy` and/or `no_proxy`
environment variables documented above.

For example, to use an unauthenticated HTTP or SOCKS5 proxy:

    export http_proxy=http://$HOST:$PORT
    
    export all_proxy=socks5://$HOST:$PORT

And for an authenticated HTTP proxy:

    export http_proxy=http://$USER:$PASSWORD@$HOST:$PORT

## SEE ALSO

Homebrew Documentation: <https://docs.brew.sh>

Homebrew API: <https://rubydoc.brew.sh>

`git`(1), `git-log`(1)

## AUTHORS

Homebrew's Project Leader is Mike McQuaid.

Homebrew's Project Leadership Committee is Colin Dean, Michka Popoff, Mike
McQuaid, Patrick Linnane and Vanessa Gennarelli.

Homebrew's Technical Steering Committee is Bo Anderson, FX Coudert, Mike McQuaid
and Rylan Polster.

Homebrew's maintainers are Alexander Bayandin, Bevan Kay, Bo Anderson, Branch
Vincent, Caleb Xu, Carlo Cabrera, Daeho Ro, Douglas Eichelberger, Dustin
Rodrigues, Eric Knibbe, FX Coudert, Issy Long, Justin Krehel, Klaus Hipp, Markus
Reiter, Michael Cho, Michka Popoff, Mike McQuaid, Nanda H Krishna, Patrick
Linnane, Rui Chen, Ruoyu Zhong, Rylan Polster, Sam Ford, Sean Molenaar, Štefan
Baebler, Thierry Moisan, Timothy Sutton and William Woodruff.

Former maintainers with significant contributions include Miccal Matthews, Misty
De Méo, Shaun Jackman, Vítor Galvão, Claudia Pellegrino, Seeker, Jan Viljanen,
JCount, commitay, Dominyk Tiller, Tim Smith, Baptiste Fontaine, Xu Cheng, Martin
Afanasjew, Brett Koonce, Charlie Sharpsteen, Jack Nagel, Adam Vandenberg, Andrew
Janke, Alex Dunn, neutric, Tomasz Pajor, Uladzislau Shablinski, Alyssa Ross,
ilovezfs, Chongyu Zhu and Homebrew's creator: Max Howell.

## BUGS

See our issues on GitHub:

**Homebrew/brew**

: <https://github.com/Homebrew/brew/issues>

**Homebrew/homebrew-core**

: <https://github.com/Homebrew/homebrew-core/issues>

**Homebrew/homebrew-cask**

: <https://github.com/Homebrew/homebrew-cask/issues>

