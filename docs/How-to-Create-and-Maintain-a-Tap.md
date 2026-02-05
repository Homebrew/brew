---
last_review_date: "2025-09-05"
---

# How to Create and Maintain a Tap

[Taps](Taps.md) are external sources of Homebrew formulae, casks and/or external commands. They can be created by anyone to provide their own formulae, casks and/or external commands to any Homebrew user.

## Creating a tap

A tap is usually a Git repository available online, but you can use anything as long as it’s a protocol that Git understands, or even just a directory with files in it. If hosted on GitHub, we recommend that the repository’s name start with `homebrew-` so the short `brew tap` command can be used. See the [`brew` manual page](Manpage.md) for more information on repository naming.

The `brew tap-new` command can be used to create a new tap along with some template files:

```console
$ brew tap-new $YOUR_GITHUB_USERNAME/homebrew-tap
Initialized empty Git repository in /opt/homebrew/Library/Taps/$YOUR_GITHUB_USERNAME/homebrew-tap/.git/
...
==> Created $YOUR_GITHUB_USERNAME/tap
/opt/homebrew/Library/Taps/$YOUR_GITHUB_USERNAME/homebrew-tap
```

This creates a local tap with the proper directory structure.
Next, you can push it to a new GitHub repository by running (from any directory):

```console
$ brew install gh
...
$ gh repo create $YOUR_GITHUB_USERNAME/homebrew-tap --push --public --source "$(brew --repository $YOUR_GITHUB_USERNAME/homebrew-tap)"
✓ Created repository $YOUR_GITHUB_USERNAME/homebrew-tap on github.com
  https://github.com/$YOUR_GITHUB_USERNAME/homebrew-tap
✓ Added remote https://github.com/$YOUR_GITHUB_USERNAME/homebrew-tap.git
...
✓ Pushed commits to https://github.com/$YOUR_GITHUB_USERNAME/homebrew-tap.git
```

