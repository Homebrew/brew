# `HOMEBREW_*` variables are set by brew.sh before sourcing this command.
# shellcheck disable=SC2154
source "${HOMEBREW_LIBRARY}/Homebrew/utils/cmd.sh"

homebrew-as-user() {
  local command_name="$1"
  shift
  while [[ "$#" -gt 0 ]]
  do
    if homebrew-command-help "${command_name}" "$1"
    then
      return $?
    fi
    if homebrew-command-common-option "$1"
    then
      shift
      continue
    fi
    break
  done

  homebrew-command-enable-debug

  if [[ "$#" -eq 0 ]]
  then
    brew help "${command_name}"
    return 1
  fi

  [[ -n "${HOMEBREW_MACOS}" || "${command_name}" == as-brew-user ]] ||
    odie "\`brew as-console-user\` is only supported on macOS."

  # `HOMEBREW_LIBRARY` is set by brew.sh, so ShellCheck cannot follow it.
  # shellcheck disable=SC1091
  source "${HOMEBREW_LIBRARY}/Homebrew/utils/macos_user.sh"

  local selected_user
  if [[ "${command_name}" == as-brew-user ]]
  then
    if [[ -n "${HOMEBREW_MACOS}" ]]
    then
      selected_user="$(stat -L -f "%Su" "${HOMEBREW_PREFIX}")"
    else
      selected_user="$(stat -L -c "%U" "${HOMEBREW_PREFIX}")"
    fi
    [[ -n "${selected_user}" ]] || odie "Could not determine the Homebrew prefix owner."
    [[ "${selected_user}" != root ]] || odie "The Homebrew prefix owner must not be root."
  else
    selected_user="$(homebrew-console-user)" || odie "No supported macOS console user is logged in."
  fi

  local selected_home
  if [[ -n "${HOMEBREW_MACOS}" ]]
  then
    selected_home="$(homebrew-user-home "${selected_user}")"
  else
    selected_home="$(getent passwd "${selected_user}" | cut -d: -f6)"
  fi
  [[ -n "${selected_home}" ]] || odie "Could not determine home directory for user: ${selected_user}"

  local user_command=()
  if [[ "${command_name}" == as-console-user && -z "${HOMEBREW_NO_SUDO:-}" ]] || [[ "$(id -un)" != "${selected_user}" ]]
  then
    # `HOMEBREW_LIBRARY` is set by brew.sh, so ShellCheck cannot follow it.
    # shellcheck disable=SC1091
    source "${HOMEBREW_LIBRARY}/Homebrew/utils/sudo.sh"
    if homebrew-sudo-available
    then
      user_command=(sudo -H -u "${selected_user}")
    elif [[ "$(id -u)" != 0 ]]
    then
      odie "Cannot switch to ${selected_user} with sudo disabled. Log in as ${selected_user} instead."
    elif [[ -n "${HOMEBREW_MACOS}" ]]
    then
      user_command=(homebrew-login "${selected_user}")
    else
      user_command=(runuser -u "${selected_user}" --)
    fi
  fi

  (
    if [[ "${command_name}" == as-brew-user ]]
    then
      # Expand HOME only after switching to the prefix owner.
      # shellcheck disable=SC2016
      set -- /bin/bash -c 'cd -- "$HOME" && exec "$@"' -- "${HOMEBREW_BREW_FILE}" "$@"
    else
      cd "${selected_home}" &>/dev/null || odie "Failed to cd to ${selected_home}!"
      set -- "${HOMEBREW_BREW_FILE}" "$@"
    fi

    "${user_command[@]}" /usr/bin/env -i \
      "HOME=${selected_home}" \
      "USER=${selected_user}" \
      "LOGNAME=${selected_user}" \
      "PWD=${selected_home}" \
      "PATH=/usr/bin:/bin:/usr/sbin:/sbin" \
      ${HOMEBREW_NO_SUDO:+"HOMEBREW_NO_SUDO=${HOMEBREW_NO_SUDO}"} \
      "$@"
  )
}
