# `brew` wrapper handling helpers.

# HOMEBREW_LIBRARY, HOMEBREW_BREW_FILE, HOMEBREW_ORIGINAL_BREW_FILE, HOMEBREW_PREFIX are set by bin/brew.
# HOMEBREW_FORCE_BREW_WRAPPER is set by the user environment.
# shellcheck disable=SC2154
odie-with-wrapper-message() {
  source "${HOMEBREW_LIBRARY}/Homebrew/utils/helpers.sh"

  local CUSTOM_MESSAGE="${1}"
  local HOMEBREW_FORCE_BREW_WRAPPER_WITHOUT_BREW="${HOMEBREW_FORCE_BREW_WRAPPER%/brew}"

  odie <<EOS
conflicting Homebrew wrapper configuration!
HOMEBREW_FORCE_BREW_WRAPPER was set to ${HOMEBREW_FORCE_BREW_WRAPPER}
${CUSTOM_MESSAGE}

$(bold "Ensure you run ${HOMEBREW_FORCE_BREW_WRAPPER} directly (not ${HOMEBREW_ORIGINAL_BREW_FILE})")!

Manually setting your PATH can interfere with Homebrew wrappers.
Ensure your shell configuration contains:
  eval "\$(${HOMEBREW_BREW_FILE} shellenv)"
or that ${HOMEBREW_FORCE_BREW_WRAPPER_WITHOUT_BREW} comes before ${HOMEBREW_PREFIX}/bin in your PATH:
  export PATH="${HOMEBREW_FORCE_BREW_WRAPPER_WITHOUT_BREW}:${HOMEBREW_PREFIX}/bin:\$PATH"
EOS
}

check-brew-wrapper() {
  [[ -z "${HOMEBREW_FORCE_BREW_WRAPPER:-}" ]] && return
  [[ -z "${HOMEBREW_DISABLE_NO_FORCE_BREW_WRAPPER:-}" && -n "${HOMEBREW_NO_FORCE_BREW_WRAPPER:-}" ]] && return

  # Require HOMEBREW_BREW_WRAPPER to be set if HOMEBREW_FORCE_BREW_WRAPPER is set
  # (and HOMEBREW_NO_FORCE_BREW_WRAPPER and HOMEBREW_DISABLE_NO_FORCE_BREW_WRAPPER are not set).
  if [[ -z "${HOMEBREW_DISABLE_NO_FORCE_BREW_WRAPPER:-}" && -z "${HOMEBREW_NO_FORCE_BREW_WRAPPER:-}" ]]
  then
    if [[ -z "${HOMEBREW_BREW_WRAPPER:-}" ]]
    then
      odie-with-wrapper-message "but HOMEBREW_BREW_WRAPPER   was unset."
    elif [[ "${HOMEBREW_FORCE_BREW_WRAPPER}" != "${HOMEBREW_BREW_WRAPPER}" ]]
    then
      odie-with-wrapper-message "but HOMEBREW_BREW_WRAPPER   was set to ${HOMEBREW_BREW_WRAPPER}"
    fi

    return
  fi

  # If HOMEBREW_FORCE_BREW_WRAPPER and HOMEBREW_DISABLE_NO_FORCE_BREW_WRAPPER are set,
  # verify that the path to our parent process is the same as the value of HOMEBREW_FORCE_BREW_WRAPPER.
  # We can't check this for `brew vendor-install` as this would cause an infinite loop on macOS.
  if [[ -n "${HOMEBREW_DISABLE_NO_FORCE_BREW_WRAPPER:-}" && "$1" != "vendor-install" ]]
  then
    local HOMEBREW_BREW_CALLER HOMEBREW_BREW_CALLER_CHECK_EXIT_CODE

    if [[ -n "${HOMEBREW_MACOS:-}" ]]
    then
      source "${HOMEBREW_LIBRARY}/Homebrew/utils/ruby.sh"
      setup-ruby-path
      HOMEBREW_BREW_CALLER="$("${HOMEBREW_RUBY_PATH}" "${HOMEBREW_LIBRARY}/Homebrew/utils/pid_path.rb" "${PPID}")"
    else
      HOMEBREW_BREW_CALLER="$(readlink -f "/proc/${PPID}/exe")"
    fi
    HOMEBREW_BREW_CALLER_CHECK_EXIT_CODE="$?"

    if ((HOMEBREW_BREW_CALLER_CHECK_EXIT_CODE != 0))
    then
      source "${HOMEBREW_LIBRARY}/Homebrew/utils/helpers.sh"
      # Error message already printed above when populating `HOMEBREW_BREW_CALLER`.
      odie "failed to check the path to the parent process!"
    fi

    if [[ "${HOMEBREW_BREW_CALLER:-}" != "${HOMEBREW_FORCE_BREW_WRAPPER}" ]]
    then
      odie-with-wrapper-message "but \`brew\` was invoked by ${HOMEBREW_BREW_CALLER}."
    fi
  fi
}
