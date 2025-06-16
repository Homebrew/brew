# Documentation defined in Library/Homebrew/dev-cmd/rubocop.rb

# HOMEBREW_LIBRARY is from the user environment.
# HOMEBREW_RUBY_PATH is set by utils/ruby.sh
# HOMEBREW_BREW_FILE is set by extend/ENV/super.rb
# shellcheck disable=SC2154
homebrew-rubocop() {
  source "${HOMEBREW_LIBRARY}/Homebrew/utils/ruby.sh"
  setup-ruby-path
  setup-gem-home-bundle-gemfile

  BUNDLE_WITH="style"
  export BUNDLE_WITH

  if ! bundle check &>/dev/null
  then
    "${HOMEBREW_BREW_FILE}" install-bundler-gems --add-groups="${BUNDLE_WITH}"
  fi

  export PATH="${GEM_HOME}/bin:${PATH}"

  RUBOCOP="${HOMEBREW_LIBRARY}/Homebrew/utils/rubocop.rb"
  exec "${HOMEBREW_RUBY_PATH}" "${RUBOCOP}" "$@"
}
