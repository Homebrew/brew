# Documentation defined in Library/Homebrew/cmd/as-console-user.rb

# `HOMEBREW_*` variables are set by brew.sh before sourcing this command.
# shellcheck disable=SC2154
source "${HOMEBREW_LIBRARY}/Homebrew/utils/cmd.sh"

homebrew-as-console-user() {
  while [[ "$#" -gt 0 ]]
  do
    if homebrew-command-help as-console-user "$1"
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
    brew help as-console-user
    return 1
  fi

  [[ -n "${HOMEBREW_MACOS}" ]] || odie "\`brew as-console-user\` is only supported on macOS."

  # `HOMEBREW_LIBRARY` is set by brew.sh, so ShellCheck cannot follow it.
  # shellcheck disable=SC1091
  source "${HOMEBREW_LIBRARY}/Homebrew/utils/macos_user.sh"

  local console_user
  console_user="$(homebrew-console-user)" || odie "No supported macOS console user is logged in."

  local console_home
  console_home="$(homebrew-user-home "${console_user}")" ||
    odie "Could not determine home directory for console user: ${console_user}"

  (
    cd "${console_home}" &>/dev/null || odie "Failed to cd to ${console_home}!"

    sudo -H -u "${console_user}" /usr/bin/env -i \
      "HOME=${console_home}" \
      "USER=${console_user}" \
      "LOGNAME=${console_user}" \
      "PWD=${console_home}" \
      "PATH=/usr/bin:/bin:/usr/sbin:/sbin" \
      "${HOMEBREW_BREW_FILE}" "$@"
  )
}
