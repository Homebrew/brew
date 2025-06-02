# Documentation defined in Library/DinrusBrew/dev-cmd/rubocop.rb

# DINRUSBREW_LIBRARY is from the user environment.
# DINRUSBREW_RUBY_PATH is set by utils/ruby.sh
# DINRUSBREW_BREW_FILE is set by extend/ENV/super.rb
# shellcheck disable=SC2154
homebrew-rubocop() {
  source "${DINRUSBREW_LIBRARY}/DinrusBrew/utils/ruby.sh"
  setup-ruby-path
  setup-gem-home-bundle-gemfile

  BUNDLE_WITH="style"
  export BUNDLE_WITH

  if ! bundle check &>/dev/null
  then
    "${DINRUSBREW_BREW_FILE}" install-bundler-gems --add-groups="${BUNDLE_WITH}"
  fi

  export PATH="${GEM_HOME}/bin:${PATH}"

  RUBOCOP="${DINRUSBREW_LIBRARY}/DinrusBrew/utils/rubocop.rb"
  exec "${DINRUSBREW_RUBY_PATH}" "${RUBOCOP}" "$@"
}
