---
last_review_date: "2026-06-10"
---

# Responsible AI Usage

This guide is for maintainers and contributors who use "Artificial Intelligence"/Large Language Model (AI/LLM) tools when working on Homebrew.
It expands on the [AI/LLM usage rules in our Contributing guide](https://github.com/Homebrew/brew/blob/HEAD/CONTRIBUTING.md) and the repository's `AGENTS.md` files with the principles we expect you to apply.

AI tools can make you faster.
They can also produce confidently plausible but wrong output.
These guidelines exist to make Homebrew better rather than shifting work and risk onto other maintainers.

## Human in the loop

AI is not responsible for its output: you are responsible for the output of the AI tools you use.
A pull request with your name on it is your work regardless of how much of it an AI wrote.

Verify AI output for correctness as you would that of an avatarless GitHub user with no previous contributions.
Read it, run it, test it and make sure you understand it.

Do not ask other humans to review your AI-generated code until you have reviewed it yourself.
This is already a requirement in our [Contributing guide](https://github.com/Homebrew/brew/blob/HEAD/CONTRIBUTING.md): you must review all AI/LLM-generated content before asking anyone in Homebrew to review it, and you must be able to address all review comments yourself even when the AI cannot.

As the [pull request template](https://github.com/Homebrew/brew/blob/HEAD/.github/PULL_REQUEST_TEMPLATE.md) sets out, disclose when AI was used to generate or assist with a pull request and explain how you verified the changes.

## Trust appropriately

AI tools should not be trusted much more or much less than those of humans.
Treat their output as a fallible first draft.

Verify output: it may be wrong.
Where Homebrew has fast feedback loops, use them.
Run `brew lgtm` (style, typechecking and tests) on every change, and read the diff with `git diff` to keep it small and intentional.

Review code, but don't try to make all of it perfectly match how you would have written it by hand.
Reviewing for correctness, security and maintainability matters far more than reviewing for personal style; our [Prose Style Guidelines](Prose-Style-Guidelines.md) and RuboCop already cover most of the latter.

Review mission-critical code, such as anything touching installation, security, package downloads or the `Formula` and `Cask` DSLs, much more carefully than a one-off script you run locally (which may not need much review at all).

## Use AI to improve AI

For maintainers or regular contributors, when prompting an AI requires repeated corrections and nudges to get Homebrew conventions right, ask it to write or update an `AGENTS.md` file so the next person and the next agent start from a better place.
We already keep instructions in `AGENTS.md` at the repository root.

It's acceptable to do this in the same pull request as your 3rd or later PR.
Don't do this on your first.

## Try things

LLM technologies are changing month by month.
Don't assume a tool you tried last month or last year is still as good or as bad as it was then.

AI use is a new skill and you will be bad at it initially.
Start on areas where the learning curve is lower and the impact is higher, get better and then take on harder problems.

Experiment with your setup as well as your prompts.
Running agents in sandboxed git worktrees, for example, lets you give them more autonomy while containing the blast radius; see Mike McQuaid's write-up of [sandboxed agent worktrees](https://mikemcquaid.com/sandboxed-agent-worktrees-my-coding-and-ai-setup-in-2026/) for one such approach.

## See also

- [Contributing to Homebrew](https://github.com/Homebrew/brew/blob/HEAD/CONTRIBUTING.md)
- [Maintainer Guidelines](Maintainer-Guidelines.md)
- [Maintainers: Avoiding Burnout](Maintainers-Avoiding-Burnout.md)
- [Prose Style Guidelines](Prose-Style-Guidelines.md)
