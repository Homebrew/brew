# Does the quickest output of brew tap possible for no arguments.
# HOMEBREW_LIBRARY is set by bin/brew
# shellcheck disable=SC2154

normalise_tap_name() {
  local directory="$1"
  local user
  local repository

  user="$(tr '[:upper:]' '[:lower:]' <<<"${directory%%/*}")"
  repository="$(tr '[:upper:]' '[:lower:]' <<<"${directory#*/}")"
  repository="${repository#@(home|linux)brew-}"
  echo "${user}/${repository}"
}

homebrew-tap() {
  local taplib="${HOMEBREW_LIBRARY}/Taps"
  (
    shopt -s extglob

    for directory in "${taplib}"/*/*
    do
      [[ -d "${directory}" ]] || continue
      normalise_tap_name "${directory#"${taplib}"/}"
    done | sort
  )
}
