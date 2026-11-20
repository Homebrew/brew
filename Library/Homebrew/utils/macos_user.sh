# Used by `brew as-console-user` and macOS installer package scripts.
# Keep this standalone: package scripts source it before Homebrew is installed.

# macOS login discards the command's exit status, so return it through a file.
homebrew-login() (
  local user="$1" status_dir status
  shift
  status_dir="$(mktemp -d /tmp/homebrew-login.XXXXXX)" || return 1
  trap 'rm -rf "${status_dir}"' EXIT
  touch "${status_dir}/status" || return 1
  chmod 600 "${status_dir}/status" || return 1
  chown "${user}" "${status_dir}/status" || return 1
  # Only root may replace the status file; the target user may write to it.
  chmod 711 "${status_dir}" || return 1

  # Expand arguments and capture status in the target user's shell.
  # shellcheck disable=SC2016
  login -f -l -q "${user}" /bin/bash -c '
    status_file="$1"
    shift
    "$@"
    printf "%s\n" "$?" > "$status_file"
  ' -- "${status_dir}/status" "$@" || return "$?"
  # Only accept an exit code from the unprivileged writer.
  IFS= read -r -n 4 status <"${status_dir}/status" || return 1
  [[ "${status}" =~ ^(0|[1-9][0-9]{0,2})$ ]] && ((status <= 255)) || return 1
  return "${status}"
)

# Print the active macOS console user, or fail for login-window/system users.
homebrew-console-user() {
  local console_user
  console_user="$(stat -f "%Su" /dev/console 2>/dev/null)" || return 1

  case "${console_user}" in
    "" | root | loginwindow | _mbsetupuser)
      return 1
      ;;
    *) ;;
  esac

  printf '%s\n' "${console_user}"
}

# Print a user's home directory from the local account database.
homebrew-user-home() {
  local user_record
  user_record="$(id -P "$1" 2>/dev/null)" || return 1
  user_record="${user_record%:*}"
  user_record="${user_record##*:}"
  [[ -n "${user_record}" ]] || return 1

  printf '%s\n' "${user_record}"
}

# Print the package install user, preferring MDM's plist override.
homebrew-package-user() {
  local homebrew_pkg_user_plist="${HOMEBREW_PKG_USER_PLIST:-/var/tmp/.homebrew_pkg_user.plist}"
  # Only honour an override plist that is securely managed by an administrator:
  # a single-link regular file, owned by root, mode 0600 and free of ACLs.
  # Otherwise fall back to the console user below. Read ownership and mode from
  # `stat` so extended attributes are ignored, and detect ACLs with `ls -led`,
  # which prints an extra line per ACL entry (its "@"/"+" mode suffix is not
  # reliable as "@" for extended attributes masks "+" for ACLs).
  # shellcheck disable=SC2012
  if [[ "$(LC_ALL=C stat -f '%HT %u %Lp %l' "${homebrew_pkg_user_plist}" 2>/dev/null)" == "Regular File 0 600 1" ]] &&
     [[ "$(ls -led "${homebrew_pkg_user_plist}" 2>/dev/null | wc -l)" -eq 1 ]]
  then
    local homebrew_pkg_user
    if homebrew_pkg_user="$(plutil -extract HOMEBREW_PKG_USER raw -expect string -o - -- "${homebrew_pkg_user_plist}" 2>/dev/null)" &&
       [[ -n "${homebrew_pkg_user}" ]]
    then
      printf '%s\n' "${homebrew_pkg_user}"
      return
    fi
  fi

  # Fall back to the active console user when MDM has not specified one.
  homebrew-console-user
}

homebrew-package-abort() {
  echo "$1" >&2
  exit 1
}

homebrew-package-check-directory() {
  # ls -led also detects ACLs on directories with extended attributes.
  # shellcheck disable=SC2012
  [[ "$(stat -f '%u %Sp' "$1")" == "0 d"????-??-? && "$(ls -led "$1" | wc -l)" -eq 1 ]] ||
    homebrew-package-abort "The package requires a protected directory at $1."
}

# Enter the validated prefix and prepare user_command for the package scripts.
homebrew-package-setup() {
  local homebrew_pkg_user user_home_dir first_entry
  unset CDPATH DEVELOPER_DIR HOMEBREW_PKG_USER_PLIST
  export LC_ALL=C
  homebrew_directory=/opt/homebrew
  # Both installer scripts use these directories after setup.
  # shellcheck disable=SC2034
  directories=(Caskroom Cellar Frameworks bin etc include lib opt sbin share var var/homebrew var/homebrew/linked)
  payload_directory=/private/var/db/sh.brew.homebrew
  [[ "${2:-}" == / && "${3:-}" == / ]] || homebrew-package-abort "Homebrew must be installed on the startup volume."

  homebrew_pkg_user="$(homebrew-package-user)" && [[ -n "${homebrew_pkg_user}" && "${homebrew_pkg_user}" != [-#]* ]] &&
    install_uid="$(id -u "${homebrew_pkg_user}")" && [[ "${install_uid}" =~ ^[1-9][0-9]*$ ]] ||
    homebrew-package-abort "A non-root Homebrew installation user is required."
  user_home_dir="$(homebrew-user-home "${homebrew_pkg_user}")"
  [[ "${user_home_dir}" == /* && "${user_home_dir}" != / ]] ||
    homebrew-package-abort "The Homebrew installation user requires a home directory."

  if [[ -z "${HOMEBREW_NO_SUDO:-}" ]] && command -v sudo &>/dev/null
  then
    user_command=(sudo -u "#${install_uid}" --)
  elif [[ "$(id -u)" == 0 ]]
  then
    user_command=(homebrew-login "${homebrew_pkg_user}")
  else
    homebrew-package-abort "Switching to the Homebrew installation user without sudo requires root."
  fi
  user_command+=(/usr/bin/env -i PATH="${PATH}" HOME="${user_home_dir}" USER="${homebrew_pkg_user}" LOGNAME="${homebrew_pkg_user}")

  homebrew_pkg_group="admin"
  if [[ " $(id -Gn "${homebrew_pkg_user}") " != *" admin "* ]]
  then
    homebrew_pkg_group="$(id -gn "${homebrew_pkg_user}")"
  fi

  homebrew-package-check-directory "${payload_directory%/*}"
  if [[ -e "${payload_directory}" || -L "${payload_directory}" ]]
  then
    homebrew-package-check-directory "${payload_directory}"
  fi
  (umask go-w && mkdir -p "${homebrew_directory%/*}")
  homebrew-package-check-directory "${homebrew_directory%/*}"
  (umask go-w && mkdir -p "${homebrew_directory}")
  cd -P -- "${homebrew_directory}" || return 1
  [[ "${PWD}" == "${homebrew_directory}" ]] || homebrew-package-abort "Refusing to install to a symlinked Homebrew prefix."
  case "$(stat -f '%u' .)" in
    0)
      first_entry="$(find . -mindepth 1 -maxdepth 1 -print -quit)"
      [[ -z "${first_entry}" ]] ||
        homebrew-package-abort "Cannot adopt the non-empty root-owned prefix at ${homebrew_directory}."
      ;;
    "${install_uid}") ;;
    *) homebrew-package-abort "The existing Homebrew prefix belongs to another user." ;;
  esac
  chown "${homebrew_pkg_user}:${homebrew_pkg_group}" .
}
