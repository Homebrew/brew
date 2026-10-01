homebrew-sudo-available() {
  [[ -z "${HOMEBREW_NO_SUDO:-}" ]] || return 1
  [[ "${HOMEBREW_SUDO_CHECKED:-}" != 1 ]] || return 0
  HOMEBREW_SUDO_CHECKED=1

  local SUDO="${1:-}" SUDO_OUTPUT
  if [[ -z "${SUDO}" ]]
  then
    # Avoid picking up any random `sudo` in `PATH`.
    if [[ -x /usr/bin/sudo ]]
    then
      SUDO=/usr/bin/sudo
    else
      # Do this after ensuring we're using default Bash builtins.
      SUDO="$(command -v sudo 2>/dev/null)"
    fi
  fi

  # Keep detection in sync with Homebrew/install's install.sh.
  # Used by SystemCommand.sudo_available? in system_command.rb.
  if [[ ! -x "${SUDO}" ]]
  then
    export HOMEBREW_NO_SUDO=1
  # Reset sudo timestamp to avoid running unauthorised sudo commands.
  elif ! SUDO_OUTPUT="$(LC_ALL=C "${SUDO}" --reset-timestamp 2>&1)"
  then
    case "${SUDO_OUTPUT}" in
      *'The "no new privileges" flag is set'* | \
        *"effective uid is not 0"* | \
        *"must be owned by uid 0 and have the setuid bit set"*)
        export HOMEBREW_NO_SUDO=1
        ;;
      *) ;;
    esac
  fi

  # Do not update cached credentials while checking privileges.
  if [[ -z "${HOMEBREW_NO_SUDO:-}" ]] && ! SUDO_OUTPUT="$(LC_ALL=C "${SUDO}" -n -k -l 2>&1)"
  then
    # Authentication failures do not establish whether sudo is permitted.
    case "${SUDO_OUTPUT}" in
      *'The "no new privileges" flag is set'* | \
        *"effective uid is not 0"* | \
        *"must be owned by uid 0 and have the setuid bit set"* | \
        *" is not in the sudoers file."* | *" is not allowed to run sudo on "* | *" may not run sudo on "*)
        export HOMEBREW_NO_SUDO=1
        ;;
      *) ;;
    esac
  fi

  [[ -z "${HOMEBREW_NO_SUDO:-}" ]]
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]
then
  homebrew-sudo-available "$@"
fi
