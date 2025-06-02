---
last_review_date: "1970-01-01"
---

# Adding Software to Homebrew

Is your favourite software missing from Homebrew? Then you're the perfect person to resolve this problem.

If you want to add software that is either closed source or a GUI-only program, you will want to follow the guide for [Casks](#casks). Otherwise follow the guide for [Formulae](#formulae) (see also: [Homebrew Terminology](Formula-Cookbook.md#homebrew-terminology)).

Before you start, please check the open pull requests for [Homebrew/homebrew-core](https://github.com/Homebrew/homebrew-core/pulls) or [Homebrew/homebrew-cask](https://github.com/Homebrew/homebrew-cask/pulls) to make sure no one else beat you to the punch.

Next, you will want to go through the [Acceptable Formulae](Acceptable-Formulae.md) or [Acceptable Casks](Acceptable-Casks.md) documentation to determine if the software is an appropriate addition to Homebrew. If you are creating a formula for an alternative version of software already in Homebrew (e.g. a major/minor version that differs significantly from the existing version), be sure to read the [Versions](Versions.md) documentation to understand versioned formulae requirements.

If everything checks out, you're ready to get started on a new formula!

## Formulae

### Writing the formula

1. It's a good idea to find existing formulae in Homebrew that have similarities to the software you want to add. This will help you to understand how specific languages, build methods, etc. are typically handled. Start by tapping `homebrew/core`: first set `HOMEBREW_NO_INSTALL_FROM_API=1` in your shell environment, then run `brew tap --force homebrew/core` to clone the `homebrew/core` tap to the path returned by `brew --repository homebrew/core`.

1. If you're starting from scratch, you can use the [`brew create` command](Manpage.md#create-options-url) to produce a basic version of your formula. This command accepts a number of options and you may be able to save yourself some work by using an appropriate template option like `--python`.

1. You will now have to develop the boilerplate code from `brew create` into a full-fledged formula. Your main references will be the [Formula Cookbook](Formula-Cookbook.md), similar formulae in Homebrew, and the upstream documentation for your chosen software. Be sure to also take note of the Homebrew documentation for writing [Python](Python-for-Formula-Authors.md) and [Node](Node-for-Formula-Authors.md) formulae, if applicable.

1. Make sure you write a good test as part of your formula. Refer to the [Add a test to the formula](Formula-Cookbook.md#add-a-test-to-the-formula) section of the Cookbook for help with this.

1. Try installing your formula using `brew install --build-from-source <formula>`, where *\<formula>* is the name of your formula. If any errors occur, correct your formula and attempt to install it again. The formula installation should finish without errors by the end of this step.

If you're stuck, ask for help on GitHub or the [Homebrew discussion forum](https://github.com/orgs/Homebrew/discussions). The maintainers are very happy to help but we also like to see that you've put effort into trying to find a solution first.

### Testing and auditing the formula

1. Run `brew audit --strict --new --online <formula>` with your formula. If any errors occur, correct your formula and run the audit again. The audit should finish without any errors by the end of this step.

1. Run your formula's test using `brew test <formula>`. The test should finish without any errors.

### Submitting the formula

You're finally ready to submit your formula to the [homebrew-core](https://github.com/Homebrew/homebrew-core) repository. If you haven't done this before, you can refer to the [How to Open a Homebrew Pull Request](How-To-Open-a-Homebrew-Pull-Request.md#formulae-related-pull-request) documentation for help. Maintainers will review the pull request and provide feedback about any areas that need to be addressed before the formula can be added to Homebrew.

If you've made it this far, congratulations on submitting a Homebrew formula! We appreciate the hard work you put into this and you can take satisfaction in knowing that your work may benefit other Homebrew users as well.

## Casks

**Note:** Before taking the time to craft a new cask:

* make sure it can be accepted by checking the [Rejected Casks FAQ](Acceptable-Casks.md#rejected-casks), and
* check that the cask was not [already refused](https://github.com/Homebrew/homebrew-cask/search?q=is%3Aclosed&type=Issues).

### Writing the cask

Making a new cask is easy. Follow the directions in [How to Open a Homebrew Pull Request](How-To-Open-a-Homebrew-Pull-Request.md#cask-related-pull-request) to begin.

#### Examples

Here’s a cask for `dixa` as an example. Note the `verified` parameter below the `url`, which is needed when [the url and homepage hostnames differ](Cask-Cookbook.md#when-url-and-homepage-domains-differ-add-verified).

```ruby
cask "dixa" do
  version "4.0.12"
  sha256 "a4e1a30d074e724ba24e9e2674a72bc4050f00161fb7dc23295a2c189ecda5bb"

  url "https://github.com/dixahq/dixa-desktop-app-release/releases/download/v#{version}/dixa-#{version}.dmg",
      verified: "github.com/dixahq/dixa-desktop-app-release/"
  name "Dixa"
  desc "Customer service platform"
  homepage "https://dixa.com/"

  livecheck do
    url :url
    strategy :github_latest
  end

  app "Dixa.app"

  zap trash: [
    "~/Library/Application Support/Dixa",
    "~/Library/Logs/Dixa",
    "~/Library/Preferences/dixa.plist",
    "~/Library/Saved Application State/dixa.savedState",
  ]
end
```

And here is one for `pomello`. Note that it has an unversioned download (the download `url` does not contain the version number, unlike the example above). It also suppresses the checksum with `sha256 :no_check`, which is necessary because since the download `url` does not contain the version number, its checksum will change when a new version is made available.

```ruby
cask "pomello" do
  version "0.10.17"
  sha256 :no_check

  url "https://pomelloapp.com/download/mac/latest"
  name "Pomello"
  desc "Turns your Trello cards into Pomodoro tasks"
  homepage "https://pomelloapp.com/"

  livecheck do
    url :url
    strategy :header_match
  end

  app "Pomello.app"

  zap trash: [
    "~/Library/Application Support/com.apple.sharedfilelist/com.apple.LSSharedFileList.ApplicationRecentDocuments/com.tinynudge.pomello.*",
    "~/Library/Application Support/Pomello",
    "~/Library/Caches/com.tinynudge.pomello",
    "~/Library/Caches/com.tinynudge.pomello.ShipIt",
    "~/Library/HTTPStorages/com.tinynudge.pomello",
    "~/Library/Preferences/com.tinynudge.pomello.plist",
    "~/Library/Saved Application State/com.tinynudge.pomello.savedState",
  ]
end
```

Here is a last example for `fabfilter-one`, which uses a `pkg` installer to install the application instead of a stand-alone application bundle (`.app`). Note the [`uninstall pkgutil` stanza](Cask-Cookbook.md#uninstall-pkgutil), which is needed to uninstall all files that were installed using the installer.

You will also see how to adapt `version` to the download `url`. Use [our custom `version` methods](Cask-Cookbook.md#version-methods) to do so, resorting to the standard [Ruby String methods](https://ruby-doc.org/core/String.html) when they don’t suffice.

```ruby
cask "fabfilter-one" do
  version "3.37"
  sha256 "4059594580e365237ded16a213d8d549cbb01c4b8bad80895c61f44bcff7eb68"

  url "https://download.fabfilter.com/ffone#{version.no_dots}.dmg"
  name "FabFilter One"
  desc "Synthesizer plug-in"
  homepage "https://www.fabfilter.com/products/volcano-2-powerful-filter-plug-in"

  livecheck do
    url "https://www.fabfilter.com/download"
    strategy :page_match do |page|
      match = page.match(/ffone(\d)(\d+)\.dmg/i)
      next if match.blank?

      "#{match[1]}.#{match[2]}"
    end
  end

  depends_on macos: ">= :sierra"

  pkg "FabFilter One #{version} Installer.pkg"

  uninstall pkgutil: "com.fabfilter.One.#{version.major}"

  # No zap stanza required
end
```

#### Generating a token for the cask

The cask **token** is the mnemonic string people will use to interact with the cask via `brew install`, etc. The name of the cask **file** is simply the token with the extension `.rb` appended.

The easiest way to generate a token for a cask is to run `generate_cask_token`:

```bash
$(brew --repository homebrew/cask)/developer/bin/generate_cask_token "/full/path/to/new/software.app"
```

If the software you wish to create a cask for is not installed, or does not have an associated App bundle, just give the full proper name of the software instead of a pathname:

```bash
$(brew --repository homebrew/cask)/developer/bin/generate_cask_token "Google Chrome"
```

If the `generate_cask_token` script does not work for you, see [Cask Token Details](#cask-token-details).

#### Creating the cask file

Once you know the token, create your cask with the `brew create --cask` command:

```bash
brew create --cask download-url --set-name my-new-cask
```

This will open `EDITOR` with a template for your new cask, to be stored in the file `my-new-cask.rb`.

#### Cask stanzas

Fill in the following stanzas for your cask:

| name               | value       |
| ------------------ | ----------- |
| `version`          | application version |
| `sha256`           | SHA-256 checksum of the file downloaded from `url`, calculated by the command `shasum -a 256 <file>`. Can be suppressed by using the special value `:no_check`. (see [`sha256` Stanza Details](Cask-Cookbook.md#stanza-sha256)) |
| `url`              | URL to the `.dmg`/`.zip`/`.tgz`/`.tbz2` file that contains the application.<br />A [`verified` parameter](Cask-Cookbook.md#when-url-and-homepage-domains-differ-add-verified) must be added if the hostnames in the `url` and `homepage` stanzas differ. [Block syntax](Cask-Cookbook.md#using-a-block-to-defer-code-execution) is available for URLs that change on every visit. |
| `name`             | the full and proper name defined by the vendor, and any useful alternate names (see [`name` Stanza Details](Cask-Cookbook.md#stanza-name)) |
| `desc`             | one-line description of the software (see [`desc` Stanza Details](Cask-Cookbook.md#stanza-desc)) |
| `homepage`         | application homepage; used for the `brew home` command |
| `livecheck`        | Ruby block describing how to find updates for this cask (see [`livecheck` Stanza Details](Cask-Cookbook.md#stanza-livecheck)) |
| `app`              | relative path to an `.app` bundle that should be moved into the `/Applications` folder on installation (see [`app` Stanza Details](Cask-Cookbook.md#stanza-app)) |
| `zap`              | additional procedures for a more complete uninstall, including configuration files and shared resources (see [`zap` Stanza Details](Cask-Cookbook.md#stanza-zap)) |

Other commonly used stanzas are:

| name               | value       |
| ------------------ | ----------- |
| `pkg`              | relative path to a `.pkg` file containing the distribution (see [`pkg` Stanza Details](Cask-Cookbook.md#stanza-pkg)) |
| `caveats`          | string or Ruby block providing the user with cask-specific information at install time (see [`caveats` Stanza Details](Cask-Cookbook.md#stanza-caveats)) |
| `uninstall`        | procedures to uninstall a cask; optional unless the `pkg` stanza is used (see [`uninstall` Stanza Details](Cask-Cookbook.md#stanza-uninstall)) |

Additional [`artifact` stanzas](Cask-Cookbook.md#at-least-one-artifact-stanza-is-also-required) may be needed for special use cases. Even more special-use stanzas are listed at [Optional Stanzas](Cask-Cookbook.md#optional-stanzas).

#### Cask token details

If a token conflicts with an already-existing cask, authors should manually make the new token unique by prepending the vendor name. Example: [unison.rb](https://github.com/Homebrew/homebrew-cask/blob/HEAD/Casks/u/unison.rb) and [panic-unison.rb](https://github.com/Homebrew/homebrew-cask/blob/HEAD/Casks/p/panic-unison.rb).

If possible, avoid creating tokens that differ only by the placement of hyphens.

To generate a token manually, or to learn about exceptions for unusual cases, see the [Token Reference](Cask-Cookbook.md#token-reference).

#### Archives with subfolders

When a downloaded archive expands to a subfolder, the subfolder name must be included in the `app` value.

Example:

1. Simple Floating Clock is downloaded to the file `sfc.zip`.
1. `sfc.zip` unzips to a folder called `Simple Floating Clock`.
1. The folder `Simple Floating Clock` contains the application `SimpleFloatingClock.app`.
1. So, the `app` stanza should include the subfolder as a relative path:

   ```ruby
app "Simple Floating Clock/SimpleFloatingClock.app"
   ```

### Testing and auditing the cask

Give it a shot with:

```bash
export HOMEBREW_NO_AUTO_UPDATE=1
export HOMEBREW_NO_INSTALL_FROM_API=1
brew install my-new-cask
```

Did it install? If something went wrong, edit your cask with `brew edit my-new-cask` to fix it.

Test also if the uninstall works successfully:

```bash
brew uninstall my-new-cask
```

If everything looks good, you’ll also want to make sure your cask passes audit with:

```bash
brew audit --new --cask my-new-cask
```

You should also check stylistic details with `brew style`:

```bash
brew style --fix my-new-cask
```

Keep in mind that all these checks will be made when you submit your PR, so by doing them in advance you’re saving everyone a lot of time and trouble.

If your application and Homebrew Cask do not work well together, feel free to [file an issue](https://github.com/Homebrew/homebrew-cask#reporting-bugs) after checking out open issues.

### Submitting the cask

#### Finding a home for your cask

See the [Acceptable Casks documentation](Acceptable-Casks.md#finding-a-home-for-your-cask).

Hop into your tap and check to make sure your new cask is there:

```console
$ cd "$(brew --repository)"/Library/Taps/homebrew/homebrew-cask
$ git status
On branch master
Untracked files:
  (use "git add <file>..." to include in what will be committed)
        Casks/m/my-new-cask.rb
```

So far, so good. Now make a feature branch `my-new-cask-branch` that you’ll use in your pull request:

```console
$ git checkout -b my-new-cask-branch
Switched to a new branch 'my-new-cask-branch'
```

Stage your cask with:

```bash
git add Casks/m/my-new-cask.rb
```

You can view the changes that are to be committed with:

```bash
git diff --cached
```

Commit your changes with:

```bash
git commit -v
```

#### Commit messages

For any Git project, some good rules for commit messages are:

* The first line is the commit summary, 50 characters or less,
* Followed by an empty line,
* Followed by an explanation of the commit, wrapped to 72 characters.

See [A Note About Git Commit Messages](https://tbaggery.com/2008/04/19/a-note-about-git-commit-messages.html) for more.

The first line of a commit message becomes the **title** of a pull request on GitHub, like the subject line of an email. Including the key info in the first line will help us respond faster to your pull request.

For cask commits in the Homebrew Cask project, we like to include the application name, version number, and purpose of the commit in the first line.

Examples of good, clear commit summaries:

* `transmission 1.0 (new cask)`
* `transmission 2.82`
* `transmission: fix checksum`
* `codebox latest (new cask)`

Examples of difficult, unclear commit summaries:

* `Upgrade to v2.82`
* `Checksum was bad`

#### Pushing

Push your changes on the branch `my-new-cask-branch` to your GitHub account:

```bash
git push {{my-github-username}} my-new-cask-branch
```

If you are using [GitHub two-factor authentication](https://docs.github.com/en/authentication/securing-your-account-with-two-factor-authentication-2fa) and have set your remote repository as HTTPS you will need to [set up a personal access token](https://docs.github.com/en/repositories/creating-and-managing-repositories/troubleshooting-cloning-errors#provide-an-access-token) and use that instead of your password.

#### Filing a pull request on GitHub

##### a) use suggestion from `git push`

The `git push` command prints a suggestion for how to create a pull request:

    remote: Create a pull request for 'new-cask-cask' on GitHub by visiting:
    remote:      https://github.com/{{my-github-username}}/homebrew-cask/pull/new/my-new-cask-branch

##### b) use suggestion from GitHub's website

Now go to the [`homebrew-cask` GitHub repository](https://github.com/Homebrew/homebrew-cask). GitHub will often show your `my-new-cask-branch` branch with a handy button to `Compare & pull request`.

##### c) manually create a pull request on GitHub

Otherwise, click the `Contribute > Open pull request` button and choose to `compare across forks`. The base fork should be `Homebrew/homebrew-cask @ master`, and the head fork should be `my-github-username/homebrew-cask @ my-new-cask-branch`. You can also add any further comments to your pull request at this stage.

##### Congratulations!

You are done now, and your cask should be pulled in or otherwise noticed in a while. If a maintainer suggests some changes, just make them on the `my-new-cask-branch` branch locally and [push](#pushing).

### Cleaning up

After your pull request is submitted, you should get yourself back onto `master`, so that `brew update` will pull down new casks properly:

```bash
cd "$(brew --repository)"/Library/Taps/homebrew/homebrew-cask
git checkout master
```

If earlier you set the variable `HOMEBREW_NO_AUTO_UPDATE` and `HOMEBREW_NO_INSTALL_FROM_API` then clean it up with:

```bash
unset HOMEBREW_NO_AUTO_UPDATE
unset HOMEBREW_NO_INSTALL_FROM_API
```
