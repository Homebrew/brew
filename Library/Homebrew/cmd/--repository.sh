# Documentation defined in Library/Homebrew/cmd/--repository.rb

# HOMEBREW_REPOSITORY, HOMEBREW_LIBRARY are set by brew.sh
# shellcheck disable=SC2154

tap_path() {
  local tap="$1"
  local user
  local repo
  local part

  if [[ "${tap}" != *"/"* ]]
  then
    odie "Invalid tap name: ${tap}"
  fi

  user="$(echo "${tap%%/*}" | tr '[:upper:]' '[:lower:]')"
  repo="$(echo "${tap#*/}" | tr '[:upper:]' '[:lower:]')"

  for part in "${user}" "${repo}"
  do
    if [[ -z "${part}" || "${part}" == *"/"* ]]
    then
      odie "Invalid tap name: ${tap}"
    fi
  done

  repo="${repo#@(home|linux)brew-}"
  echo "${HOMEBREW_LIBRARY}/Taps/${user}/homebrew-${repo}"
}

homebrew---repository() {
  local tap

  if [[ "$#" -eq 0 ]]
  then
    echo "${HOMEBREW_REPOSITORY}"
    return
  fi

  (
    shopt -s extglob
    for tap in "$@"
    do
      tap_path "${tap}"
    done
  )
}
