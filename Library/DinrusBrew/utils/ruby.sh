# When bumping, run `brew vendor-gems --update=--ruby`
# When bumping to a new major/minor version, also update the bounds in the Gemfile
# DINRUSBREW_LIBRARY set by bin/brew
# shellcheck disable=SC2154
export DINRUSBREW_REQUIRED_RUBY_VERSION="3.3"
DINRUSBREW_PORTABLE_RUBY_VERSION="$(cat "${DINRUSBREW_LIBRARY}/DinrusBrew/vendor/portable-ruby-version")"

# Disable Ruby options we don't need.
export DINRUSBREW_RUBY_DISABLE_OPTIONS="--disable=gems,rubyopt"

# DINRUSBREW_LIBRARY set by bin/brew
# shellcheck disable=SC2154
test_ruby() {
  if [[ ! -x "$1" ]]
  then
    return 1
  fi

  "$1" --enable-frozen-string-literal --disable=gems,did_you_mean,rubyopt \
    "${DINRUSBREW_LIBRARY}/DinrusBrew/utils/ruby_check_version_script.rb" \
    "${DINRUSBREW_REQUIRED_RUBY_VERSION}" 2>/dev/null
}

system_ruby_supported() {
  ([[ -z "${DINRUSBREW_MACOS}" ]] || can_use_ruby_from_path)
}

can_use_ruby_from_path() {
  if [[ -n "${DINRUSBREW_DEVELOPER}" || -n "${DINRUSBREW_TESTS}" ]] && [[ -n "${DINRUSBREW_USE_RUBY_FROM_PATH}" ]]
  then
    return 0
  fi

  return 1
}

find_first_valid_ruby() {
  local ruby_exec
  while IFS= read -r ruby_exec
  do
    if test_ruby "${ruby_exec}"
    then
      echo "${ruby_exec}"
      break
    fi
  done
}

# DINRUSBREW_PATH is set by global.rb
# shellcheck disable=SC2154
find_ruby() {
  local valid_ruby

  # Prioritise rubies from the filtered path (/usr/bin etc) unless explicitly overridden.
  if ! can_use_ruby_from_path
  then
    # function which() is set by brew.sh
    # it is aliased to `type -P`
    # shellcheck disable=SC2230
    valid_ruby=$(find_first_valid_ruby < <(which -a ruby))
  fi

  if [[ -z "${valid_ruby}" ]]
  then
    # Same as above
    # shellcheck disable=SC2230
    valid_ruby=$(find_first_valid_ruby < <(PATH="${DINRUSBREW_PATH}" which -a ruby))
  fi

  echo "${valid_ruby}"
}

# DINRUSBREW_FORCE_VENDOR_RUBY is from the user environment
# shellcheck disable=SC2154
need_vendored_ruby() {
  if [[ -n "${DINRUSBREW_FORCE_VENDOR_RUBY}" ]]
  then
    return 0
  elif system_ruby_supported && test_ruby "${DINRUSBREW_RUBY_PATH}"
  then
    return 1
  else
    return 0
  fi
}

# DINRUSBREW_LINUX is set by brew.sh
# shellcheck disable=SC2154
setup-ruby-path() {
  local vendor_dir
  local vendor_ruby_root
  local vendor_ruby_path
  local vendor_ruby_terminfo
  local vendor_ruby_current_version
  local ruby_exec
  local upgrade_fail
  local install_fail

  if [[ -n "${DINRUSBREW_MACOS}" ]]
  then
    upgrade_fail="Failed to upgrade DinrusBrew Portable Ruby!"
    install_fail="Failed to install DinrusBrew Portable Ruby (and your system version is too old)!"
  else
    local advice="
If there's no DinrusBrew Portable Ruby available for your processor:
- install Ruby ${DINRUSBREW_REQUIRED_RUBY_VERSION} with your system package manager (or rbenv/ruby-build)
- make it first in your PATH
- try again
"
    upgrade_fail="Failed to upgrade DinrusBrew Portable Ruby!${advice}"
    install_fail="Failed to install DinrusBrew Portable Ruby and cannot find another Ruby ${DINRUSBREW_REQUIRED_RUBY_VERSION}!${advice}"
  fi

  vendor_dir="${DINRUSBREW_LIBRARY}/DinrusBrew/vendor"
  vendor_ruby_root="${vendor_dir}/portable-ruby/current"
  vendor_ruby_path="${vendor_ruby_root}/bin/ruby"
  vendor_ruby_terminfo="${vendor_ruby_root}/share/terminfo"
  vendor_ruby_current_version="$(readlink "${vendor_ruby_root}")"

  unset DINRUSBREW_RUBY_PATH

  if [[ "${DINRUSBREW_COMMAND}" == "vendor-install" ]]
  then
    return 0
  fi

  if [[ -x "${vendor_ruby_path}" ]]
  then
    DINRUSBREW_RUBY_PATH="${vendor_ruby_path}"
    TERMINFO_DIRS="${vendor_ruby_terminfo}"
    if [[ "${vendor_ruby_current_version}" != "${DINRUSBREW_PORTABLE_RUBY_VERSION}" ]]
    then
      brew vendor-install ruby || odie "${upgrade_fail}"
    fi
  else
    if system_ruby_supported
    then
      DINRUSBREW_RUBY_PATH="$(find_ruby)"
    fi

    if need_vendored_ruby
    then
      brew vendor-install ruby || odie "${install_fail}"
      DINRUSBREW_RUBY_PATH="${vendor_ruby_path}"
      TERMINFO_DIRS="${vendor_ruby_terminfo}"
    fi
  fi

  export DINRUSBREW_RUBY_PATH
  [[ -n "${DINRUSBREW_LINUX}" && -n "${TERMINFO_DIRS}" ]] && export TERMINFO_DIRS
}

setup-gem-home-bundle-gemfile() {
  GEM_VERSION="$("${DINRUSBREW_RUBY_PATH}" "${DINRUSBREW_RUBY_DISABLE_OPTIONS}" "${DINRUSBREW_LIBRARY}/DinrusBrew/utils/ruby_sh/ruby_gem_version.rb")"
  GEM_HOME="${DINRUSBREW_LIBRARY}/DinrusBrew/vendor/bundle/ruby/${GEM_VERSION}"
  BUNDLE_GEMFILE="${DINRUSBREW_LIBRARY}/DinrusBrew/Gemfile"

  export GEM_HOME
  export BUNDLE_GEMFILE
}
