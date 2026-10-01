# Helpers for Homebrew's Bash command option parsing.

# HOMEBREW_LIBRARY is set by bin/brew.
# shellcheck disable=SC2154
source "${HOMEBREW_LIBRARY}/Homebrew/utils.sh"

homebrew-command-help() {
  local command="$1"
  local option="$2"

  case "${option}" in
    -\? | -h | --help | --usage)
      brew help "${command}"
      ;;
    --*)
      return 1
      ;;
    -*h*)
      brew help "${command}"
      ;;
    *)
      return 1
      ;;
  esac
}

homebrew-command-common-option() {
  local option="$1"

  case "${option}" in
    --verbose)
      HOMEBREW_VERBOSE=1
      ;;
    --quiet)
      HOMEBREW_QUIET=1
      ;;
    --debug)
      HOMEBREW_DEBUG=1
      ;;
    --*)
      return 1
      ;;
    -*)
      local other_options="${option#-}"
      other_options="${other_options//[dqv]/}"
      [[ -n "${option#-}" && -z "${other_options}" ]] || return 1

      # `HOMEBREW_VERBOSE` is read by caller command code after this helper returns.
      # shellcheck disable=SC2034
      [[ "${option#-}" == *v* ]] && HOMEBREW_VERBOSE=1
      # `HOMEBREW_QUIET` is read by caller command code after this helper returns.
      # shellcheck disable=SC2034
      [[ "${option#-}" == *q* ]] && HOMEBREW_QUIET=1
      [[ "${option#-}" == *d* ]] && HOMEBREW_DEBUG=1
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

homebrew-command-common-short-options() {
  local options="$1"

  case "${options}" in
    --*)
      return 1
      ;;
    -*) ;;
    *)
      return 1
      ;;
  esac

  options="${options#-}"
  [[ -n "${options}" ]] || return 1
  options="${options//[!dqv]/}"
  [[ -z "${options}" ]] || homebrew-command-common-option "-${options}"
}

homebrew-command-enable-debug() {
  [[ -n "${HOMEBREW_DEBUG:-}" ]] && set -x
}
