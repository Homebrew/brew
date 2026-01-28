# Setup analytics and delete old analytics UUIDs.
# HOMEBREW_LINUX, HOMEBREW_REPOSITORY is set by bin/brew
# HOMEBREW_NO_ANALYTICS is from the user environment.
# shellcheck disable=SC2154

setup-analytics() {
  local git_config_file="${HOMEBREW_REPOSITORY}/.git/config"

  local legacy_uuid_file="${HOME}/.homebrew_analytics_user_uuid"
  if [[ -f "${legacy_uuid_file}" ]]
  then
    rm -f "${legacy_uuid_file}"
  fi

  local user_uuid
  user_uuid="$(git config --file="${git_config_file}" --get homebrew.analyticsuuid 2>/dev/null)"
  if [[ -n "${user_uuid}" ]]
  then
    git config --file="${git_config_file}" --unset-all homebrew.analyticsuuid 2>/dev/null
  fi

  if [[ -n "${HOMEBREW_NO_ANALYTICS}" ]]
  then
    return
  fi

  local message_seen analytics_disabled
  message_seen="$(git config --file="${git_config_file}" --get homebrew.analyticsmessage 2>/dev/null)"
  analytics_disabled="$(git config --file="${git_config_file}" --get homebrew.analyticsdisabled 2>/dev/null)"
  if [[ "${message_seen}" != "true" || "${analytics_disabled}" == "true" ]]
  then
    # Internal variable for brew's use, to differentiate from user-supplied setting
    export HOMEBREW_NO_ANALYTICS_THIS_RUN="1"
    return
  fi
}
