---
last_review_date: "1970-01-01"
---

# Xcode

## Supported Xcode versions

Homebrew supports and recommends the latest Xcode and/or Command Line Tools available for your platform (see `OS::Mac::Xcode.latest_version` and `OS::Mac::CLT.latest_clang_version` in [`Library/Homebrew/os/mac/xcode.rb`](https://github.com/Homebrew/brew/blob/HEAD/Library/Homebrew/os/mac/xcode.rb)).

## Updating for new Xcode releases

When a new Xcode release is made, the following things need to be updated:

* In [`Library/Homebrew/os/mac/xcode.rb`](https://github.com/Homebrew/brew/blob/HEAD/Library/Homebrew/os/mac/xcode.rb)
  * `OS::Mac::Xcode.latest_version`
  * `OS::Mac::CLT.latest_clang_version`
  * `OS::Mac::Xcode.detect_version_from_clang_version`
