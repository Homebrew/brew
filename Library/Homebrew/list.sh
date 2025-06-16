# does the quickest output of brew list possible for no named arguments.
# HOMEBREW_CELLAR, HOMEBREW_PREFIX are set by brew.sh
# shellcheck disable=SC2154
homebrew-list() {
  case "$1" in
    # check we actually have list and not e.g. listsomething
    list | ls) ;;
    list* | ls*) return 1 ;;
    *) ;;
  esac

  local ls_env=()
  local ls_args=()

  local tty
  if [[ -t 1 ]]
  then
    tty=1
    ls_args+=("-Cq")
    source "${HOMEBREW_LIBRARY}/Homebrew/utils/helpers.sh"
    ls_env+=("COLUMNS=$(columns)")
  fi

  local formula=""
  local cask=""

  # `OPTIND` is used internally by `getopts` to track parsing position
  local OPTIND=2 # skip $1 (and localise OPTIND to this function)
  while getopts ":1lrt-:" arg
  do
    case "${arg}" in
      # check for flags passed to ls
      1 | l | r | t) ls_args+=("-${arg}") ;;
      -)
        local parsed_index=$((OPTIND - 1)) # Parse full arg to reject e.g. -r-formula
        case "${!parsed_index}" in
          --formula | --formulae) formula=1 ;;
          --cask | --casks) cask=1 ;;
          *) return 1 ;;
        esac
        ;;
      # reject all other flags
      *) return 1 ;;
    esac
  done
  # If we haven't reached the end of the arg list, we have named args.
  if ((OPTIND - 1 != $#))
  then
    return 1
  fi

  if [[ -z "${cask}" && -d "${HOMEBREW_CELLAR}" ]]
  then
    if [[ -n "${tty}" && -z "${formula}" ]]
    then
      ohai "Formulae"
    fi

    local formula_output
    formula_output="$(/usr/bin/env "${ls_env[@]}" ls "${ls_args[@]}" "${HOMEBREW_CELLAR}")" || exit 1
    if [[ -n "${formula_output}" ]]
    then
      echo "${formula_output}"
    fi

    if [[ -n "${tty}" && -z "${formula}" ]]
    then
      echo
    fi
  fi

  if [[ -z "${formula}" && -d "${HOMEBREW_CASKROOM}" ]]
  then
    if [[ -n "${tty}" && -z "${cask}" ]]
    then
      ohai "Casks"
    fi

    local cask_output
    cask_output="$(/usr/bin/env "${ls_env[@]}" ls "${ls_args[@]}" "${HOMEBREW_CASKROOM}")" || exit 1
    if [[ -n "${cask_output}" ]]
    then
      echo "${cask_output}"
    fi

    return 0
  fi
}
