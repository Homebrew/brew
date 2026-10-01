---
last_review_date: "2026-06-08"
---

# Homebrew Documentation

These are the source files for the [Homebrew documentation site](https://docs.brew.sh/).

A [GitHub Action](https://github.com/Homebrew/brew/blob/HEAD/.github/workflows/docs.yml) is run to validate each change before the site is deployed to GitHub Pages.

## Usage

Open <https://docs.brew.sh> in your web browser.

To instead generate the site locally, available on <http://localhost:4000>, run:

```bash
cd $(brew --repository)/docs
brew bundle --install exec -- bundle install
bin/jekyll serve
```
