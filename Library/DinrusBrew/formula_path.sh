# does the quickest output of brew --prefix/--cellar possible for the basic cases:
# - `brew --prefix` (output DINRUSBREW_PREFIX)
# - `brew --cellar` (output DINRUSBREW_CELLAR)
# - `brew --prefix <formula>` (output DINRUSBREW_PREFIX/opt/<formula>)
# - `brew --cellar <formula>` (output DINRUSBREW_CELLAR/<formula>)
# anything else? delegate to the slower cmd/--prefix.rb and cmd/--cellar.rb
# DINRUSBREW_PREFIX and DINRUSBREW_REPOSITORY are set by brew.sh
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
      echo "${DINRUSBREW_PREFIX}"
    else
      echo "${DINRUSBREW_CELLAR}"
    fi
    return 0
  fi

  local formula_exists
  if [[ -f "${DINRUSBREW_REPOSITORY}/Library/Taps/homebrew/homebrew-core/Formula/${formula}.rb" ]]
  then
    formula_exists="1"
  else
    local formula_path
    formula_path="$(
      shopt -s nullglob
      echo "${DINRUSBREW_REPOSITORY}/Library/Taps"/*/*/{Formula/,HomebrewFormula/,Formula/*/,}"${formula}.rb"
    )"
    [[ -n "${formula_path}" ]] && formula_exists="1"
  fi

  if [[ -z "${formula_exists}" &&
        -z "${DINRUSBREW_NO_INSTALL_FROM_API}" ]]
  then
    if [[ -f "${DINRUSBREW_CACHE}/api/formula_names.txt" ]] &&
       grep -Fxq "${formula}" "${DINRUSBREW_CACHE}/api/formula_names.txt"
    then
      formula_exists="1"
    elif [[ -f "${DINRUSBREW_CACHE}/api/formula_aliases.txt" ]]
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
      done <"${DINRUSBREW_CACHE}/api/formula_aliases.txt"
    fi
  fi

  [[ -z "${formula_exists}" ]] && return 1

  if [[ -n "${prefix}" ]]
  then
    echo "${DINRUSBREW_PREFIX}/opt/${formula}"
  else
    echo "${DINRUSBREW_CELLAR}/${formula}"
  fi
  return 0
}
