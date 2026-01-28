# Documentation defined in Library/Homebrew/cmd/which-formula.rb

# HOMEBREW_CACHE is set by utils/ruby.sh
# HOMEBREW_LIBRARY is set by bin/brew
# HOMEBREW_API_DEFAULT_DOMAIN HOMEBREW_CURL_SPEED_LIMIT  HOMEBREW_CURL_SPEED_TIME HOMEBREW_USER_AGENT_CURL are set by brew.sh
# shellcheck disable=SC2154
ENDPOINT="internal/executables.txt"
DATABASE_FILE="${HOMEBREW_CACHE}/api/${ENDPOINT}"

is_formula_installed() {
  local name="$1"
  if [[ -d "${HOMEBREW_CELLAR}/${name}" ]]
  then
    return 0
  else
    return 1
  fi
}

is_file_fresh() {
  if [[ -n "${HOMEBREW_MACOS}" ]]
  then
    STAT_PRINTF=("/usr/bin/stat" "-f")
  else
    STAT_PRINTF=("/usr/bin/stat" "-c")
  fi

  local file_mtime
  local current_time
  local auto_update_secs

  file_mtime=$("${STAT_PRINTF[@]}" %m "${DATABASE_FILE}")
  current_time=$(date +%s)
  auto_update_secs=${HOMEBREW_API_AUTO_UPDATE_SECS:-450}

  [[ $((current_time - auto_update_secs)) -lt ${file_mtime} ]]
}

download_and_cache_executables_file() {
  source "${HOMEBREW_LIBRARY}/Homebrew/utils/helpers.sh"
  if [[ -s "${DATABASE_FILE}" ]] && ([[ -n "${HOMEBREW_SKIP_UPDATE}" ]] || is_file_fresh)
  then
    return
  else
    local url
    url="${HOMEBREW_API_DEFAULT_DOMAIN}/${ENDPOINT}"

    if [[ -n "${CI}" ]]
    then
      max_time=""
      retries="3"
    else
      max_time=10
      retries=0
    fi
    mkdir -p "${DATABASE_FILE%/*}"
    ${HOMEBREW_CURL} \
      --compressed \
      --speed-limit "${HOMEBREW_CURL_SPEED_LIMIT}" --speed-time "${HOMEBREW_CURL_SPEED_TIME}" \
      --location --remote-time --output "${DATABASE_FILE}" \
      ${max_time:+--max-time "${max_time}"} \
      ${retries:+--retry "${retries}" --retry-delay 0 --retry-max-time 60} \
      --user-agent "${HOMEBREW_USER_AGENT_CURL}" \
      "${url}"
    touch "${DATABASE_FILE}"

    git config --file="${HOMEBREW_REPOSITORY}/.git/config" --bool homebrew.commandnotfound true 2>/dev/null
  fi
}

homebrew-which-formula() {
  local args=()

  while [[ "$#" -gt 0 ]]
  do
    case "$1" in
      --explain)
        HOMEBREW_EXPLAIN=1
        shift
        ;;
      --skip-update)
        HOMEBREW_SKIP_UPDATE=1
        shift
        ;;
      --*)
        echo "Unknown option: $1" >&2
        brew help which-formula
        return 1
        ;;
      *)
        args+=("$1")
        shift
        ;;
    esac
  done

  if [[ ${#args[@]} -eq 0 ]]
  then
    brew help which-formula
    exit 1
  fi

  for cms in "${args[@]}"
  do
    download_and_cache_executables_file

    cmd="$(echo "${cms}" | tr '[:upper:]' '[:lower:]')"

    local formulae=()
    local formula cmds_text

    while IFS=':' read -r formula cmds_text
    do
      [[ -z "${formula}" ]] && continue
      [[ -z "${cmds_text}" ]] && continue

      if [[ " ${cmds_text} " == *" ${cmd} "* ]]
      then
        formula="${formula%\(*}"
        formulae+=("${formula}")
      fi
    done <"${DATABASE_FILE}" 2>/dev/null

    [[ ${#formulae[@]} -eq 0 ]] && return 1

    if [[ -n ${HOMEBREW_EXPLAIN} ]]
    then
      local filtered_formulae=()
      for formula in "${formulae[@]}"
      do
        if ! is_formula_installed "${formula}"
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
      printf '%s\n' "${formulae[@]}"
    fi
  done
}
