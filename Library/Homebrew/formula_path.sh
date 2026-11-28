# does the quickest output of brew --prefix/--cellar possible for the basic cases:
# - `brew --prefix` (output HOMEBREW_PREFIX)
# - `brew --cellar` (output HOMEBREW_CELLAR)
# - `brew --prefix <formula>` (output HOMEBREW_PREFIX/opt/<formula>)
# - `brew --cellar <formula>` (output HOMEBREW_CELLAR/<formula>)
# anything else? delegate to the slower cmd/--prefix.rb and cmd/--cellar.rb
# HOMEBREW_PREFIX and HOMEBREW_REPOSITORY are set by brew.sh
# shellcheck disable=SC2154
homebrew-formula-path() {
  while [[ "$#" -gt 0 ]]
  do
    case "$1" in
      # check we actually have --prefix and not e.g. --prefixsomething
      --prefix)
        local prefix="1"
        shift
        ;;
      --cellar)
        local cellar="1"
        shift
        ;;
      # reject all other flags
      -*) return 1 ;;
      *)
        [[ -n "${formula}" ]] && return 1
        local formula="$1"
        shift
        ;;
    esac
  done
  [[ -z "${prefix}" && -z "${cellar}" ]] && return 1
  [[ -n "${prefix}" && -n "${cellar}" ]] && return 1 # don't allow both!
  if [[ -z "${formula}" ]]
  then
    if [[ -n "${prefix}" ]]
    then
      echo "${HOMEBREW_PREFIX}"
    else
      echo "${HOMEBREW_CELLAR}"
    fi
    return 0
  fi

  local given_formula="${formula}"
  local formula_exists
  if [[ -f "${HOMEBREW_REPOSITORY}/Library/Taps/homebrew/homebrew-core/Formula/${formula}.rb" ]]
  then
    formula_exists="1"
  else
    local formula_path
    formula_path="$(
      shopt -s nullglob
      echo "${HOMEBREW_REPOSITORY}/Library/Taps"/*/*/{Formula/,HomebrewFormula/,Formula/*/,}"${formula}.rb"
    )"
    [[ -n "${formula_path}" ]] && formula_exists="1"
  fi

  if [[ -z "${formula_exists}" &&
        -z "${HOMEBREW_NO_INSTALL_FROM_API}" ]]
  then
    if [[ -f "${HOMEBREW_CACHE}/api/formula_names.txt" ]] &&
       grep -Fxq "${formula}" "${HOMEBREW_CACHE}/api/formula_names.txt"
    then
      formula_exists="1"
    elif [[ -f "${HOMEBREW_CACHE}/api/formula_aliases.txt" ]]
    then
      while IFS="|" read -r alias_name real_name
      do
        case "${alias_name}" in
          "${formula}")
            formula_exists="1"
            formula="${real_name}"
            break
            ;;
          *) ;;
        esac
      done <"${HOMEBREW_CACHE}/api/formula_aliases.txt"
    fi
  fi

  if [[ -z "${formula_exists}" ]]
  then
    local opt_prefix="${HOMEBREW_PREFIX}/opt/${formula}"
    [[ "${formula}" != */* && -L "${opt_prefix}" ]] || return 1

    # A tap alias may have changed since the opt link was created.
    local tap_alias
    for tap_alias in "${HOMEBREW_REPOSITORY}/Library/Taps"/*/*/Aliases/"${formula}"
    do
      [[ -L "${tap_alias}" ]] && return 1
    done

    # Installed formulae and their aliases link to Cellar/<name>/<version>.
    local keg rack
    keg="$(realpath "${opt_prefix}")" || return 1
    rack="${keg%/*}"
    [[ "${rack%/*}" -ef "${HOMEBREW_CELLAR}" ]] || return 1
    formula="${rack##*/}"
  fi

  # Renaming an installed formula leaves a Cellar/<old name> symlink behind.
  # Ruby resolves that name to the installed formula even after the name has
  # become an alias of another formula, so only answer here when both agree.
  local given_rack="${HOMEBREW_CELLAR}/${given_formula}"
  if [[ -L "${given_rack}" ]]
  then
    local installed_rack
    installed_rack="$(realpath "${given_rack}")" || return 1
    [[ "${installed_rack##*/}" == "${formula}" ]] || return 1
  fi

  if [[ -n "${prefix}" ]]
  then
    echo "${HOMEBREW_PREFIX}/opt/${formula}"
  else
    echo "${HOMEBREW_CELLAR}/${formula}"
  fi
  return 0
}
