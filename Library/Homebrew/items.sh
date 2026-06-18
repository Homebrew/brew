# `opoo` is defined in utils.sh, which the early `formulae`/`casks` dispatch in
# brew.sh runs before sourcing, so source it here for these commands.
# HOMEBREW_LIBRARY is set by bin/brew
# shellcheck disable=SC2154
source "${HOMEBREW_LIBRARY}/Homebrew/utils.sh"

homebrew-items() {
  local items
  local find_include_filter="$1"
  local find_exclude_filter="$2"
  local sed_filter="$3"
  local grep_filter="$4"
  local sed_extended_regex_flag

  # HOMEBREW_MACOS is set by brew.sh
  # shellcheck disable=SC2154
  if [[ -n "${HOMEBREW_MACOS}" ]]
  then
    sed_extended_regex_flag="-E"
  else
    sed_extended_regex_flag="-r"
  fi

  items="$(homebrew-items-paths "${find_include_filter}" "${find_exclude_filter}" |
    sed "${sed_extended_regex_flag}" \
      -e 's/\.rb//g' \
      -e 's_.*/Taps/(.*)/(home|linux)brew-_\1/_' \
      -e "${sed_filter}")"
  local shortnames
  shortnames="$(echo "${items}" | cut -d "/" -f 3)"
  echo -e "${items}\n${shortnames}" |
    grep -v "${grep_filter}" |
    sort -uf
}

