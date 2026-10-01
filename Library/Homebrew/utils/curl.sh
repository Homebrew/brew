# curl selection and version checks plus Homebrew's user agents.

# HOMEBREW_* variables set here are used across Homebrew's Bash scripts.
# shellcheck disable=SC2034
# These variables are set by bin/brew, brew.sh or the user environment.
# shellcheck disable=SC2154

# Ensure the system curl is a version that supports modern HTTPS certificates.
HOMEBREW_MINIMUM_CURL_VERSION="7.41.0"

# Timeout values to check for dead connections
# We don't use --max-time to support slow connections
HOMEBREW_CURL_SPEED_LIMIT=100
HOMEBREW_CURL_SPEED_TIME=5

setup_curl() {
  HOMEBREW_BREWED_CURL_PATH="${HOMEBREW_PREFIX}/opt/curl/bin/curl"
  if [[ -n "${HOMEBREW_FORCE_BREWED_CURL}" && -x "${HOMEBREW_BREWED_CURL_PATH}" ]] &&
     "${HOMEBREW_BREWED_CURL_PATH}" --version &>/dev/null
  then
    HOMEBREW_CURL="${HOMEBREW_BREWED_CURL_PATH}"
  elif [[ -n "${HOMEBREW_CURL_PATH}" ]]
  then
    HOMEBREW_CURL="${HOMEBREW_CURL_PATH}"
  else
    HOMEBREW_CURL="curl"
  fi
}

setup_ca_certificates() {
  if [[ -n "${HOMEBREW_FORCE_BREWED_CA_CERTIFICATES}" && -f "${HOMEBREW_PREFIX}/etc/ca-certificates/cert.pem" ]]
  then
    export SSL_CERT_FILE="${HOMEBREW_PREFIX}/etc/ca-certificates/cert.pem"
    export GIT_SSL_CAINFO="${HOMEBREW_PREFIX}/etc/ca-certificates/cert.pem"
    export GIT_SSL_CAPATH="${HOMEBREW_PREFIX}/etc/ca-certificates"
  fi
}

# Ensure the system curl is at or newer than the minimum required version.
check-curl-version() {
  [[ -z "${HOMEBREW_MACOS}" ]] || return 0

  local curl_version_output curl_name_and_version message
  curl_version_output="$(${HOMEBREW_CURL} --version 2>/dev/null)"
  curl_name_and_version="${curl_version_output%% (*}"
  if [[ "$(numeric "${curl_name_and_version##* }")" -lt "$(numeric "${HOMEBREW_MINIMUM_CURL_VERSION}")" ]]
  then
    message="Please update your system curl or set HOMEBREW_CURL_PATH to a newer version.
Minimum required version: ${HOMEBREW_MINIMUM_CURL_VERSION}
       Your curl version: ${curl_name_and_version##* }
    Your curl executable: $(type -p "${HOMEBREW_CURL}")"

    if [[ -z ${HOMEBREW_CURL_PATH} ]]
    then
      HOMEBREW_SYSTEM_CURL_TOO_OLD=1
      HOMEBREW_FORCE_BREWED_CURL=1
      if [[ -z ${HOMEBREW_CURL_WARNING} ]]
      then
        onoe "${message}"
        HOMEBREW_CURL_WARNING=1
      fi
    else
      odie "${message}"
    fi
  fi
}

setup-user-agents() {
  HOMEBREW_USER_AGENT="${HOMEBREW_PRODUCT}/${HOMEBREW_USER_AGENT_VERSION} (${HOMEBREW_SYSTEM}; ${HOMEBREW_PROCESSOR} ${HOMEBREW_OS_USER_AGENT_VERSION})"
  # With the filtered PATH set by bin/brew this resolves to the same curl the
  # shims/shared/curl shim would but without forking the shim script itself.
  local curl_version_output curl_name_and_version
  curl_version_output="$("${HOMEBREW_CURL}" --version 2>/dev/null)"
  curl_name_and_version="${curl_version_output%% (*}"
  HOMEBREW_USER_AGENT_CURL="${HOMEBREW_USER_AGENT} ${curl_name_and_version// //}"
}
