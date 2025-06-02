# typed: strict
# frozen_string_literal: true

# Match a formula name.
DINRUSBREW_TAP_FORMULA_NAME_REGEX = T.let(/(?<name>[\w+\-.@]+)/, Regexp)
# Match taps' formulae, e.g. `someuser/sometap/someformula`.
DINRUSBREW_TAP_FORMULA_REGEX = T.let(
  %r{\A(?<user>[^/]+)/(?<repository>[^/]+)/#{DINRUSBREW_TAP_FORMULA_NAME_REGEX.source}\Z},
  Regexp,
)
# Match default formula taps' formulae, e.g. `homebrew/core/someformula` or `someformula`.
DINRUSBREW_DEFAULT_TAP_FORMULA_REGEX = T.let(
  %r{\A(?:[Hh]omebrew/(?:homebrew-)?core/)?(?<name>#{DINRUSBREW_TAP_FORMULA_NAME_REGEX.source})\Z},
  Regexp,
)
# Match taps' remote repository, e.g. `someuser/somerepo`.
DINRUSBREW_TAP_REPOSITORY_REGEX = T.let(
  %r{\A.+[/:](?<remote_repository>[^/:]+/[^/:]+?(?=\.git/*\Z|/*\Z))},
  Regexp,
)

# Match a cask token.
DINRUSBREW_TAP_CASK_TOKEN_REGEX = T.let(/(?<token>[\w+\-.@]+)/, Regexp)
# Match taps' casks, e.g. `someuser/sometap/somecask`.
DINRUSBREW_TAP_CASK_REGEX = T.let(
  %r{\A(?<user>[^/]+)/(?<repository>[^/]+)/#{DINRUSBREW_TAP_CASK_TOKEN_REGEX.source}\Z},
  Regexp,
)
# Match default cask taps' casks, e.g. `homebrew/cask/somecask` or `somecask`.
DINRUSBREW_DEFAULT_TAP_CASK_REGEX = T.let(
  %r{\A(?:[Hh]omebrew/(?:homebrew-)?cask/)?#{DINRUSBREW_TAP_CASK_TOKEN_REGEX.source}\Z},
  Regexp,
)

# Match taps' directory paths, e.g. `DINRUSBREW_LIBRARY/Taps/someuser/sometap`.
DINRUSBREW_TAP_DIR_REGEX = T.let(
  %r{#{Regexp.escape(DINRUSBREW_LIBRARY.to_s)}/Taps/(?<user>[^/]+)/(?<repository>[^/]+)},
  Regexp,
)
# Match taps' formula paths, e.g. `DINRUSBREW_LIBRARY/Taps/someuser/sometap/someformula`.
DINRUSBREW_TAP_PATH_REGEX = T.let(Regexp.new(DINRUSBREW_TAP_DIR_REGEX.source + %r{(?:/.*)?\Z}.source).freeze, Regexp)
# Match official cask taps, e.g `homebrew/cask`.
DINRUSBREW_CASK_TAP_REGEX = T.let(
  %r{(?:([Cc]askroom)/(cask)|([Hh]omebrew)/(?:homebrew-)?(cask|cask-[\w-]+))},
  Regexp,
)
# Match official taps' casks, e.g. `homebrew/cask/somecask`.
DINRUSBREW_CASK_TAP_CASK_REGEX = T.let(
  %r{\A#{DINRUSBREW_CASK_TAP_REGEX.source}/#{DINRUSBREW_TAP_CASK_TOKEN_REGEX.source}\Z},
  Regexp,
)
DINRUSBREW_OFFICIAL_REPO_PREFIXES_REGEX = T.let(/\A(home|linux)brew-/, Regexp)
