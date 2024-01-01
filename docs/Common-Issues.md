# Common Issues

This is a list of commonly encountered problems, known issues, and their solutions.

* Table of Contents
{:toc}

## Running `brew`

### `brew` complains about absence of "Command Line Tools"

You need to have the Xcode Command Line Utilities installed (and updated): run `xcode-select --install` in the terminal.

### Ruby: `bad interpreter: /usr/bin/ruby^M: no such file or directory`

You cloned with `git`, and your Git configuration is set to use Windows line endings. See this page on [configuring Git to handle line endings](https://docs.github.com/en/get-started/getting-started-with-git/configuring-git-to-handle-line-endings).

### Ruby: `bad interpreter: /usr/bin/ruby`

You don't have a `/usr/bin/ruby` or it is not executable. It's not recommended to let this persist; you'd be surprised how many `.app`s, tools and scripts expect your macOS-provided files and directories to be *unmodified* since macOS was installed.

### `brew update` complains about untracked working tree files

After running `brew update`, you receive a Git error warning about untracked files or local changes that would be overwritten by a checkout or merge, followed by a list of files inside your Homebrew installation.

This is caused by an old bug in in the `update` code that has long since been fixed. However, the nature of the bug requires that you do the following:

```sh
cd "$(brew --repository)"
git reset --hard FETCH_HEAD
```

If `brew doctor` still complains about uncommitted modifications, also run this command:

```sh
cd "$(brew --repository)/Library"
git clean -fd
```

### `launchctl` refuses to load `launchd` plist files

When trying to load a plist file with `launchctl`, you receive an error that resembles either:

    Bug: launchctl.c:2325 (23930):13: (dbfd = open(g_job_overrides_db_path, [...]
    launch_msg(): Socket is not connected

or:

    Could not open job overrides database at: /private/var/db/launchd.db/com.apple.launchd/overrides.plist: 13: Permission denied
    launch_msg(): Socket is not connected

These are likely due to one of four issues:

1. You are using iTerm. The solution is to use Terminal.app when interacting with `launchctl`.
1. You are using a terminal multiplexer such as `tmux` or `screen`. You should interact with `launchctl` from a separate Terminal.app shell.
1. You are attempting to run `launchctl` while logged in remotely. You should enable screen sharing on the remote machine and issue the command using Terminal.app running on that machine.
1. You are `su`'ed as a different user.

### `brew upgrade` errors out

When running `brew upgrade`, you see something like this:

    Error: undefined method `include?' for nil:NilClass
    Please report this bug:
        https://docs.brew.sh/Troubleshooting
    /usr/local/Library/Homebrew/formula.rb:393:in `canonical_name'
    /usr/local/Library/Homebrew/formula.rb:425:in `factory'
    /usr/local/Library/Contributions/examples/brew-upgrade.rb:7
    /usr/local/Library/Contributions/examples/brew-upgrade.rb:7:in `map'
    /usr/local/Library/Contributions/examples/brew-upgrade.rb:7
    /usr/local/bin/brew:46:in `require'
    /usr/local/bin/brew:46:in `require?'
    /usr/local/bin/brew:79

This happens because an old version of the upgrade command is hanging around for some reason. The fix:

```sh
cd "$(brew --repository)/Library/Contributions/examples"
git clean -n # if this doesn't list anything that you want to keep, then
git clean -f # this will remove untracked files
```

### Python: `easy-install.pth` cannot be linked

    Warning: Could not link <formula>. Unlinking...
    Error: The `brew link` step did not complete successfully
    The formula built, but is not symlinked into /usr/local
    You can try again using `brew link <formula>'

    Possible conflicting files are:
    /usr/local/lib/python2.7/site-packages/site.py
    /usr/local/lib/python2.7/site-packages/easy-install.pth
    ==> Could not symlink file: /homebrew/Cellar/<formula>/<version>/lib/python2.7/site-packages/site.py
    Target /usr/local/lib/python2.7/site-packages/site.py already exists. You may need to delete it.
    To force the link and overwrite all other conflicting files, do:
      brew link --overwrite formula_name

    To list all files that would be deleted:
      brew link --overwrite --dry-run formula_name

Don't follow the advice here but fix by using
`Language::Python.setup_install_args` in the formula as described in
[Python for Formula Authors](Python-for-Formula-Authors.md).

## Installation fails with "unknown revision or path not in the working tree"

When installing Homebrew, if the initial download fails with something like:

    error: Not a valid ref: refs/remotes/origin/master
    fatal: ambiguous argument 'refs/remotes/origin/master': unknown revision or path not in the working tree.
    Use '--' to separate paths from revisions, like this:
    'git <command> [<revision>...] -- [<file>...]'

or:

    fatal: the remote end hung up unexpectedly
    fatal: early EOF
    fatal: index-pack failed

This is an issue in the connection between your machine and GitHub, rather than a bug in Homebrew itself. See this [discussion topic](https://github.com/orgs/Homebrew/discussions/666) for a number of solutions others have found, such as using a wired connection or a VPN, or disabling network monitoring tools.

## Upgrading macOS

Upgrading macOS can cause errors like the following:

* `dyld: Library not loaded: /usr/local/opt/icu4c/lib/libicui18n.54.dylib`
* `configure: error: Cannot find libz`

Following a macOS upgrade it may be necessary to reinstall the Xcode Command Line Tools and then `brew upgrade` all installed formulae:

```sh
xcode-select --install
brew upgrade
```

## Homebrew Cask issues

### Cask - cURL error

First, let's tackle a common problem: do you have a `.curlrc` file? Check with `ls -A ~ | grep .curlrc` (if you get a result, the file exists). Those are a frequent cause of issues of this nature. Before anything else, remove that file and try again. If it now works, do not open an issue. Incompatible `.curlrc` configurations must be fixed on your side.

If, however, you do not have a `.curlrc` or removing it did not work, let’s see if the issue is upstream:

1. Go to the vendor’s website (`brew home <cask_name>`).
2. Find the download link for the app and click on it.

#### If the download works

The cask is outdated. Let’s fix it:

1. Look around the app’s website and find out what the latest version is. It may be expressed in the URL used to download it.
2. Take a look at the cask’s version (`brew info <cask_name>`) and verify it is indeed outdated. If the app’s version is `:latest`, it means the `url` itself is outdated. It will need to be changed to the new one.

Help us by [submitting a fix](https://github.com/Homebrew/homebrew-cask/blob/HEAD/CONTRIBUTING.md#updating-a-cask). If you get stumped, [open an issue](https://github.com/Homebrew/homebrew-cask/issues/new?template=01_bug_report.md) explaining your steps so far and where you’re having trouble.

#### If the download does not work

The issue isn’t in any way related to Homebrew Cask, but with the vendor or your connection.

Start by diagnosing your connection (try to download other casks, or browse around the web). If the problem is with your connection, try a website like [Ask Different](https://apple.stackexchange.com/) to ask for advice.

If you’re sure the issue is not with your connection, contact the app’s vendor and let them know their link is down, so they can fix it.

**Do not open an issue.**

### Cask - checksum does not match

First, check if the problem was with your download. Delete the downloaded file (its location will be pointed out in the error message) and try again.

If the problem persists, the cask must be outdated. It’ll likely need a new version, but it’s possible the version has remained the same (this happens occasionally when the vendor updates the app in-place).

1. Go to the vendor’s website (`brew home <cask_name>`).
2. Find out what the latest version is. It may be expressed in the URL used to download it.
3. Take a look at the cask’s version (`brew info <cask_name>`) and verify it is indeed outdated. If so, it will need to be updated.

Help us by [submitting a fix](https://github.com/Homebrew/homebrew-cask/blob/HEAD/CONTRIBUTING.md#updating-a-cask). If you get stumped, [open an issue](https://github.com/Homebrew/homebrew-cask/issues/new?template=01_bug_report.md) explaining your steps so far and where you’re having trouble.

### Cask - permission denied

In this case, it’s likely your user account has no admin rights and therefore lacks permissions for writing to `/Applications`, which is the default install location. You can use [`--appdir`](https://github.com/Homebrew/homebrew-cask/blob/HEAD/USAGE.md#options) to choose where to install your applications.

If `--appdir` doesn’t fix the issue or you do have write permissions to `/Applications`, verify you’re the owner of the `Caskroom` directory by running `ls -dl "$(brew --prefix)/Caskroom"` and checking the third field. If you are not the owner, fix it with `sudo chown -R "$(whoami)" "$(brew --prefix)/Caskroom"`. If you are, the problem may lie in the app bundle itself.

Some app bundles don’t have certain permissions that are necessary for us to move them to the appropriate location. You may check such permissions with `ls -ls '/path/to/application.app'`. If you see something like `dr-xr-xr-x` at the start of the output, that may be the cause. To fix it, we need to change the app bundle’s permission to allow us to move it, and then set it back to what it was (in case the developer set those permissions deliberately). See [litecoin.rb](https://github.com/Homebrew/homebrew-cask/blob/aa461148bbb5119af26b82cccf5003e2b4e50d95/Casks/l/litecoin.rb#L17-L27) for an example of such a cask.

Help us by [submitting a fix](https://github.com/Homebrew/homebrew-cask/blob/HEAD/CONTRIBUTING.md#updating-a-cask). If you get stumped, [open an issue](https://github.com/Homebrew/homebrew-cask/issues/new?template=01_bug_report.md) explaining your steps so far and where you’re having trouble.

### Cask - source is not there

First, you need to identify which artifact is not being handled correctly anymore. It’s explicit in the error message: if it says `It seems the App source…'` then the problem is with the [`app`](https://docs.brew.sh/Cask-Cookbook#stanza-app) stanza. This pattern is the same across [all artifacts](https://docs.brew.sh/Cask-Cookbook#at-least-one-artifact-stanza-is-also-required).

Fixing this error is typically easy, and requires only a bit of time on your part. Start by downloading the package for the cask: `brew fetch <cask_name>`. The last line of output will inform you of the location of the download. Navigate there and manually unpack it. As an example, let's say the structure inside the archive is as follows:

    .
    ├─ Files/SomeApp.app
    ├─ Files/script.sh
    └─ README.md

Now, if we find this when looking at the cask with `brew cat <cask_name>`:

    (…)
    app "SomeApp.app"
    (…)

The cask expects `SomeApp.app` to be in the top directory of the archive (see how it says simply `SomeApp.app`) but the developer has since moved it to be inside a `Files` directory. All we have to do is update that line of the cask to follow the new structure: `app "Files/SomeApp.app"`.

Note that occasionally the app’s name changes completely (from `SomeApp.app` to `OtherApp.app`, let's say). In these instances, the filename of the cask itself, as well as its token, must also change. Consult the [`token reference`](https://docs.brew.sh/Cask-Cookbook#token-reference) for complete instructions on the new name.

Help us by [submitting a fix](https://github.com/Homebrew/homebrew-cask/blob/HEAD/CONTRIBUTING.md#updating-a-cask). If you get stumped, [open an issue](https://github.com/Homebrew/homebrew-cask/issues/new?template=01_bug_report.md) explaining your steps so far and where you’re having trouble.

### Cask - wrong number of arguments

Make sure the issue really lies with your macOS version. To do so, try to install the software manually. If it is incompatible with your macOS version, it will tell you. In that case, there is nothing we can do to help you install the software, but we can add a [`depends_on macos:`](https://docs.brew.sh/Cask-Cookbook#depends_on-macos) stanza to prevent the cask from being installed on incompatible macOS versions.

Help us by [submitting a fix](https://github.com/Homebrew/homebrew-cask/blob/HEAD/CONTRIBUTING.md#updating-a-cask). If you get stumped, [open an issue](https://github.com/Homebrew/homebrew-cask/issues/new?template=01_bug_report.md) explaining your steps so far and where you’re having trouble.

## Other local issues

If your Homebrew installation gets messed up (and fixing the issues found by `brew doctor` doesn't solve the problem), reinstalling Homebrew may help to reset to a normal state. To easily reinstall Homebrew, use [Homebrew Bundle](https://github.com/Homebrew/homebrew-bundle) to automatically restore your installed formulae and casks. To do so, run `brew bundle dump`, [uninstall](https://docs.brew.sh/FAQ#how-do-i-uninstall-homebrew), [reinstall](https://docs.brew.sh/Installation) and run `brew bundle install`.
