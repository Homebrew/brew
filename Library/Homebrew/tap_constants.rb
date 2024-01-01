# typed: strict
# frozen_string_literal: true

# Match taps' formulae, e.g. `someuser/sometap/someformula`
HOMEBREW_TAP_FORMULA_REGEX = T.let(%r{^([\w-]+)/([\w-]+)/([\w+-.@]+)$}.freeze, Regexp)
# Match taps' casks, e.g. `someuser/sometap/somecask`
HOMEBREW_TAP_CASK_REGEX = T.let(%r{^([\w-]+)/([\w-]+)/([a-z0-9\-_]+)$}.freeze, Regexp)
# Match main cask taps' casks, e.g. `homebrew/cask/somecask` or `somecask`
HOMEBREW_MAIN_TAP_CASK_REGEX = T.let(%r{^([Hh]omebrew/(?:homebrew-)?cask/)?[a-z0-9\-_]+$}.freeze, Regexp)
# Match taps' directory paths, e.g. `HOMEBREW_LIBRARY/Taps/someuser/sometap`
HOMEBREW_TAP_DIR_REGEX = T.let(
  %r{#{Regexp.escape(HOMEBREW_LIBRARY.to_s)}/Taps/(?<user>[\w-]+)/(?<repo>[\w-]+)}.freeze, Regexp
)
# Match taps' formula paths, e.g. `HOMEBREW_LIBRARY/Taps/someuser/sometap/someformula`
HOMEBREW_TAP_PATH_REGEX = T.let(Regexp.new(HOMEBREW_TAP_DIR_REGEX.source + %r{(?:/.*)?$}.source).freeze, Regexp)
# Match official taps' casks, e.g. `homebrew/cask/somecask or homebrew/cask-versions/somecask`
HOMEBREW_CASK_TAP_CASK_REGEX =
  T.let(%r{^(?:([Cc]askroom)/(cask|versions)|([Hh]omebrew)/(?:homebrew-)?(cask|cask-[\w-]+))/([\w+-.]+)$}.freeze,
        Regexp)
HOMEBREW_OFFICIAL_REPO_PREFIXES_REGEX = T.let(/^(home|linux)brew-/.freeze, Regexp)
