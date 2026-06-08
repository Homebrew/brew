# Used by `brew as-console-user` and macOS installer package scripts.
# Keep this standalone: package scripts source it before Homebrew is installed.

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

  echo "${console_user}"
}

# Print a user's home directory from the local account database.
homebrew-user-home() {
  local user_record
  user_record="$(id -P "$1" 2>/dev/null)" || return 1
  user_record="${user_record%:*}"
  user_record="${user_record##*:}"
  [[ -n "${user_record}" ]] || return 1

  echo "${user_record}"
}

# Print the package install user, preferring MDM's plist override.
homebrew-package-user() {
  local homebrew_pkg_user_plist="${HOMEBREW_PKG_USER_PLIST:-/var/tmp/.homebrew_pkg_user.plist}"
  # Only honour an override plist that is securely managed by an administrator:
  # a non-symlink regular file, owned by root, mode 0600 and free of ACLs.
  # Otherwise fall back to the console user below. Read ownership and mode from
  # `stat` so extended attributes are ignored, and detect ACLs with `ls -led`,
  # which prints an extra line per ACL entry (its "@"/"+" mode suffix is not
  # reliable as "@" for extended attributes masks "+" for ACLs).
  # shellcheck disable=SC2012 # `ls -led` is needed to detect ACLs; `find` cannot.
  if [[ ! -L "${homebrew_pkg_user_plist}" && -f "${homebrew_pkg_user_plist}" ]] &&
     [[ "$(stat -f "%Su %Lp" "${homebrew_pkg_user_plist}" 2>/dev/null)" == "root 600" ]] &&
     [[ "$(ls -led "${homebrew_pkg_user_plist}" 2>/dev/null | wc -l)" -eq 1 ]]
  then
    local homebrew_pkg_user
    if homebrew_pkg_user="$(defaults read "${homebrew_pkg_user_plist}" HOMEBREW_PKG_USER 2>/dev/null)" &&
       [[ -n "${homebrew_pkg_user}" ]]
    then
      echo "${homebrew_pkg_user}"
      return
    fi
  fi

  # Fall back to the active console user when MDM has not specified one.
  homebrew-console-user
}
