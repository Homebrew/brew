---
last_review_date: "1970-01-01"
---

# Acceptable Formulae

Some formulae should not go in [homebrew/core](https://github.com/Homebrew/homebrew-core). But there are additional [Interesting Taps and Forks](Interesting-Taps-and-Forks.md) and anyone can [start their own](How-to-Create-and-Maintain-a-Tap.md)!

* Table of Contents
{:toc}

## Requirements for `homebrew/core`

### Supported platforms

The formula needs to build and pass tests on the latest 3 supported macOS versions ([Apple Silicon and x86_64](Installation.md#macos-requirements)) and on x86_64 [Linux](Linux-CI.md). Please have a look at the continuous integration jobs on a pull request in `homebrew/core` to see the full list of OSs. If upstream does not support one of these platforms, an exception can be made and the formula can be disabled for that platform.

### Duplicates of system packages

We now accept stuff that comes with macOS as long as it uses `keg_only :provided_by_macos` to be keg-only by default.

### Versioned formulae

We now accept versioned formulae as long as they [meet the requirements](Versions.md).

### Not a fork (usually)

We will not add new formulae using forks unless at least one of the following is true:

* the fork has been designated the official successor in the original source repository (e.g. in the README) or in a publicly verifiable way by the original author (e.g. in an issue or pull request comment)
* the fork has been used as the replacement by at least two other major distributions (e.g. Debian, Fedora, Arch, Gentoo, not smaller Linux distributions that are not widely used)

The fork must still meet all the other acceptable formulae requirements (including those of e.g. popularity and self-submission).

An alternative to the fork replacing the original formula is a new formula. For example, if `MikeMcQuaid` forked `curl` and it was very popular: a `curl-mikemcquaid` formula might make sense.

### We don’t like tools that upgrade themselves

Software that can upgrade itself does not integrate well with Homebrew formulae's own upgrade functionality. The self-update functionality should be disabled (while minimising complication to the formula). It's fine (and well-supported) for Casks.

### We don’t like install scripts that download unversioned things

We don't like install scripts that are pulling from the master branch of Git repositories or unversioned, unchecksummed tarballs. These should ideally use `resource` blocks with specific revisions or checksummed tarballs instead. Note that we now allow tools like `cargo`, `gem` and `pip` to download versioned libraries during installation. There's no need to reproduce the functionality of any language package manager with `resource` blocks when we can call it instead.

### We don’t like binary formulae

Our policy is that formulae in the core tap ([homebrew/core](https://github.com/Homebrew/homebrew-core)) must be open-source with a [Debian Free Software Guidelines license](https://wiki.debian.org/DFSGLicenses) and either built from source or producing cross-platform binaries (e.g. Java, Mono). Binary-only formulae should go in [homebrew/cask](https://github.com/Homebrew/homebrew-cask).

Additionally, core formulae must also not depend on casks or any other proprietary software. This includes automatic installation of casks at runtime.

### Stable versions

Formulae in the core repository must have a stable version tagged by the upstream project. Tarballs are preferred to Git checkouts, and tarballs should include the version in the filename whenever possible.

We don’t accept software without a tagged version because they regularly break due to upstream changes and we can’t provide [bottles](Bottles.md) for them.

### Niche (or self-submitted) stuff

The software in question must:

* be maintained (i.e. the last release wasn't ages ago, it works without patching on all Homebrew-supported OS versions and has no outstanding, unpatched security vulnerabilities)
* be stable (e.g. not declared "unstable" or "beta" by upstream)
* be known (e.g. GitHub repositories should have >=30 forks, >=30 watchers or >=75 stars)
* be used
* have a homepage

We will reject formulae that seem too obscure, partly because they won’t get maintained and partly because we have to draw the line somewhere.

We frown on authors submitting their own work unless it is very popular.

Don’t forget Homebrew is all Git underneath! [Maintain your own tap](How-to-Create-and-Maintain-a-Tap.md) if you have to!

There may be exceptions to these rules in the main repository; we may include things that don't meet these criteria or reject things that do. Please trust that we need to use our discretion based on our experience running a package manager.

### Stuff that builds an `.app`

Don’t make your formula build an `.app` (native macOS Application); we don’t want those things in Homebrew. Encourage upstream projects to build and support a `.app` that can be distributed by [homebrew/cask](https://github.com/Homebrew/homebrew-cask) (and used without it, too).

### Stuff that builds a GUI by default (but doesn't have to)

Make it build a command-line tool or a library by default and, if the GUI is useful and would be widely used, also build the GUI. Don’t build X11/XQuartz GUIs as they are a bad user experience on macOS.

### Stuff that doesn't build with the latest, stable Xcode Clang

Clang is the default C/C++ compiler on macOS (and has been for a long time). Software that doesn't build with it hasn't been adequately ported to macOS.

### Stuff that requires heavy manual pre/post-install intervention

We're a package manager so we want to do things like resolve dependencies and set up applications for our users. If things require too much manual intervention then they aren't useful in a package manager.

### Shared vs. static libraries

In general, if formulae have to ship either shared or static libraries: they should ship shared ones.
If there is interest in static libraries they can ship both.
Shipping only static libraries should be avoided when possible, particularly when the formula is depended on by other formulae since these dependents cannot be updated without a rebuild.

### Stuff that requires vendored versions of Homebrew formulae

Homebrew formulae should avoid having multiple, separate, upstream projects bundled together in a single package to avoid shipping outdated/insecure versions of software that is already a formula. Veracode's [State of Software Security report](https://www.veracode.com/blog/research/announcing-state-software-security-v11-open-source-edition) concludes:
> In fact, 79% of the time, developers never update third-party libraries after including them in a codebase.

For more info see [Debian's](https://www.debian.org/doc/debian-policy/ch-source.html#s-embeddedfiles) and [Fedora's](https://docs.fedoraproject.org/en-US/packaging-guidelines/#bundling) stances on this.

Increasingly, though: this can be (too) hard. Homebrew's primary mission is to be useful rather than ideologically pure. If we cannot package something without using vendored upstream versions: so be it; better to have packaged software in Homebrew than not.

## Sometimes there are exceptions

Even if all criteria are met we may not accept the formula. Even if some criteria are not met we may accept the formula. New formulae are held to a higher standard than existing formulae. Documentation will lag behind current decision-making. Although some rejections may seem arbitrary or strange they are based on years of experience making Homebrew work acceptably for our users.
