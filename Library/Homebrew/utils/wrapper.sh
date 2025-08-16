# `brew` wrapper handling helpers.

# HOMEBREW_LIBRARY, HOMEBREW_BREW_FILE, HOMEBREW_ORIGINAL_BREW_FILE, HOMEBREW_PREFIX are set by bin/brew.
# HOMEBREW_FORCE_BREW_WRAPPER is set by the user environment.
# shellcheck disable=SC2154
source "${HOMEBREW_LIBRARY}/Homebrew/utils/helpers.sh"

odie-with-wrapper-message() {
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
