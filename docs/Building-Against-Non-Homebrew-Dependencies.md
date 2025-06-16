---
last_review_date: "1970-01-01"
---

# Building Against Non-Homebrew Dependencies

## History

Originally Homebrew was a build-from-source package manager and all user environment variables and non-Homebrew-installed software were available to builds. Since then Homebrew added `Requirement`s to specify dependencies on non-Homebrew software (such as those provided by `brew cask` like X11/XQuartz), the `superenv` build system to strip out unspecified dependencies, environment filtering to stop the user environment leaking into Homebrew builds and `default_formula` to specify that a `Requirement` can be satisfied by a particular formula.

As Homebrew became primarily a binary package manager, most users were fulfilling `Requirement`s with the `default_formula`, not with arbitrary alternatives. To improve quality and reduce variation, Homebrew now exclusively supports using the default formula, as an ordinary dependency, and no longer supports using arbitrary alternatives.

## Today

If you wish to build against custom non-Homebrew dependencies that are provided by Homebrew (e.g. a non-Homebrew, non-macOS `ruby`) then you must [create and maintain your own tap](How-to-Create-and-Maintain-a-Tap.md) as these formulae will not be accepted in Homebrew/homebrew-core. Once you have done that you can specify `env :std` in the formula which will allow e.g. `which ruby` to access your existing `PATH` variable and allow compilation to link against this Ruby. You can also [include a custom Requirement](https://github.com/Homebrew/brew/tree/HEAD/Library/Homebrew/requirements) in your formula that more accurately describes the non-Homebrew software you build against.
