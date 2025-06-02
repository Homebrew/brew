---
last_review_date: "1970-01-01"
---

# Taps (Third-Party Repositories)

The `brew tap` command adds more repositories to the list of formulae that Homebrew tracks, updates,
and installs from. By default, `tap` assumes that the repositories come from GitHub,
but the command isn't limited to any one location.

## The `brew tap` command

* `brew tap` without arguments lists all currently tapped repositories. For
  example:

  ```console
  $ brew tap
  homebrew/cask
  homebrew/core
  petere/postgresql
  ```

* `brew tap <user>/<repo>` makes a clone of the repository at
  `https://github.com/<user>/homebrew-<repo>` into `$(brew --repository)/Library/Taps`.
  After that, `brew` will be able to work with those formulae as if they were in Homebrew's
  [homebrew/core](https://github.com/Homebrew/homebrew-core) canonical repository.
  You can install and uninstall them with `brew [un]install`, and the formulae are
  automatically updated when you run `brew update`. (See below for details
  about how `brew tap` handles the names of repositories.)

* `brew tap <user>/<repo> <URL>` makes a clone of the repository at _URL_.
  Unlike the one-argument version, _URL_ is not assumed to be GitHub, and it
  doesn't have to be HTTP. Any location and any protocol that Git can handle is
  fine, although non-GitHub taps require running `brew tap --force-auto-update <user>/<repo>`
  to enable automatic updating.

* `brew tap --repair` migrates tapped formulae from a symlink-based to
  directory-based structure. (This should only need to be run once.)

* `brew untap user/repo [user/repo user/repo ...]` removes the given taps. The
  repositories are deleted and `brew` will no longer be aware of their formulae.
  `brew untap` can handle multiple removals at once.

## Repository naming conventions and assumptions

On GitHub, your repository must be named `homebrew-something` to use
the one-argument form of `brew tap`. The prefix "homebrew-" is not optional.
(The two-argument form doesn't have this limitation, but it forces you to
give the full URL explicitly.)

When you use `brew tap` on the command line, however, you can leave out the
"homebrew-" prefix in commands. That is, `brew tap username/foobar` can be used as a shortcut for the long
version: `brew tap username/homebrew-foobar`. `brew` will automatically add
back the "homebrew-" prefix whenever it's necessary.

## Formula with duplicate names

If your tap contains a formula that is also present in
[homebrew/core](https://github.com/Homebrew/homebrew-core), that's fine,
but you would need to specify its fully qualified name in the form
`<user>/<repo>/<formula>` to install your version.

Whenever a `brew install foo` command is issued, `brew` selects which formula
to use by searching in the following order:

* core formulae
* other taps

If you need a formula to be installed from a particular tap, you can use fully
qualified names to refer to them.

If you were to create a tap for an alternative `vim` formula, the behaviour would be:

```sh
brew install vim                     # installs from homebrew/core
brew install username/repo/vim       # installs from your custom repository
```

As a result, we recommend you give new names to customized formulae if you want to make
them easier to install. Note that there is (intentionally) no way of replacing
dependencies of core formulae with those from other taps.
