# API helpers for Homebrew's Bash scripts.

# HOMEBREW_API_DEFAULT_DOMAIN HOMEBREW_API_DOMAIN HOMEBREW_CURLRC are set by brew.sh
# shellcheck disable=SC2154
api_urls() {
  local filename="$1"

  if [[ -n "${HOMEBREW_API_DOMAIN:-}" && "${HOMEBREW_API_DOMAIN}" != "${HOMEBREW_API_DEFAULT_DOMAIN}" ]]
  then
    echo "${HOMEBREW_API_DOMAIN}/${filename}"
  fi
  echo "${HOMEBREW_API_DEFAULT_DOMAIN}/${filename}"
}

api_curlrc_args() {
  # HOMEBREW_CURLRC is optionally defined in the user environment.
  if [[ -z "${HOMEBREW_CURLRC:-}" ]]
  then
    echo "-q"
  elif [[ "${HOMEBREW_CURLRC}" == /* ]]
  then
    echo "-q"
    echo "--config"
    echo "${HOMEBREW_CURLRC}"
  fi
}

api_time_cond_args() {
  local cache_path="$1"

  if [[ -s "${cache_path}" ]]
  then
    echo "--time-cond"
    echo "${cache_path}"
  fi
}
