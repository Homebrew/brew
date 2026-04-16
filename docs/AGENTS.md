---
last_review_date: "2026-04-05"
---

# Agent Instructions for Homebrew/brew docs

These instructions apply when working in `docs/`.

## Tooling

- Use the system Homebrew `brew bundle exec ...` workflow from this directory
  rather than `./bin/brew` for the docs site toolchain.
- Set `HOMEBREW_NO_AUTO_UPDATE=1` for docs verification commands to match the
  CI workflow.
- Install or refresh the docs Ruby environment with
  `brew bundle exec bundle install`.

## Verification

When you change docs, run the relevant checks from `.github/workflows/docs.yml`
and `docs/Rakefile`.

At a minimum, from `docs/` run:

- `HOMEBREW_NO_AUTO_UPDATE=1 brew bundle exec bundle install`
- `HOMEBREW_NO_AUTO_UPDATE=1 brew bundle exec bin/jekyll build`
- `HOMEBREW_NO_AUTO_UPDATE=1 brew bundle exec bundle exec rake lint`
- `HOMEBREW_NO_AUTO_UPDATE=1 brew bundle exec bundle exec rake test`

Also run these from the repository root when docs content changes:

- `HOMEBREW_NO_AUTO_UPDATE=1 vale docs/`
- `HOMEBREW_NO_AUTO_UPDATE=1 brew style docs`

## Notes

- Prefer `brew bundle exec bin/jekyll build` explicitly for site builds.
- Prefer `brew bundle exec bundle exec rake ...` for Rake tasks so bundled
  executables such as `mdl` are available to the task.
- For `Homebrew/brew`, the docs CI also runs
  `brew generate-man-completions --no-exit-code` before docs checks. Run it
  when your docs change depends on updated generated manpages or completions.
