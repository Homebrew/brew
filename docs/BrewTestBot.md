---
logo: https://brew.sh/assets/img/brewtestbot.png
image: https://brew.sh/assets/img/brewtestbot.png
redirect_from:
  - /Brew-Test-Bot
last_review_date: "2025-02-08"
---

# BrewTestBot

[`brew test-bot`](Manpage.md#test-bot-options-formula) is Homebrew's continuous-integration orchestration command, originally funded by [our Kickstarter in 2013](https://www.kickstarter.com/projects/homebrew/brew-test-bot).
Homebrew's GitHub Actions workflows run it on macOS and Linux runners to build bottles and test the lifecycle of changes to Homebrew and its taps.
The workflow definitions are the authoritative description of the current runner and job configuration.

## Pull requests

The bot automatically builds pull requests and updates their status depending on the result of the job.

For example, a job which has been queued but not yet completed will have a section in the pull request that looks like this:

![Triggered Pull Request](assets/img/docs/brew-test-bot-triggered-pr.png)

---

A failed build looks like this:

![Failed Pull Request](assets/img/docs/brew-test-bot-failed-pr.png)

---

A passed build that's been approved to merge looks like this:

![Passed Pull Request](assets/img/docs/brew-test-bot-passed-pr.png)

---

On failed or passed builds you can click the "Details" link for each check to view its output in GitHub Actions.
