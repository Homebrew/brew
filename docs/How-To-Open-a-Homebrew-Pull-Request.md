---
last_review_date: "2026-01-06"
---

# How to Open a Homebrew Pull Request

The following commands are used by Homebrew contributors to set up a fork of Homebrew's Git repository on GitHub, create a new branch and create a GitHub pull request ("PR") for the changes in that branch.

The type of change you want to make influences which of Homebrew's main repositories you'll need to send your pull request to. If you want to submit a change to Homebrew's core code (the `brew` implementation), you should open a pull request on [Homebrew/brew](https://github.com/Homebrew/brew). If you want to submit a change for a formula, you should open a pull request on the [homebrew/core](https://github.com/Homebrew/homebrew-core) tap, while for casks you should open the pull request on the [homebrew/cask](https://github.com/Homebrew/homebrew-cask) tap or another [official tap](https://github.com/Homebrew), depending on the formula type.

## Submit a new version of an existing formula

1. Use [`brew bump-formula-pr`](Manpage.md#bump-formula-pr-options-formula) to do everything (i.e. forking, committing, pushing) with a single command. Run `brew bump-formula-pr --help` to learn more.

## Submit a new version of an existing cask

1. Use [`brew bump-cask-pr`](Manpage.md#bump-cask-pr-options-cask) to do everything (i.e. forking, committing, pushing) with a single command. Run `brew bump-cask-pr --help` to learn more.

## Set up your own fork of the Homebrew repository

### Core `brew` code pull request

1. [Fork the Homebrew/brew repository on GitHub](https://github.com/Homebrew/brew/fork).
   * This creates a personal remote repository that you can push to. This is needed because only Homebrew maintainers have push access to the main repositories.
2. Change to the directory containing your Homebrew installation:

   ```sh
   cd "$(brew --repository)"
   ```

3. Add your pushable forked repository as a new remote:

   ```sh
   git remote add <YOUR_USERNAME> https://github.com/<YOUR_USERNAME>/brew.git
   ```

   * `<YOUR_USERNAME>` is your GitHub username, not your local machine username.

### Formulae-related pull request

Before creating a new formula, please read [Acceptable Formulae](Acceptable-Formulae.md).

1. [Fork the Homebrew/homebrew-core repository on GitHub](https://github.com/Homebrew/homebrew-core/fork).
   * This creates a personal remote repository that you can push to. This is needed because only Homebrew maintainers have push access to the main repositories.
2. Tap (download a local clone of) the repository of core Homebrew formulae:

   ```sh
   brew tap --force homebrew/core
   ```

3. Change to the directory containing Homebrew formulae:

   ```sh
   cd "$(brew --repository homebrew/core)"
   ```

4. Add your pushable forked repository as a new remote:

   ```sh
   git remote add <YOUR_USERNAME> https://github.com/<YOUR_USERNAME>/homebrew-core.git
   ```

   * `<YOUR_USERNAME>` is your GitHub username, not your local machine username.

### Cask-related pull request

Before creating a new cask, please read [Acceptable Casks](Acceptable-Casks.md).

1. [Fork the Homebrew/homebrew-cask repository on GitHub](https://github.com/Homebrew/homebrew-cask/fork).
   * This creates a personal remote repository that you can push to. This is needed because only Homebrew maintainers have push access to the main repositories.
2. Tap (download a local clone of) the repository of core Homebrew casks:

   ```sh
   brew tap --force homebrew/cask
   ```

3. Change to the directory containing Homebrew casks:

   ```sh
   cd "$(brew --repository homebrew/cask)"
   ```

4. Add your pushable forked repository as a new remote:

   ```sh
   git remote add <YOUR_USERNAME> https://github.com/<YOUR_USERNAME>/homebrew-cask.git
   ```

   * `<YOUR_USERNAME>` is your GitHub username, not your local machine username.

## Create your pull request from a new branch

To make changes on a new branch and submit it for review, create a GitHub pull request with the following steps:

1. Check out the `main` branch:

   ```sh
   git checkout main
   ```

2. Retrieve new changes to the `main` branch:

   ```sh
   brew update
   ```

3. Create a new branch from the latest default branch:

   ```sh
   git checkout -b <YOUR_BRANCH_NAME> origin/HEAD
   ```

4. Make your changes. For formulae or casks, use `brew edit` or your favourite text editor, using the guidelines in the [Formula Cookbook](Formula-Cookbook.md) or [Cask Cookbook](Cask-Cookbook.md) for reference.
   * If there's a `bottle do` block in the formula, don't remove or change it; we'll update it when we merge your PR.
5. Test your changes by running the following, and ensure they all pass without issue. For changed formulae and casks, make sure you do the `brew audit` step after your changed formula/cask has been installed.

   For formulae:

   ```sh
   HOMEBREW_NO_INSTALL_FROM_API=1 brew install --build-from-source <CHANGED_FORMULA>
   brew test <CHANGED_FORMULA>
   brew audit --strict --online <CHANGED_FORMULA>
   ```

   For casks:

   ```sh
   HOMEBREW_NO_INSTALL_FROM_API=1 brew install --cask <CHANGED_CASK>
   brew uninstall --cask <CHANGED_CASK>
   brew audit --strict --online --cask <CHANGED_CASK>
   ```

6. [Make a separate commit](Formula-Cookbook.md#commit) for each changed formula with `git add` and `git commit`. Each formula's commits must be squashed.
   * Please note that our required commit message format for simple version updates is "`<FORMULA_NAME> <NEW_VERSION>`", e.g. "`source-highlight 3.1.8`".
7. Upload your branch of new commits to your fork:

   ```sh
   git push --set-upstream <YOUR_USERNAME> <YOUR_BRANCH_NAME>
   ```

8. Go to the relevant repository (e.g. <https://github.com/Homebrew/brew>, <https://github.com/Homebrew/homebrew-core>, etc.) and create a pull request to request review and merging of the commits from your pushed branch. Explain why the change is needed and, if fixing a bug, how to reproduce the bug. Make sure you have done each step in the checklist that appears in your new PR.
9. Await feedback or a merge from Homebrew's maintainers. We typically respond to all PRs within a couple days, but it may take up to a week, depending on the maintainers' workload.

Thank you!

### "Artificial Intelligence"/Large Language Model (AI/LLM) usage

We allow you to create issues and pull requests with AI/LLM with the following requirements:

* You must disclose in the initial issue or pull request that you used AI/LLM and what tool/model/etc. you used.
* You must review all AI/LLM generated code, prose, etc. content before you ask anyone in Homebrew to review it for you.
* You must be able to address all pull request review comments, manually if the AI/LLM cannot do so for you.
* If you reach the point where you feel unwilling or unable to do the above, please close your issue or pull request.

## Following up

To respond well to feedback:

1. Ask for clarification of anything you don't understand and for help with anything you don't know how to do.
2. Post a comment on your pull request if you've provided all the requested changes/information and it hasn't been merged after a week.
   Post a comment on your pull request if you're stuck and need help.
   A `needs response` label on a PR means that the Homebrew maintainers need you to respond to previous comments.
3. Keep discussion in the pull request unless requested otherwise (i.e. do not email maintainers privately).
4. Do not continue discussion in closed pull requests.
5. Do not argue with Homebrew maintainers. You may disagree but unless they change their mind, please implement what they request. Ultimately they control what is included in Homebrew, as they have to support any changes that are made.

To make changes based on feedback:

1. Check out your branch again:

   ```sh
   git checkout <YOUR_BRANCH_NAME>
   ```

2. Make any requested changes and commit them with `git add` and `git commit`.
3. Squash new commits into one commit per formula:

   ```sh
   git rebase --interactive origin/HEAD
   ```

   If you are working on a PR for a single formula, `git commit --amend` is a convenient way of keeping your commits squashed as you go.
4. Push to your remote fork's branch and the pull request:

   ```sh
   git push --force
   ```

Once all feedback has been addressed and if it's a change we want to include (we include most changes), then we'll add your changes to Homebrew. Note that the PR status may show up as "Closed" instead of "Merged" because of the way we merge contributions. Don't worry: you will still get author credit in the actual merged commit.

Well done, you are now a Homebrew contributor!
