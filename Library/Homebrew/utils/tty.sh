# TTY helpers for Homebrew's Bash scripts.

# These variables are set from the user environment.
# shellcheck disable=SC2154
tty_colour_enabled() {
  local stream="${1:-1}"
  [[ -n "${HOMEBREW_COLOR}" || (-t "${stream}" && -z "${HOMEBREW_NO_COLOR}") ]]
}

# Keep in sync with Tty.width in Library/Homebrew/utils/tty.rb.
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
