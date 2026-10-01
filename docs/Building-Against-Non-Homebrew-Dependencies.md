---
last_review_date: "2026-07-18"
---

# Building Against Non-Homebrew Dependencies

Homebrew formulae normally build in `superenv`, which filters the user's environment and exposes declared dependencies.
This makes builds reproducible and prevents an undeclared program or library on one contributor's machine from silently changing the result.

## `homebrew/core`

Formulae in `homebrew/core` must use declared Homebrew dependencies or supported platform facilities.
They cannot depend on an arbitrary executable, library or language runtime from the user's `PATH` when a Homebrew dependency is the supported alternative.

Declare ordinary dependencies with `depends_on` and use the default formula for requirements that provide one.
Do not use `env :std` in `homebrew/core` to expose undeclared user software.

## Third-party taps

If software must build against a private, locally managed or otherwise non-Homebrew dependency, [maintain the formula in your own tap](How-to-Create-and-Maintain-a-Tap.md).
Document the external dependency, supported versions and setup required by users of that tap.

An external tap may use `env :std` when exposing the user's normal environment is an intentional part of the formula's contract.
This reduces reproducibility and can make bottles unsuitable, so prefer a declared dependency whenever possible.

A tap can also define a [custom `Requirement`](https://github.com/Homebrew/brew/tree/HEAD/Library/Homebrew/requirements) when it can validate the external software precisely.
The requirement should explain how to satisfy it and should not accept versions or installations that the formula has not tested.

Run the tap's formula audit and tests in a clean environment to ensure that undeclared software does not accidentally become mandatory.
