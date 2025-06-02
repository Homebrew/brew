---
last_review_date: "1970-01-01"
---

# How to Build Software Outside Homebrew with Homebrew `keg_only` Dependencies

## What does "keg-only" mean?

The [FAQ](FAQ.md#what-does-keg-only-mean) briefly explains this.

As an example:

*OpenSSL isn’t symlinked into my `PATH` and non-Homebrew builds can’t find it!*

This is because Homebrew isolates it within its individual prefix, rather than symlinking to the publicly available location.

## Advice on potential workarounds

A number of people in this situation are either forcefully linking keg-only tools with `brew link --force` or moving default system utilities out of the `PATH` and replacing them with manually created symlinks to the Homebrew-provided tool.

*Please* do not remove macOS native tools and forcefully replace them with symlinks back to the Homebrew-provided tool. Doing so can and likely will cause significant breakage when attempting to build software.

`brew link --force` creates a warning in `brew doctor` to let both you and maintainers know that a link exists that could be causing issues. If you’ve linked something and there’s no problems at all? Feel free to ignore the `brew doctor` error.

## How do I use those tools outside of Homebrew?

Useful, reliable alternatives exist should you wish to use keg-only tools outside of Homebrew.

### Build flags

You can set flags to give configure scripts or Makefiles a nudge in the right direction. An example of flag setting:

```sh
./configure --prefix=/Users/Dave/Downloads CFLAGS="-I$(brew --prefix openssl)/include" LDFLAGS="-L$(brew --prefix openssl)/lib"
```

An example using `pip`:

```sh
CFLAGS="-I$(brew --prefix icu4c)/include" LDFLAGS="-L$(brew --prefix icu4c)/lib" pip install pyicu
```

### `PATH` modification

You can temporarily prepend your `PATH` with the tool’s `bin` directory, such as:

```sh
export PATH="$(brew --prefix openssl)/bin:${PATH}"
```

This will prepend the directory to your `PATH`, ensuring any build script that searches the `PATH` will find it first.

Changing your `PATH` using this command ensures the change only exists for the duration of the shell session. Once the current session ends, the `PATH` reverts to its prior state.

### `pkg-config` detection

If the tool you are attempting to build is [pkg-config](https://en.wikipedia.org/wiki/Pkg-config) aware, you can amend your `PKG_CONFIG_PATH` to find a keg-only utility’s `.pc` files, if it has any. Not all formulae ship with these files.

An example of this is:

```sh
export PKG_CONFIG_PATH="$(brew --prefix openssl)/lib/pkgconfig"
```

If you’re curious about the `PKG_CONFIG_PATH` variable, `man pkg-config` goes into more detail.

You can get `pkg-config` to print the default search path with:

```sh
pkg-config --variable pc_path pkg-config
```
