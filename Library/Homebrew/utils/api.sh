# API helpers for Homebrew's Bash scripts.

# HOMEBREW_API_DEFAULT_DOMAIN HOMEBREW_API_DOMAIN HOMEBREW_CURL HOMEBREW_CURLRC are set by brew.sh
# shellcheck disable=SC2154,SC2153
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

# `--etag-compare` and `--etag-save` were added in curl 7.68.0, which is newer
# than HOMEBREW_MINIMUM_CURL_VERSION, so fall back to `--time-cond` below when
# they are unavailable.
HOMEBREW_MINIMUM_CURL_ETAG_VERSION="7.68.0"

api_curl_supports_etag() {
  if [[ -z "${HOMEBREW_CURL_SUPPORTS_ETAG:-}" ]]
  then
    local curl_version_output curl_name_and_version
    curl_version_output="$("${HOMEBREW_CURL}" --version 2>/dev/null)"
    curl_name_and_version="${curl_version_output%% (*}"
    if [[ "$(numeric "${curl_name_and_version##* }")" -ge "$(numeric "${HOMEBREW_MINIMUM_CURL_ETAG_VERSION}")" ]]
    then
      HOMEBREW_CURL_SUPPORTS_ETAG="1"
    else
      HOMEBREW_CURL_SUPPORTS_ETAG="0"
    fi
  fi

  [[ "${HOMEBREW_CURL_SUPPORTS_ETAG}" == "1" ]]
}

api_etag_save_args() {
  local cache_path="$1"

  api_curl_supports_etag || return 0

  # Save to a scratch path rather than the stored ETag: curl empties the
  # `--etag-save` file when the server answers 304, which would make every
  # other request unconditional. `api_promote_etag` only keeps non-empty ones.
  echo "--etag-save"
  echo "${cache_path}.etag.incoming"
}

# Emit the curl arguments used to revalidate an already-cached API file.
#
# Prefer `If-None-Match` over `If-Modified-Since`. The cache file's mtime is
# also used as a "last checked at" marker by `skip_download?` in api.rb, so it
# is deliberately advanced to the current time after every successful
# revalidation. That makes the mtime unsafe as a validator: it can drift ahead
# of the `Last-Modified` of a newer object, after which every conditional
# request keeps returning 304 and the stale body is pinned indefinitely. An
# ETag is compared exactly, so it cannot drift in the same way.
api_conditional_args() {
  local cache_path="$1"
  local etag_path="${cache_path}.etag"

  if [[ -s "${cache_path}" ]]
  then
    if api_curl_supports_etag && [[ -s "${etag_path}" ]]
    then
      echo "--etag-compare"
      echo "${etag_path}"
    else
      api_time_cond_args "${cache_path}"
    fi
  fi

  api_etag_save_args "${cache_path}"
}

# Keep a newly received ETag, or retain the previous one when the server
# answered 304 (curl empties the `--etag-save` file in that case).
api_promote_etag() {
  local cache_path="$1"
  local incoming="${cache_path}.etag.incoming"

  if [[ -s "${incoming}" ]]
  then
    mv -f "${incoming}" "${cache_path}.etag"
  else
    rm -f "${incoming}"
  fi
}
