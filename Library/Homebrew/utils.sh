# These variables are set from the user environment.
# shellcheck disable=SC2154
source "${HOMEBREW_LIBRARY}/Homebrew/utils/formatter.sh"

# Keep in sync with Utils::Output#ohai in Library/Homebrew/utils/output.rb.
ohai() {
  # Check whether stdout is a tty.
  headline "$*"
  echo
}

# Keep status labels, colours and emoji in sync with
# Utils::Output#pretty_installed in Library/Homebrew/utils/output.rb.
pretty_installed() {
  local string="$1"

  if [[ ! -t 1 ]]
  then
    echo "${string}"
    return
  fi

  if [[ -n "${HOMEBREW_NO_EMOJI}" ]]
  then
    if tty_colour_enabled 1
    then
      printf '\033[32m\033[1m%s (installed)\033[0m\n' "${string}"
    else
      echo "${string} (installed)"
    fi
  elif tty_colour_enabled 1
  then
    printf '\033[1m%s \033[32m✔\033[0m\n' "${string}"
  else
    echo "${string} ✔"
  fi
}

# Keep status labels, colours and emoji in sync with
# Utils::Output#pretty_uninstalled in Library/Homebrew/utils/output.rb.
pretty_uninstalled() {
  local string="$1"

  if [[ ! -t 1 ]]
  then
    echo "${string}"
    return
  fi

  if [[ -n "${HOMEBREW_NO_EMOJI}" ]]
  then
    if tty_colour_enabled 1
    then
      printf '\033[31m\033[1m%s (uninstalled)\033[0m\n' "${string}"
    else
      echo "${string} (uninstalled)"
    fi
  elif tty_colour_enabled 1
  then
    printf '\033[1m%s \033[31m✘\033[0m\n' "${string}"
  else
    echo "${string} ✘"
  fi
}

print_formula_install_status() {
  local formula="$1"

  if [[ -d "${HOMEBREW_CELLAR}/${formula}" ]]
  then
    pretty_installed "${formula}"
  else
    pretty_uninstalled "${formula}"
  fi
}

# Keep in sync with Utils::Output#opoo in Library/Homebrew/utils/output.rb.
opoo() {
  # Check whether stderr is a tty.
  if tty_colour_enabled 2
  then
    printf '%s ' "$(formatter_label 33 "Warning:" 2)" >&2 # highlight Warning with yellow color
  else
    echo -n "Warning: " >&2
  fi
  if [[ $# -eq 0 ]]
  then
    cat >&2
  else
    echo "$*" >&2
  fi
}

# Keep in sync with Utils::Output#onoe in Library/Homebrew/utils/output.rb.
onoe() {
  # Check whether stderr is a tty.
  if tty_colour_enabled 2
  then
    printf '%s ' "$(formatter_label 31 "Error:" 2)" >&2 # highlight Error with red color
  else
    echo -n "Error: " >&2
  fi
  if [[ $# -eq 0 ]]
  then
    cat >&2
  else
    echo "$*" >&2
  fi
}

# Keep in sync with Utils::Output#odie in Library/Homebrew/utils/output.rb.
odie() {
  onoe "$@"
  exit 1
}

safe_cd() {
  cd "$@" >/dev/null || odie "Failed to cd to $*!"
}

brew() {
  # This variable is set by bin/brew
  # shellcheck disable=SC2154
  "${HOMEBREW_BREW_FILE}" "$@"
}

curl() {
  "${HOMEBREW_LIBRARY}/Homebrew/shims/shared/curl" "$@"
}

git() {
  "${HOMEBREW_LIBRARY}/Homebrew/shims/shared/git" "$@"
}

# Search given executable in PATH (remove dependency for `which` command)
# Keep in sync with Kernel#which.
which() {
  # Alias to Bash built-in command `type -P`
  type -P "$@"
}

numeric() {
  local -a version_array
  IFS=".rc" read -r -a version_array <<<"${1}"
  printf "%01d%02d%02d%03d" "${version_array[@]}" 2>/dev/null
}
