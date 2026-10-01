---
last_review_date: "2026-07-18"
---

# Xcode and Command Line Tools Maintenance

This page is a maintainer runbook for updating Homebrew when Apple releases Xcode or the Command Line Tools.
Users looking for installation requirements should read [Installation](Installation.md#macos-requirements).

## Supported versions

Homebrew supports the current Xcode and Command Line Tools versions appropriate for each supported macOS release.
The authoritative version mappings and diagnostic messages are implemented in [`Library/Homebrew/os/mac/xcode.rb`](https://github.com/Homebrew/brew/blob/HEAD/Library/Homebrew/os/mac/xcode.rb).

Do not copy a current Xcode version into other documentation.
Link to the implementation or supported-platform documentation so the value has one maintained source.

## Updating for a release

When Apple publishes a new Xcode or Command Line Tools release:

1. Confirm the version, build number, bundled Apple Clang version and supported macOS versions from Apple's release information.
2. Update `OS::Mac::Xcode.latest_version` when the latest Xcode mapping changes.
3. Update `OS::Mac::CLT.latest_clang_version` when the Command Line Tools compiler mapping changes.
4. Update `OS::Mac::Xcode.detect_version_from_clang_version` when Homebrew must infer a new Xcode version from Apple Clang.
5. Review minimum-version checks and diagnostic text in the same file for assumptions affected by the release.
6. Add or update automated coverage for every changed mapping or inference.
7. Verify `brew config` and the relevant `brew doctor` output on an affected macOS runner when one is available.

Run the repository checks from the Homebrew/brew checkout:

```sh
./bin/brew typecheck
./bin/brew style --fix Library/Homebrew/os/mac/xcode.rb
./bin/brew tests --changed
```

Use `./bin/brew lgtm --online` before committing the complete change.
