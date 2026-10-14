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
  local ls_flag=""

  local tty
  if [[ -t 1 ]]
  then
    tty=1
    ls_args+=("-Cq")
    source "${HOMEBREW_LIBRARY}/Homebrew/utils.sh"
    ls_env+=("COLUMNS=$(columns)")
  fi

  local formula=""
  local cask=""
  local versions=""
  local json=""
  local installed_on_request=""

  # `OPTIND` is used internally by `getopts` to track parsing position
  local OPTIND=2 # skip $1 (and localise OPTIND to this function)
  while getopts ":1lrt-:" arg
  do
    case "${arg}" in
      # check for flags passed to ls
      1 | l | r | t)
        ls_args+=("-${arg}")
        ls_flag=1
        ;;
      -)
        local parsed_index=$((OPTIND - 1)) # Parse full arg to reject e.g. -r-formula
        case "${!parsed_index}" in
          --formula | --formulae) formula=1 ;;
          --cask | --casks) cask=1 ;;
          --versions) versions=1 ;;
          --json) json=1 ;;
          --installed-on-request) installed_on_request=1 ;;
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

  if [[ -n "${installed_on_request}" ]]
  then
    # The Ruby command handles combinations, names, and receipt layouts which
    # cannot be identified from a single installed keg.
    [[ -n "${formula}" && -z "${cask}${versions}${json}${ls_flag}" ]] || return 1

    local jq
    jq="$(type -P jq)"
    if [[ -z "${jq}" && -n "${HOMEBREW_PATH:-}" ]]
    then
      jq="$(PATH="${HOMEBREW_PATH}" type -P jq)"
    fi
    [[ -n "${jq}" ]] || return 1

    local aliases_file="${HOMEBREW_CACHE}/api/formula_aliases.txt"
    local names_file="${HOMEBREW_CACHE}/api/formula_names.txt"
    [[ -r "${aliases_file}" && -r "${names_file}" ]] || return 1
    # Tap trust and tap migrations require Ruby's full resolution rules.
    [[ ! -f "${HOMEBREW_USER_CONFIG_HOME}/trust.json" ]] || return 1
    [[ -z "${HOMEBREW_NO_REQUIRE_TAP_TRUST:-}" ]] || return 1

    local receipts=()
    local rack keg receipt
    if [[ -d "${HOMEBREW_CELLAR}" ]]
    then
      for rack in "${HOMEBREW_CELLAR}"/*
      do
        [[ -d "${rack}" && ! -L "${rack}" && "${rack##*/}" != .* ]] || continue
        keg=""
        local version_dir
        for version_dir in "${rack}"/*
        do
          [[ -d "${version_dir}" ]] || continue
          receipt="${version_dir}/INSTALL_RECEIPT.json"
          [[ -f "${receipt}" && -r "${receipt}" ]] || return 1
          [[ -z "${keg}" ]] || return 1
          keg=1
          receipts+=("${receipt}")
        done
        [[ -n "${keg}" ]] || return 1
      done
    fi

    local output
    output="$("${jq}" -nr --rawfile aliases "${aliases_file}" --rawfile names "${names_file}" \
      -f "${HOMEBREW_LIBRARY}/Homebrew/list-installed-on-request.jq" "${receipts[@]}" 2>/dev/null)" || return 1
    [[ -z "${output}" ]] || printf '%s\n' "${output}"
    return 0
  fi

  if [[ -n "${json}" ]]
  then
    if [[ -z "${versions}" ]]
    then
      echo "Error: \`brew list --json\` requires \`--versions\`." >&2
      exit 1
    fi
    if [[ -n "${ls_flag}" ]]
    then
      echo "Error: \`brew list --versions --json\` cannot be combined with \`-1\`, \`-l\`, \`-r\` or \`-t\`." >&2
      exit 1
    fi
    if [[ -n "${formula}" && -n "${cask}" ]]
    then
      echo "Error: \`--formula\` and \`--cask\` are mutually exclusive." >&2
      exit 1
    fi

    local jq
    jq="$(type -P jq)"
    if [[ -z "${jq}" && -n "${HOMEBREW_PATH:-}" ]]
    then
      jq="$(PATH="${HOMEBREW_PATH}" type -P jq)"
    fi
    if [[ -z "${jq}" ]]
    then
      if [[ -x "${HOMEBREW_PREFIX}/opt/jq/bin/jq" ]]
      then
        jq="${HOMEBREW_PREFIX}/opt/jq/bin/jq"
      elif [[ -x "${HOMEBREW_PREFIX}/bin/jq" ]]
      then
        jq="${HOMEBREW_PREFIX}/bin/jq"
      fi
    fi
    if [[ -z "${jq}" ]]
    then
      echo "Error: jq is required for brew list --versions --json." >&2
      exit 1
    fi

    local pipefail=""
    [[ -o pipefail ]] && pipefail=1
    set -o pipefail

    {
      if [[ -z "${cask}" && -d "${HOMEBREW_CELLAR}" ]]
      then
        local rack
        for rack in "${HOMEBREW_CELLAR}"/*
        do
          [[ -d "${rack}" && ! -L "${rack}" ]] || continue
          [[ "${rack##*/}" != .* ]] || continue

          local linked_version=""
          local linked_path="${HOMEBREW_PREFIX}/var/homebrew/linked/${rack##*/}"
          if [[ -L "${linked_path}" && -d "${linked_path}" ]]
          then
            local linked_real_path
            linked_real_path="$(realpath "${linked_path}")" || exit 1
            linked_version="${linked_real_path##*/}"
          fi

          local pinned_version=""
          local pinned_path="${HOMEBREW_PREFIX}/var/homebrew/pinned/${rack##*/}"
          if [[ -L "${pinned_path}" && -d "${pinned_path}" ]]
          then
            local pinned_real_path
            pinned_real_path="$(realpath "${pinned_path}")" || exit 1
            pinned_version="${pinned_real_path##*/}"
          fi

          local opt_version=""
          local opt_path="${HOMEBREW_PREFIX}/opt/${rack##*/}"
          if [[ -L "${opt_path}" && -d "${opt_path}" ]]
          then
            local opt_real_path
            opt_real_path="$(realpath "${opt_path}")" || exit 1
            opt_version="${opt_real_path##*/}"
          fi

          local keg
          for keg in "${rack}"/*
          do
            [[ -d "${keg}" ]] || continue
            printf 'formula\t%s\t%s\t%s\t%s\t%s\n' \
              "${rack##*/}" "${keg##*/}" "${linked_version}" "${opt_version}" "${pinned_version}"
          done
        done
      fi

      if [[ -z "${formula}" && -d "${HOMEBREW_CASKROOM}" ]]
      then
        local cask_path
        for cask_path in "${HOMEBREW_CASKROOM}"/*
        do
          [[ -d "${cask_path}" ]] || continue

          local token="${cask_path##*/}"
          if [[ -L "${cask_path}" ]]
          then
            local real_cask_path
            real_cask_path="$(realpath "${cask_path}")" || exit 1
            token="${real_cask_path##*/}"
          fi

          local pinned_version=""
          local pinned_path="${HOMEBREW_PREFIX}/var/homebrew/pinned_casks/${token}"
          if [[ -L "${pinned_path}" && -d "${pinned_path}" ]]
          then
            local pinned_real_path
            pinned_real_path="$(realpath "${pinned_path}")" || exit 1
            pinned_version="${pinned_real_path##*/}"
          fi

          local version_path
          for version_path in "${cask_path}/.metadata"/*
          do
            [[ -d "${version_path}" ]] || continue

            local installed_cask_file=""
            local cask_file
            for cask_file in "${version_path}"/*/Casks/*.{rb,json}
            do
              [[ -e "${cask_file}" ]] || continue
              installed_cask_file=1
              break
            done
            [[ -n "${installed_cask_file}" ]] || continue

            printf 'cask\t%s\t%s\t\t\t%s\n' "${token}" "${version_path##*/}" "${pinned_version}"
          done
        done
      fi
    } | "${jq}" -Rnc '
      [inputs | split("\t")] |
      {
        formulae: (map(select(.[0] == "formula")) | group_by(.[1]) | map({
          name: .[0][1],
          versions: (map(.[2]) | unique),
          linked_version: (.[0][3] | if . == "" then null else . end),
          optlinked_version: (.[0][4] | if . == "" then null else . end),
          pinned_version: (.[0][5] | if . == "" then null else . end)
        })),
        casks: (map(select(.[0] == "cask")) | group_by(.[1]) | map({
          token: .[0][1],
          versions: (map(.[2]) | unique),
          pinned_version: (.[0][5] | if . == "" then null else . end)
        }))
      }
    '
    local json_status=$?
    if [[ -z "${pipefail}" ]]
    then
      set +o pipefail
    fi
    if ((json_status != 0))
    then
      exit 1
    fi
    return 0
  fi

  if [[ -n "${versions}" ]]
  then
    return 1
  fi

  if [[ -z "${cask}" && -d "${HOMEBREW_CELLAR}" ]]
  then
    local formula_output
    formula_output="$(/usr/bin/env "${ls_env[@]}" ls "${ls_args[@]}" "${HOMEBREW_CELLAR}")" || exit 1
    if [[ -n "${formula_output}" ]]
    then
      if [[ -n "${tty}" && -z "${formula}" ]]
      then
        ohai "Formulae"
      fi

      echo "${formula_output}"

      if [[ -n "${tty}" && -z "${formula}" ]]
      then
        echo
      fi
    fi
  fi

  if [[ -z "${formula}" && -d "${HOMEBREW_CASKROOM}" ]]
  then
    local cask_output
    cask_output="$(/usr/bin/env "${ls_env[@]}" ls "${ls_args[@]}" "${HOMEBREW_CASKROOM}")" || exit 1
    if [[ -n "${cask_output}" ]]
    then
      if [[ -n "${tty}" && -z "${cask}" ]]
      then
        ohai "Casks"
      fi

      echo "${cask_output}"
    fi

    # Keep in sync with Homebrew::Cmd::List#warn_about_broken_caskroom_symlinks
    # in Library/Homebrew/cmd/list.rb.
    local broken_cask_symlinks=()
    local cask_path
    for cask_path in "${HOMEBREW_CASKROOM}"/*
    do
      [[ -L "${cask_path}" && ! -e "${cask_path}" ]] || continue
      broken_cask_symlinks+=("${cask_path##*/}")
    done
    if ((${#broken_cask_symlinks[@]} > 0))
    then
      source "${HOMEBREW_LIBRARY}/Homebrew/utils.sh"
      local joined_broken_cask_symlinks
      printf -v joined_broken_cask_symlinks '%s, ' "${broken_cask_symlinks[@]}"
      opoo "Broken Caskroom symlinks (\`brew cleanup\` removes them): ${joined_broken_cask_symlinks%, }"
    fi

    return 0
  fi
}
