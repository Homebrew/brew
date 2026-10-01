---
last_review_date: "2026-07-18"
---

# Troubleshooting

Use this checklist before creating a Homebrew issue.

## Update and diagnose

1. Run `brew update`.
2. Run `brew update` again so the first update cannot leave the failing command on an older Homebrew version.
3. Run `brew doctor` and read every warning.
4. Correct warnings that apply to the failing command.
5. Retry the original command and keep its complete output.

Do not apply destructive Git, ownership or permission changes from an old issue report without understanding which files they affect.
See [Common Issues](Common-Issues.md) for current recovery guidance.

## Search existing reports

Search the tracker responsible for the failing component:

- [`Homebrew/homebrew-core` issues](https://github.com/Homebrew/homebrew-core/issues) for formulae
- [`Homebrew/homebrew-cask` issues](https://github.com/Homebrew/homebrew-cask/issues) for casks
- [`Homebrew/brew` issues](https://github.com/Homebrew/brew/issues) for the `brew` command
- The tap's own tracker for a formula, cask or command from a non-Homebrew tap

Also search [Homebrew Discussions](https://github.com/orgs/Homebrew/discussions) for support and related reports.
The Discourse archive is no longer online; anything you find quoted from it is historical material and will contain outdated instructions.

## Collect diagnostic information

For a formula installation or build failure, upload its logs:

```sh
brew gist-logs FORMULA
```

For other failures, collect:

```sh
brew config
brew doctor
```

Remove credentials, private repository URLs and other secrets before publishing terminal output.
Do not omit warnings merely because they appear unrelated.

## Create an issue

If the problem is neither resolved nor already reported, use the issue template in the appropriate repository:

- [`Homebrew/homebrew-core` issue chooser](https://github.com/Homebrew/homebrew-core/issues/new/choose)
- [`Homebrew/homebrew-cask` issue chooser](https://github.com/Homebrew/homebrew-cask/issues/new/choose)
- [`Homebrew/brew` issue chooser](https://github.com/Homebrew/brew/issues/new/choose)

Include the command, complete error, relevant `brew config` and `brew doctor` output and the `brew gist-logs` URL when available.
Use a descriptive title that identifies the package, failure and operating system.

See [Creating a Homebrew Issue](Creating-a-Homebrew-Issue.md) for reporting expectations.
