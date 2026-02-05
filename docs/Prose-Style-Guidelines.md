---
last_review_date: 2025-05-22
---

# Prose Style Guidelines

<!-- vale off -->
<!-- Disable vale linting for the whole of the style guide, because it contains deliberately bad examples. -->

This is a set of style and usage guidelines for Homebrew's prose documentation aimed at users, contributors, and maintainers (as opposed to executable computer code). It applies to documents like those in `docs` in the `Homebrew/brew` repository, announcement emails, and other communications with the Homebrew community.

This does not apply to any Ruby or other computer code. You can use it to inform technical documentation extracted from computer code, like embedded man pages, but it's just a suggestion there.

## Goals and audience

The primary goal of Homebrew's prose documents is communicating with its community of users and contributors. "Users" includes "contributors" here; wherever you see "users" you can substitute "users and contributors".

Understandability is more important than any particular style guideline.

Users take precedence over maintainers, except in specifically maintainer-focused documents.

Homebrew's audience includes users with a wide range of education and experience, and users for whom English is not a native language. We aim to support as many of those users as feasible.

We strive for "correct" but not "fancy" usage. Think newspaper article, not academic paper.

This is a set of guidelines to be applied using human judgement, not a set of hard and fast rules. It is more like [Garner's Modern American Usage](https://en.wikipedia.org/wiki/Garner's_Modern_American_Usage) and less like the [Ruby Style Guide](https://github.com/rubocop-hq/ruby-style-guide#the-ruby-style-guide). All guidelines here are open to interpretation and discussion. 100% conformance to these guidelines is *not* a goal.

The intent of this document is to help authors make decisions about clarity, style, and consistency. It is not to help settle arguments about who knows English better. Don't use this document to be a jerk.

## Guidelines

We prefer:

### Style and usage

* British/Commonwealth English over American English, in general
* "e.g." and "i.e.": Go ahead and use "e.g." or "i.e." instead of spelling them out. Don't worry about putting a comma after them.
  * "e.g." means "for example"; "i.e." means "that is"
* Offset nontrivial subordinate clauses with commas

### Personal pronouns

* We respect all people's choice of personal pronouns
* Singular "they" when someone's gender is unknown
* Avoid gender-specific language when not necessary

### Structure and markup

* Title Case in `h1` headings; sentence case in all other headings
* Periods at the ends of list items where most items in that list are complete sentences
* More generally, parallel list item structure
* Capitalise all list items if you want, even if they're not complete sentences; just be consistent within each list, and preferably, throughout the whole page
* Use a subordinate list item instead of dropping a multi-sentence paragraph-long item into a list of sentence fragments
* Prefer Markdown over other markup formats unless their specific features are needed
  * GitHub Flavoured Markdown. GitHub's implementation is the standard, period.
* Link to other documentation pages with relative links to the Markdown filename rather than the full URL
  * e.g. `FAQ.md` instead of `https://docs.brew.sh/FAQ`

### Typographical conventions

* Literal text in commands and code is styled in `fixed width font`
* Placeholders inside code snippets are marked up with `<...>` brackets
  * e.g. `git remote add <my-user-name> https://github.com/<my-user-name>/homebrew-core.git`
* Names of commands like `git` and `brew` are styled in `fixed width font`
* No "$" with environment variables mentioned outside code snippets
  * e.g. "Set `BLAH` to 5", not "Set `$BLAH` to 5"
* One space after periods, not two
* Capitalised proper nouns
* We do not defer to extensive nonstandard capitalisation, typesetting, or other styling of brand names, aside from the normal capitalisation of proper nouns and simple internal capitalisation
* No "TM", &trade;, <sup>SM</sup>, &copy;, &reg;, or other explicit indicators of rights ownership or trademarks; we take these as understood when the brand name is mentioned
* Tap names like `homebrew/core` are styled in `fixed width font`. Repository names may be styled in either fixed width font like "`Homebrew/homebrew-core`", as links like "[Homebrew/homebrew-core](https://github.com/homebrew/homebrew-core)", or regular text like "Homebrew/homebrew-core", based on which looks best for a given use.
  * But be consistent within a single document
  * Capitalise repository names to match the user and repository names on GitHub. Keep tap names in lower case.
* Commas
  * No Oxford commas
  * Prefer a "loose" comma style: "when in doubt, leave it out" unless needed for clarity

### Terminology, words, and word styling

* "pull request", not "Pull Request"
* "check out" is the verb; "checkout" is the noun
* Spell out certain technical words
  * "repository", not "repo"
  * When abbreviating, introduce the abbreviation with the first usage in any document
* Some abbreviations (near-universally understood among our user base) are fine, though.
  * "Mac" is fine; "Macintosh" isn't necessary
* "macOS" for all versions, "OS X" or "Mac OS X" when describing specific older versions
* "RuboCop", not "Rubocop"
* A pull request is made "on" a repository; that repository is "at" a URL

## How to use these guidelines

Refer to these guidelines to make decisions about style and usage in your own writing for Homebrew documents and communication.

PRs that fix style and usage throughout a document or multiple documents are okay and encouraged. PRs for just one or two style changes are a bit much.

Giving style and usage feedback on a PR or commit that involves documents is okay and encouraged. But keep in mind that these are just guidelines, and for any change, the author may have made a deliberate choice to break these rules in the interest of understandability or aesthetics.

<!-- vale on -->