Assuming you leave the default `.github/workflows` files in place,
["bottles" (binary packages) will be built and uploaded to GitHub Releases](https://brew.sh/2020/11/18/homebrew-tap-with-bottles-uploaded-to-github-releases).

If you run `brew tap-new --github-packages`, you can upload to GitHub Packages instead.

Tap formulae follow the same format as the core’s ones, and can be added under either the `Formula` subdirectory, the `HomebrewFormula` subdirectory or the repository’s root. The first available directory is used, other locations will be ignored. We recommend the use of subdirectories because it makes the repository organisation easier to grasp, and top-level files are not mixed with formulae.

See [homebrew/core](https://github.com/Homebrew/homebrew-core) for an example of a tap with a `Formula` subdirectory.

### Creating your formula or cask

Run `brew create` to create a formula or cask file in your tap and open it in your text editor:

```console
$ brew create https://mirror.ibcp.fr/pub/gnu/wget/wget-1.25.0.tar.gz --tap $YOUR_GITHUB_USERNAME/homebrew-tap --set-name $YOUR_GITHUB_USERNAME-wget
==> Downloading from https://mirror.ibcp.fr/pub/gnu/wget/wget-1.25.0.tar.gz
...
Editing /opt/homebrew/Library/Taps/$YOUR_GITHUB_USERNAME/homebrew-tap/Formula/$YOUR_GITHUB_USERNAME-wget.rb
```

After that, follow the [Adding Software to Homebrew](Adding-Software-to-Homebrew.md) guide to create your formula or cask file.

Finally, `git add`, `git commit` and `git push` your formula or cask to your tap and others can use it too.

### Naming your formulae to avoid clashes

If a formula in your tap has the same name as a Homebrew/homebrew-core formula they cannot be installed side-by-side. If you wish to create a different version of a formula that's in Homebrew/homebrew-core (e.g. with `option`s) consider giving it a different name; e.g. `nginx-full` for a more full-featured `nginx` formula. This will allow both `nginx` and `nginx-full` to be installed at the same time (assuming one is [keg-only](FAQ.md#what-does-keg-only-mean) or the linked files do not clash).

## Installing

There are two ways users can install formulae from your tap:

### Direct installation (recommended)

Users can install any of your formulae directly with `brew install user/repository/formula`. Homebrew will automatically add your tap before installing the formula:

```console
$ brew install alice/homebrew-tap/my-script
==> Tapping alice/homebrew-tap
Cloning into '/opt/homebrew/Library/Taps/alice/homebrew-tap'...
...
==> Installing my-script from alice/homebrew-tap
```

This is the most convenient method for users as it requires only one command.

### Manual tap installation

To install your tap without installing any formula at the same time, users can add it with the [`brew tap` command](Taps.md):

```console
# For GitHub repositories
$ brew tap user/repository

# For repositories hosted elsewhere
$ brew tap user/repo <URL>
```

Where `user` is your GitHub username, `repository` is your repository name, and `<URL>` is your Git clone URL for non-GitHub repositories.

After tapping, users can install your formulae either with:

- `brew install foo` if there's no core formula with the same name
- `brew install user/repository/foo` to avoid conflicts with core formulae

## Maintaining a tap

A tap is just a Git repository so you don't have to do anything specific when making modifications, apart from committing and pushing your changes.

### Updating

Once your tap is installed, Homebrew will update it each time a user runs `brew update`. Outdated formulae will be upgraded when a user runs `brew upgrade`, like core formulae.

### Best practices

- **Keep your tap up to date**: Regularly update your formulae to the latest versions of the software you're packaging
- **Test your formulae**: Before pushing changes, test your formulae locally with `brew install --build-from-source user/repository/formula`
- **Use semantic versioning**: Tag your releases with version numbers (e.g. `1.0.0`) to make it easier for users to track changes
- **Provide clear documentation**: Include a `README` in your tap repository explaining what your formulae do and how to use them
- **Handle dependencies**: Make sure your formulae properly declare all dependencies using `depends_on`

### Troubleshooting

- **Formula not found after installation**: Make sure your formula file is in the correct location (`Formula/` subdirectory) and has the right file extension (`.rb`).
- **Installation fails**: Check that your formula's `url` and `sha256` values are correct. You can verify the SHA256 with:

  ```console
  curl -L <URL> | shasum -a 256
  ```

- **Tap not updating**: Users may need to run `brew untap user/repository && brew tap user/repository` to force a fresh clone of your tap.
- **Conflicts with core formulae**: If your formula conflicts with a core formula, consider renaming it or making it [keg-only](FAQ.md#what-does-keg-only-mean).

## Casks

Casks can also be installed from a tap. Casks can be included in taps with formulae, or in a tap with just casks. Place any cask files you wish to make available in a `Casks` directory at the top level of your tap.

See [homebrew/cask](https://github.com/Homebrew/homebrew-cask) for an example of a tap with a `Casks` subdirectory.

### Naming

Unlike formulae, casks must have globally unique names to avoid clashes. This can be achieved by e.g. prepending the cask name with your GitHub username: `username-formula-name`.

## External commands

You can provide your tap users with custom `brew` commands by adding them in a `cmd` subdirectory. [Read more on external commands](External-Commands.md).

## Upstream taps

Some upstream software providers like to package their software in their own Homebrew tap. When their software is [eligible for Homebrew/homebrew-core](Acceptable-Formulae.md) we prefer to maintain software there for ease of updates, improved discoverability and use of tools such as [formulae.brew.sh](https://formulae.brew.sh/).

We are not willing to remove software packaged in Homebrew/homebrew-core in favour of an upstream tap. We are not willing to instruct users of our formulae to use an upstream tap instead. If upstream projects have issues with how Homebrew packages your software: please file issues (or, ideally, pull requests) to address these problems.

There’s an increasing desire in commercial open source about “maintaining control” e.g. defining exactly what binaries are shipping to users. Not supporting users (or even software distributions) to build-from-source is antithetical to the values of open source. If you think Homebrew's perspective is annoying on this: try and see how Debian responds to requests to ship your binaries.
