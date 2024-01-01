#:  * `setup-ruby`
#:
#:  Installs and configures Homebrew's Ruby.
#:

# HOMEBREW_LIBRARY is from the user environment.
# HOMEBREW_RUBY_PATH is set by utils/ruby.sh
# RUBY_DISABLE_OPTIONS is set by brew.sh
# HOMEBREW_BREW_FILE is set by extend/ENV/super.rb
# shellcheck disable=SC2154
homebrew-setup-ruby() {
  source "${HOMEBREW_LIBRARY}/Homebrew/utils/ruby.sh"
  setup-ruby-path

  if [[ -z "${HOMEBREW_DEVELOPER}" && -z "${HOMEBREW_RUBY3}" ]]
  then
    return
  fi

  GEM_VERSION="$("${HOMEBREW_RUBY_PATH}" "${HOMEBREW_RUBY_DISABLE_OPTIONS}" -rrbconfig -e 'puts RbConfig::CONFIG["ruby_version"]')"
  GEM_HOME="${HOMEBREW_LIBRARY}/Homebrew/vendor/bundle/ruby/${GEM_VERSION}"
  BUNDLE_GEMFILE="${HOMEBREW_LIBRARY}/Homebrew/Gemfile"

  export GEM_HOME
  export BUNDLE_GEMFILE

  if ! bundle check &>/dev/null
  then
    "${HOMEBREW_BREW_FILE}" install-bundler-gems
  fi
}
