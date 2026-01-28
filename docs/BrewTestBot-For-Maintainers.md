---
logo: /assets/img/brewtestbot.png
image: /assets/img/brewtestbot.png
redirect_from:
  - /Brew-Test-Bot-For-Core-Contributors
last_review_date: "1970-01-01"
---

# BrewTestBot for Maintainers

[`brew test-bot`](Manpage.md#test-bot-options-formula) is the command our [CI](https://github.com/BrewTestBot) runs to test and build bottles for formulae.

## Publishing Bottles

If CI is passing on a pull request and it doesn't need any modifications (e.g. commit message, revision bump, etc.):

1. Review and approve the pull request. Be sure to thank the contributor!
2. Wait for BrewTestBot to automatically merge the pull request. This job usually starts within a minute if both of the following are true:
    - The pull request is approved by a maintainer who has write access to homebrew-core.
    - CI is passing.

If any jobs did not complete successfully, the pull request will not automatically merge. Additionally, BrewTestBot will comment on the pull request if there is a publishing failure.

If a pull request won't be automatically merged by BrewTestBot (has the labels `autosquash`, `automerge-skip`, or`new formula`, or has some kind of acceptable CI failure):

1. Ensure that bottles have built successfully.
2. Run `brew pr-publish 12345` where `12345` is the pull request number (or URL).
3. Watch the [actions queue](https://github.com/Homebrew/homebrew-core/actions) to ensure your job finishes. BrewTestBot will notify you of failures with a ping as well.

If a pull request needs its commit messages changed in a way that autosquash doesn't support (has the label `automerge-skip`):

1. Ensure that bottles have built successfully.
2. Run `brew pr-pull 12345` where `12345` is the pull request number (or URL).
3. Amend any relevant commits if needed, then run `git push` to push the commits to the pull request.

## Rebottling

If a formula in homebrew-core needs rebottling for any reason:

1. Navigate to [homebrew-core's rebottling workflow page](https://github.com/Homebrew/homebrew-core/actions/workflows/dispatch-rebottle.yml)
2. Click on the "Run workflow" button on the right of the page.
3. Fill out any necessary fields.
