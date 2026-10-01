---
last_review_date: "2026-07-18"
---

# Adding Software to Homebrew

Homebrew accepts new software as either a formula or a cask.
This page helps choose the correct package type and routes each step to the maintained reference instead of duplicating complete formula and cask examples.

## Choose a package type

<a data-proofer-ignore name="casks"></a>

Use a formula for open source command-line software and libraries that Homebrew can build from source.
Use a cask for native macOS applications and for proprietary or supported binary-only software.
Casks may target macOS, Linux or both, but only supported artifact types are available on each operating system.

Read the acceptance policy before writing the package:

- [Acceptable Formulae](Acceptable-Formulae.md)
- [Acceptable Casks](Acceptable-Casks.md)
- [Package Acceptance Policy](Package-Acceptance-Policy.md)
- [Versioned Formulae](Versions.md) when packaging a non-current major or minor release

Search open and closed pull requests in [`homebrew/core`](https://github.com/Homebrew/homebrew-core/pulls) or [`homebrew/cask`](https://github.com/Homebrew/homebrew-cask/pulls) before starting.
A previous rejection may identify an unresolved licensing, security, maintenance or distribution problem.

## Prepare a contribution checkout

Follow [How to Open a Homebrew Pull Request](How-To-Open-a-Homebrew-Pull-Request.md) to fork the correct repository, tap its local checkout and create a branch from the latest `origin/HEAD`.

Use `brew create` to generate a starting point from the release download URL:

```sh
brew create URL
brew create --cask URL
```

`brew create --help` lists language and build-system templates such as `--python`, `--node`, `--cmake` and `--rust`.
Use `--tap homebrew/core` or `--tap homebrew/cask` when Homebrew cannot infer the intended repository.

Generated files are templates, not completed packages.
Review every field, remove unused boilerplate and compare the result with current packages that use the same build or artifact type.

## Write the package

For a formula, use the [Formula Cookbook](Formula-Cookbook.md) as the authoritative DSL and testing reference.
The [language-specific formula guide](Language-Specific-Formulae.md) covers Python, Node.js, Java and Ruby helpers.

For a cask, use the [Cask Cookbook](Cask-Cookbook.md) for token rules, required stanzas, artifact selection, uninstall behaviour and `zap` guidance.
Do not copy a complete cask from a general documentation page because versions, checksums, URLs and vendor packaging change frequently.

In both cases:

- use the vendor's canonical homepage and immutable release source
- verify downloads with SHA-256 when the URL is versioned
- declare only required dependencies
- add a meaningful test for formulae
- include complete uninstall behaviour for casks that run an installer
- avoid scripts or permissions broader than the installation requires

## Test locally

Use the current commands from the pull-request guide.
The normal validation is:

```sh
HOMEBREW_NO_INSTALL_FROM_API=1 brew install --build-from-source FORMULA
brew test FORMULA
brew audit --strict --new --online FORMULA
brew style --fix --formula FORMULA
```

For a cask:

<a data-proofer-ignore name="testing-and-auditing-the-cask"></a>

```sh
HOMEBREW_NO_INSTALL_FROM_API=1 brew install --cask CASK
brew uninstall --cask CASK
brew audit --new --cask CASK
brew style --fix --cask CASK
```

Inspect the installed files and user-facing output, not only the exit status.
Run `brew lgtm --online` from the contribution checkout before submitting the pull request.

## Submit the pull request

Return to [How to Open a Homebrew Pull Request](How-To-Open-a-Homebrew-Pull-Request.md#create-your-pull-request-from-a-new-branch) for commit, push and submission instructions.
Complete the pull-request template, disclose AI assistance when applicable and respond to review feedback with tested changes.

Use [Homebrew Discussions](https://github.com/orgs/Homebrew/discussions) when the package type, policy or build approach remains unclear after reading the relevant guide.
