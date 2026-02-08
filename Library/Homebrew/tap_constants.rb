# typed: strict
# frozen_string_literal: true

# Match a formula name.
HOMEBREW_TAP_FORMULA_NAME_REGEX = /(?<name>[\w+\-.@]+)/
# Match taps' formulae, e.g. `someuser/sometap/someformula`.
HOMEBREW_TAP_FORMULA_REGEX =
  %r{\A(?<user>[^/]+)/(?<repository>[^/]+)/#{HOMEBREW_TAP_FORMULA_NAME_REGEX.source}\Z}
# Match default formula taps' formulae, e.g. `homebrew/core/someformula` or `someformula`.
HOMEBREW_DEFAULT_TAP_FORMULA_REGEX =
  %r{\A(?:[Hh]omebrew/(?:homebrew-)?core/)?(?<name>#{HOMEBREW_TAP_FORMULA_NAME_REGEX.source})\Z}
# Match taps' remote repository, e.g. `someuser/somerepo`.
HOMEBREW_TAP_REPOSITORY_REGEX =
  %r{\A.+[/:](?<remote_repository>[^/:]+/[^/:]+?(?=\.git/*\Z|/*\Z))}

# Match a cask token.
HOMEBREW_TAP_CASK_TOKEN_REGEX = /(?<token>[\w+\-.@]+)/
# Match taps' casks, e.g. `someuser/sometap/somecask`.
HOMEBREW_TAP_CASK_REGEX =
  %r{\A(?<user>[^/]+)/(?<repository>[^/]+)/#{HOMEBREW_TAP_CASK_TOKEN_REGEX.source}\Z}
# Match default cask taps' casks, e.g. `homebrew/cask/somecask` or `somecask`.
HOMEBREW_DEFAULT_TAP_CASK_REGEX =
  %r{\A(?:[Hh]omebrew/(?:homebrew-)?cask/)?#{HOMEBREW_TAP_CASK_TOKEN_REGEX.source}\Z}

# Match taps' directory paths, e.g. `HOMEBREW_LIBRARY/Taps/someuser/sometap`.
HOMEBREW_TAP_DIR_REGEX =
  %r{#{Regexp.escape(HOMEBREW_LIBRARY.to_s)}/Taps/(?<user>[^/]+)/(?<repository>[^/]+)}
# Match taps' formula paths, e.g. `HOMEBREW_LIBRARY/Taps/someuser/sometap/someformula`.
HOMEBREW_TAP_PATH_REGEX = T.let(Regexp.new(HOMEBREW_TAP_DIR_REGEX.source + %r{(?:/.*)?\Z}.source).freeze, Regexp)
# Match official cask taps, e.g `homebrew/cask`.
HOMEBREW_CASK_TAP_REGEX =
  %r{(?:([Cc]askroom)/(cask)|([Hh]omebrew)/(?:homebrew-)?(cask|cask-[\w-]+))}
# Match official taps' casks, e.g. `homebrew/cask/somecask`.
HOMEBREW_CASK_TAP_CASK_REGEX =
  %r{\A#{HOMEBREW_CASK_TAP_REGEX.source}/#{HOMEBREW_TAP_CASK_TOKEN_REGEX.source}\Z}
HOMEBREW_OFFICIAL_REPO_PREFIXES_REGEX = /\A(home|linux)brew-/
