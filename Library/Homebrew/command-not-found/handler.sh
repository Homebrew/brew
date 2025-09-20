#
# Homebrew command-not-found script for macOS
#
# Usage: Source it somewhere in your .bashrc (bash) or .zshrc (zsh)
#
# Author: Baptiste Fontaine
# License: MIT
# The license text can be found in Library/Homebrew/command-not-found/LICENSE

if ! command -v brew >/dev/null; then return; fi

homebrew_command_not_found_handle() {
  local cmd="$1"

  if [[ -n "${ZSH_VERSION}" ]]
  then
    autoload is-at-least
  fi

  # The code below is based off this Linux Journal article:
  #   http://www.linuxjournal.com/content/bash-command-not-found

  # do not run when inside Midnight Commander or within a Pipe, except if CI
  # HOMEBREW_COMMAND_NOT_FOUND_CI is defined in the CI environment
  # MC_SID is defined when running inside Midnight Commander.
  # shellcheck disable=SC2154
  if test -z "${HOMEBREW_COMMAND_NOT_FOUND_CI}" && test -n "${MC_SID}" -o ! -t 1
  then
    [[ -n "${BASH_VERSION}" ]] &&
      TEXTDOMAIN=command-not-found echo $"${cmd}: command not found"
    # Zsh versions 5.3 and above don't print this for us.
    [[ -n "${ZSH_VERSION}" ]] && is-at-least "5.2" "${ZSH_VERSION}" &&
      echo "zsh: command not found: ${cmd}" >&2
    return 127
  fi

  if [[ "${cmd}" != "-h" ]] && [[ "${cmd}" != "--help" ]] && [[ "${cmd}" != "--usage" ]] && [[ "${cmd}" != "-?" ]]
  then
    local txt
    txt="$(brew which-formula --skip-update --explain "${cmd}" 2>/dev/null)"
  fi

  if [[ -z "${txt}" ]]
  then
    [[ -n "${BASH_VERSION}" ]] &&
      TEXTDOMAIN=command-not-found echo $"${cmd}: command not found"

    # Zsh versions 5.3 and above don't print this for us.
    [[ -n "${ZSH_VERSION}" ]] && is-at-least "5.2" "${ZSH_VERSION}" &&
      echo "zsh: command not found: ${cmd}" >&2
  else
    echo "${txt}"
  fi

  return 127
}

if [[ -n "${BASH_VERSION}" ]]
then
  command_not_found_handle() {
    homebrew_command_not_found_handle "$*"
    return $?
  }
elif [[ -n "${ZSH_VERSION}" ]]
then
  command_not_found_handler() {
    homebrew_command_not_found_handle "$*"
    return $?
  }
fi
