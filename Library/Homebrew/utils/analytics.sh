# Setup analytics and delete old analytics UUIDs.
# HOMEBREW_GIT_CONFIG_FILE and HOMEBREW_GIT_CONFIG_ANALYTICS_* are parsed from
# the repository Git configuration by brew.sh.
# HOMEBREW_NO_ANALYTICS is from the user environment.
# shellcheck disable=SC2154
setup-analytics() {
  local legacy_uuid_file="${HOME}/.homebrew_analytics_user_uuid"
  if [[ -f "${legacy_uuid_file}" ]]
  then
    rm -f "${legacy_uuid_file}"
  fi

  if [[ -n "${HOMEBREW_GIT_CONFIG_ANALYTICS_UUID}" ]]
  then
    git config --file="${HOMEBREW_GIT_CONFIG_FILE}" --unset-all homebrew.analyticsuuid 2>/dev/null
  fi

  if [[ -n "${HOMEBREW_NO_ANALYTICS}" ]]
  then
    return
  fi

  if [[ "${HOMEBREW_GIT_CONFIG_ANALYTICS_MESSAGE_SEEN}" != "true" ||
        "${HOMEBREW_GIT_CONFIG_ANALYTICS_DISABLED}" == "true" ]]
  then
    # Internal variable for brew's use, to differentiate from user-supplied setting
    export HOMEBREW_NO_ANALYTICS_THIS_RUN="1"
    return
  fi
}
