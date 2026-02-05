# When bumping, run `brew vendor-gems --update=--ruby`
# When bumping to a new major/minor version, also update the bounds in the Gemfile
# HOMEBREW_LIBRARY set by bin/brew
# shellcheck disable=SC2154
export HOMEBREW_REQUIRED_RUBY_VERSION="3.4"
HOMEBREW_PORTABLE_RUBY_VERSION="$(cat "${HOMEBREW_LIBRARY}/Homebrew/vendor/portable-ruby-version")"
export HOMEBREW_BUNDLER_VERSION="2.6.9"

# Disable Ruby options we don't need.
export HOMEBREW_RUBY_DISABLE_OPTIONS="--disable=gems,rubyopt"

# HOMEBREW_LIBRARY set by bin/brew
# shellcheck disable=SC2154
test_ruby() {
  if [[ ! -x "$1" ]]
  then
    return 1
  fi

  "$1" --enable-frozen-string-literal --disable=gems,did_you_mean,rubyopt \
    "${HOMEBREW_LIBRARY}/Homebrew/utils/ruby_check_version_script.rb" \
    "${HOMEBREW_REQUIRED_RUBY_VERSION}" 2>/dev/null
}

system_ruby_supported() {
  ([[ -z "${HOMEBREW_MACOS}" ]] || can_use_ruby_from_path)
}

can_use_ruby_from_path() {
  if [[ -n "${HOMEBREW_DEVELOPER}" || -n "${HOMEBREW_TESTS}" ]] && [[ -n "${HOMEBREW_USE_RUBY_FROM_PATH}" ]]
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

# HOMEBREW_PATH is set by global.rb
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
    valid_ruby=$(find_first_valid_ruby < <(PATH="${HOMEBREW_PATH}" which -a ruby))
  fi

  echo "${valid_ruby}"
}

# HOMEBREW_FORCE_VENDOR_RUBY is from the user environment
# shellcheck disable=SC2154
need_vendored_ruby() {
  if [[ -n "${HOMEBREW_FORCE_VENDOR_RUBY}" ]]
  then
    return 0
  elif system_ruby_supported && test_ruby "${HOMEBREW_RUBY_PATH}"
  then
    return 1
  else
    return 0
  fi
}

# HOMEBREW_LINUX is set by brew.sh
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

  if [[ -n "${HOMEBREW_MACOS}" ]]
  then
    upgrade_fail="Failed to upgrade Homebrew Portable Ruby!"
    install_fail="Failed to install Homebrew Portable Ruby (and your system version is too old)!"
  else
    local advice="
If there's no Homebrew Portable Ruby available for your processor:
- install Ruby ${HOMEBREW_REQUIRED_RUBY_VERSION} with your system package manager (or rbenv/ruby-build)
- make it first in your PATH
- try again
"
    upgrade_fail="Failed to upgrade Homebrew Portable Ruby!${advice}"
    install_fail="Failed to install Homebrew Portable Ruby and cannot find another Ruby ${HOMEBREW_REQUIRED_RUBY_VERSION}!${advice}"
  fi

  vendor_dir="${HOMEBREW_LIBRARY}/Homebrew/vendor"
  vendor_ruby_root="${vendor_dir}/portable-ruby/current"
  vendor_ruby_path="${vendor_ruby_root}/bin/ruby"
  vendor_ruby_terminfo="${vendor_ruby_root}/share/terminfo"
  vendor_ruby_current_version="$(readlink "${vendor_ruby_root}")"

  unset HOMEBREW_RUBY_PATH

  if [[ "${HOMEBREW_COMMAND}" == "vendor-install" ]]
  then
    return 0
  fi

  # Needed for `brew` and `odie`.
  source "${HOMEBREW_LIBRARY}/Homebrew/utils/helpers.sh"

  if [[ -x "${vendor_ruby_path}" ]]
  then
    HOMEBREW_RUBY_PATH="${vendor_ruby_path}"
    TERMINFO_DIRS="${vendor_ruby_terminfo}"
    if [[ "${vendor_ruby_current_version}" != "${HOMEBREW_PORTABLE_RUBY_VERSION}" ]]
    then
      brew vendor-install ruby || odie "${upgrade_fail}"
    fi
    HOMEBREW_BOOTSNAP_GEM_PATH="$(
      shopt -s nullglob
      echo "${vendor_ruby_root}"/lib/ruby/gems/*/gems/bootsnap-*/lib/bootsnap 2>/dev/null
    )"
  else
    if system_ruby_supported
    then
      HOMEBREW_RUBY_PATH="$(find_ruby)"
    fi

    if need_vendored_ruby
    then
      brew vendor-install ruby || odie "${install_fail}"
      HOMEBREW_RUBY_PATH="${vendor_ruby_path}"
      TERMINFO_DIRS="${vendor_ruby_terminfo}"

      if [[ -n "${HOMEBREW_DEVELOPER}" && -x "${vendor_ruby_path}" ]]
      then
        if [[ ! -f "${vendor_ruby_root}/bin/bundle" ]]
        then
          odie "Homebrew Portable Ruby is installed but bundle is not!"
        elif [[ ! -d "${vendor_ruby_root}/lib/ruby/gems/${HOMEBREW_REQUIRED_RUBY_VERSION}.0/gems/bundler-${HOMEBREW_BUNDLER_VERSION}" ]]
        then
          odie "Homebrew Portable Ruby is installed but bundler ${HOMEBREW_BUNDLER_VERSION} is not!"
        elif ! grep -q "  ${HOMEBREW_BUNDLER_VERSION}" "${HOMEBREW_LIBRARY}/Homebrew/Gemfile.lock"
        then
          odie "Homebrew Portable Ruby is installed but bundler ${HOMEBREW_BUNDLER_VERSION} is not in the Gemfile.lock!"
        fi
      fi
    fi
  fi

  homebrew_ruby_bin="$(dirname "${HOMEBREW_RUBY_PATH}")"
  if [[ ! -f "${homebrew_ruby_bin}/bundle" ]]
  then
    "${homebrew_ruby_bin}/gem" install bundler -v "${HOMEBREW_BUNDLER_VERSION}"
  fi

  export HOMEBREW_RUBY_PATH HOMEBREW_BOOTSNAP_GEM_PATH
  [[ -n "${HOMEBREW_LINUX}" && -n "${TERMINFO_DIRS}" ]] && export TERMINFO_DIRS
}

setup-gem-home-bundle-gemfile() {
  GEM_VERSION="$("${HOMEBREW_RUBY_PATH}" "${HOMEBREW_RUBY_DISABLE_OPTIONS}" "${HOMEBREW_LIBRARY}/Homebrew/utils/ruby_sh/ruby_gem_version.rb")"
  GEM_HOME="${HOMEBREW_LIBRARY}/Homebrew/vendor/bundle/ruby/${GEM_VERSION}"
  BUNDLE_GEMFILE="${HOMEBREW_LIBRARY}/Homebrew/Gemfile"

  export GEM_HOME
  export BUNDLE_GEMFILE
}

ensure-bundle-dependencies() {
  local install_args=()

  if ! bundle check &>/dev/null
  then
    if [[ -n "${BUNDLE_WITH}" ]]
    then
      # Convert colon-separated BUNDLE_WITH to comma-separated for --add-groups
      local groups_for_flag="${BUNDLE_WITH//:/,}"
      install_args+=("--add-groups=${groups_for_flag}")
    fi
    "${HOMEBREW_BREW_FILE}" install-bundler-gems "${install_args[@]}"
  fi
}