homebrew-trusted-items() {
  local find_include_filter="$1"
  local find_exclude_filter="$2"
  local trust_key="$3"
  local official_tap="$4"
  local item_dir="$5"
  local items
  local jq
  # HOMEBREW_USER_CONFIG_HOME is set by brew.sh
  # shellcheck disable=SC2154
  local trust_file="${HOMEBREW_USER_CONFIG_HOME}/trust.json"
  # shellcheck disable=SC2016
  local trust_filter='
    select(type == "string") |
    capture(".*/Taps/(?<user>[^/]+)/(?:home|linux)brew-(?<tap>[^/]+)/" + $item_dir + "/(?:.*/)?(?<name>[^/]+)\\.rb$")? |
    select(. != null) |
    "\(.user)/\(.tap)/\(.name)" as $item |
    ($item | split("/") | .[0:2] | join("/")) as $tap |
    ($tap_references[$tap] // $tap) as $tap_reference |
    "\($tap_reference)/\(.name)" as $remote_item |
    select(
      $tap == $official_tap or
      (($store.trustedtaps // []) | (index($tap) or index($tap_reference))) or
      (($store[$trust_key] // []) | (index($item) or index($remote_item)))
    ) |
    $item
  '
  # shellcheck disable=SC2016
  local untrusted_tap_filter='
    select(type == "string") |
    capture(".*/Taps/(?<user>[^/]+)/(?:home|linux)brew-(?<tap>[^/]+)/" + $item_dir + "/(?:.*/)?(?<name>[^/]+)\\.rb$")? |
    select(. != null) |
    "\(.user)/\(.tap)/\(.name)" as $item |
    ($item | split("/") | .[0:2] | join("/")) as $tap |
    ($tap_references[$tap] // $tap) as $tap_reference |
    "\($tap_reference)/\(.name)" as $remote_item |
    select(
      $tap != $official_tap and
      (($store.trustedtaps // []) | (index($tap) or index($tap_reference)) | not) and
      (($store[$trust_key] // []) | (index($item) or index($remote_item)) | not)
    ) |
    $tap
  '

  if ! jq="$(type -P jq)" && [[ -n "${HOMEBREW_PATH:-}" ]]
  then
    jq="$(PATH="${HOMEBREW_PATH}" type -P jq)"
  fi
  [[ -x "${jq}" ]] || return 1

  items="$(homebrew-items-paths "${find_include_filter}" "${find_exclude_filter}")"
  [[ -n "${items}" ]] || return 0

  local store='{}'
  if [[ -f "${trust_file}" ]]
  then
    store="$("${jq}" -c 'if type == "object" then . else {} end' "${trust_file}")" || store='{}'
  fi

  local tap_references
  # The JQ programs below need literal `$...` variables for JQ, not shell expansions.
  # shellcheck disable=SC2016
  tap_references="$(
    while IFS=$'\t' read -r tap tap_path
    do
      [[ -n "${tap}" && -d "${tap_path}" ]] || continue

      local remote
      if remote="$(git -C "${tap_path}" config --get remote.origin.url 2>/dev/null)"
      then
        printf "%s\t%s\n" "${tap}" "${remote}" | tr "[:upper:]" "[:lower:]"
      else
        printf "%s\t%s\n" "${tap}" "${tap}"
      fi
    done < <(
      echo "${items}" | "${jq}" -Rr --arg item_dir "${item_dir}" '
        capture("(?<path>.*/Taps/(?<user>[^/]+)/(?:home|linux)brew-(?<tap>[^/]+))/" + $item_dir + "/.*")? |
        select(. != null) |
        "\(.user)/\(.tap)\t\(.path)"
      ' | sort -u
    ) | "${jq}" -Rnc '
      reduce inputs as $line ({};
        ($line | split("\t")) as $parts |
        .[$parts[0]] = $parts[1]
      )
    '
  )"

  if [[ -z "${HOMEBREW_COMPLETION:-}" ]]
  then
    local tap
    while read -r tap
    do
      [[ -n "${tap}" ]] || continue
      opoo "Skipping ${tap} because it is not trusted. Run \`brew trust ${tap}\` to trust it."
    done < <(echo "${items}" | "${jq}" -Rr --argjson store "${store}" --arg trust_key "${trust_key}" \
      --arg official_tap "${official_tap}" --arg item_dir "${item_dir}" \
      --argjson tap_references "${tap_references}" "${untrusted_tap_filter}" | sort -u)
  fi

  local trusted
  trusted="$(echo "${items}" | "${jq}" -Rr --argjson store "${store}" --arg trust_key "${trust_key}" \
    --arg official_tap "${official_tap}" --arg item_dir "${item_dir}" \
    --argjson tap_references "${tap_references}" "${trust_filter}")"
  local shortnames
  shortnames="$(echo "${trusted}" | cut -d "/" -f 3)"
  echo -e "${trusted}\n${shortnames}" | sort -uf
}

homebrew-trusted-items-with-api-names() {
  local find_include_filter="$1"
  local find_exclude_filter="$2"
  local trust_key="$3"
  local official_tap="$4"
  local item_dir="$5"
  local api_names_file="$6"
  local trusted_items

  trusted_items="$(homebrew-trusted-items "${find_include_filter}" "${find_exclude_filter}" \
    "${trust_key}" "${official_tap}" "${item_dir}")" || return 1

  # HOMEBREW_CACHE is set by brew.sh
  # shellcheck disable=SC2154
  if [[ -z "${HOMEBREW_NO_INSTALL_FROM_API}" &&
        -f "${HOMEBREW_CACHE}/api/${api_names_file}" ]]
  then
    {
      cat "${HOMEBREW_CACHE}/api/${api_names_file}"
      echo
      echo "${trusted_items}"
    } | sort -uf
  else
    echo "${trusted_items}"
  fi
}

homebrew-items-paths() {
  local find_args
  local find_include_filter="$1"
  local find_exclude_filter="$2"

  # HOMEBREW_MACOS is set by brew.sh
  # shellcheck disable=SC2154
  if [[ -n "${HOMEBREW_MACOS}" ]]
  then
    find_args=("-E" "${HOMEBREW_REPOSITORY}/Library/Taps")
  else
    find_args=("${HOMEBREW_REPOSITORY}/Library/Taps" "-regextype" "posix-extended")
  fi

  # HOMEBREW_REPOSITORY is set by brew.sh
  # shellcheck disable=SC2154
  [[ -d "${HOMEBREW_REPOSITORY}/Library/Taps" ]] || return
  find "${find_args[@]}" \
    -type d \( \
    -regex "${find_exclude_filter}" -o \
    -name cmd -o \
    -name .github -o \
    \( -name lib -a ! -path '*/Formula/*' -a ! -path '*/Casks/*' \) -o \
    -name spec -o \
    -name vendor -o \
    -name .git \
    \) \
    -prune -false -o -path "${find_include_filter}"
}

homebrew-tap-trust-required() {
  [[ -n "${HOMEBREW_NO_REQUIRE_TAP_TRUST:-}" ]] && return 1

  return 0
}
