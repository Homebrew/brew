---
last_review_date: "1970-01-01"
---

# Troubleshooting

**Run `brew update` twice and `brew doctor` (and fix all the warnings) *before* creating an issue!**

This document will help you check for common issues and make sure your issue has not already been reported.

## Check for common issues

* Read through the list of [Common Issues](Common-Issues.md).

## Check to see if the issue has been reported

* Search the appropriate issue tracker to see if someone else has already reported the same issue:
  * [Homebrew/homebrew-core issue tracker](https://github.com/Homebrew/homebrew-core/issues) (formulae)
  * [Homebrew/homebrew-cask issue tracker](https://github.com/Homebrew/homebrew-cask/issues) (casks)
  * [Homebrew/brew issue tracker](https://github.com/Homebrew/brew/issues) (`brew` itself)
* If the formula or cask that has failed to install is part of a non-Homebrew tap, then check that tap's issue tracker instead.
* Search the [Homebrew discussion forum](https://github.com/orgs/Homebrew/discussions) or [Discourse archive](https://discourse.brew.sh/) to see if any discussions have started about the issue.

## Create an issue

If your problem hasn't been solved or reported, then create an issue:

1. Collect debugging information:
  * If you have a problem with installing a formula: run `brew gist-logs <formula>` (where `<formula>` is the name of the formula) to upload the logs to a new [Gist](https://gist.github.com).
  * If your have a non-formula problem: collect the output of `brew config` and `brew doctor`.

1. Create a new issue on the issue tracker for [Homebrew/homebrew-core](https://github.com/Homebrew/homebrew-core/issues/new/choose), [Homebrew/homebrew-cask](https://github.com/Homebrew/homebrew-cask/issues/new/choose) or [Homebrew/brew](https://github.com/Homebrew/brew/issues/new/choose) and follow the instructions:
  * Give your issue a descriptive title which includes the formula name (if applicable) and the version of macOS or Linux you are using. For example, if a formula fails to build, title your issue "\<formula> failed to build on \<platform>", where *\<formula>* is the name of the formula that failed to build, and *\<platform>* is the name and version of macOS or Linux you are using.
  * Include the URL provided by `brew gist-logs <formula>` (if applicable) plus links to any additional Gists you may have created.
  * Include the output of `brew config` and `brew doctor`.
