# Documentation defined in Library/Homebrew/cmd/which-formula.rb

# shellcheck disable=SC2154
source "${HOMEBREW_LIBRARY}/Homebrew/utils/executables.sh"

homebrew-which-formula() {
  local args=()

  while [[ "$#" -gt 0 ]]
  do
    case "$1" in
      --explain)
        HOMEBREW_EXPLAIN=1
        shift
        ;;
      -\? | -h | --help | --usage)
        brew help which-formula
        exit $?
        ;;
      --verbose) HOMEBREW_VERBOSE=1 ;;
      --debug) HOMEBREW_DEBUG=1 ;;
      --quiet) HOMEBREW_QUIET=1 ;;
      --*)
        onoe "Unknown option: $1"
        brew help which-formula
        return 1
        ;;
      -*)
        [[ "$1" == *v* ]] && HOMEBREW_VERBOSE=1
        [[ "$1" == *q* ]] && HOMEBREW_QUIET=1
        [[ "$1" == *d* ]] && HOMEBREW_DEBUG=1
        shift
        ;;
      *)
        args+=("$1")
        shift
        ;;
    esac
  done

  if [[ -n "${HOMEBREW_DEBUG}" ]]
  then
    set -x
  fi

  if [[ ${#args[@]} -eq 0 ]]
  then
    brew help which-formula
    exit 1
  fi

  for cmd in "${args[@]}"
  do
    ensure_executables_file

    local formulae=()
    local formula
    while read -r formula
    do
      formulae+=("${formula}")
    done < <(formulae_containing_executable "${cmd}")

    [[ ${#formulae[@]} -eq 0 ]] && return 1

    if [[ -n ${HOMEBREW_EXPLAIN} ]]
    then
      local filtered_formulae=()
      for formula in "${formulae[@]}"
      do
        if [[ ! -d "${HOMEBREW_CELLAR}/${formula}" ]]
        then
          filtered_formulae+=("${formula}")
        fi
      done

      if [[ ${#filtered_formulae[@]} -eq 0 ]]
      then
        return 1
      fi

      if [[ ${#filtered_formulae[@]} -eq 1 ]]
      then
        echo "The program '${cmd}' is currently not installed. You can install it by typing:"
        echo "  brew install ${filtered_formulae[0]}"
      else
        echo "The program '${cmd}' can be found in the following formulae:"
        printf "  * %s\n" "${filtered_formulae[@]}"
        echo "Try: brew install <selected formula>"
      fi
    else
      for formula in "${formulae[@]}"
      do
        print_formula_install_status "${formula}"
      done
    fi
  done
}
