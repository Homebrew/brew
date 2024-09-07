# These variables are set from the user environment.
# shellcheck disable=SC2154
ohai() {
  # Check whether stdout is a tty.
  if [[ -n "${HOMEBREW_COLOR}" || (-t 1 && -z "${HOMEBREW_NO_COLOR}") ]]
  then
    echo -e "\\033[34m==>\\033[0m \\033[1m$*\\033[0m" # blue arrow and bold text
  else
    echo "==> $*"
  fi
}

opoo() {
  # Check whether stderr is a tty.
  if [[ -n "${HOMEBREW_COLOR}" || (-t 2 && -z "${HOMEBREW_NO_COLOR}") ]]
  then
    echo -ne "\\033[4;33mWarning\\033[0m: " >&2 # highlight Warning with underline and yellow color
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

bold() {
  # Check whether stderr is a tty.
  if [[ -n "${HOMEBREW_COLOR}" || (-t 2 && -z "${HOMEBREW_NO_COLOR}") ]]
  then
    echo -e "\\033[1m""$*""\\033[0m"
  else
    echo "$*"
  fi
}

onoe() {
  # Check whether stderr is a tty.
  if [[ -n "${HOMEBREW_COLOR}" || (-t 2 && -z "${HOMEBREW_NO_COLOR}") ]]
  then
    echo -ne "\\033[4;31mError\\033[0m: " >&2 # highlight Error with underline and red color
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
which() {
  # Alias to Bash built-in command `type -P`
  type -P "$@"
}

numeric() {
  local -a version_array
  IFS=".rc" read -r -a version_array <<<"${1}"
  printf "%01d%02d%02d%03d" "${version_array[@]}" 2>/dev/null
}

columns() {
  if [[ -n "${COLUMNS}" ]]
  then
    echo "${COLUMNS}"
    return
  fi

  local columns
  read -r _ columns < <(stty size 2>/dev/null)

  if [[ -z "${columns}" ]] && tput cols >/dev/null 2>&1
  then
    columns="$(tput cols)"
  fi

  echo "${columns:-80}"
}
