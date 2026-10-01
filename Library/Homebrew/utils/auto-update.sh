# Auto-update before commands that need up-to-date formula and cask data.

# These variables are set by bin/brew, brew.sh or the user environment.
# shellcheck disable=SC2154

# NOTE: The members of the array in the second arg must not have spaces!
check-array-membership() {
  local item=$1
  shift

  if [[ " ${*} " == *" ${item} "* ]]
  then
    return 0
  else
    return 1
  fi
}

auto-update() {
  [[ -z "${HOMEBREW_HELP}" ]] || return
  [[ -z "${HOMEBREW_NO_AUTO_UPDATE}" ]] || return
  [[ -z "${HOMEBREW_AUTO_UPDATING}" ]] || return
  [[ -z "${HOMEBREW_UPDATE_AUTO}" ]] || return
  [[ -z "${HOMEBREW_AUTO_UPDATE_CHECKED}" ]] || return
  # Worktrees may share Git metadata with another checkout, so skip background updates.
  [[ ! -f "${HOMEBREW_REPOSITORY}/.git" ]] || return

  # If we've checked for updates, we don't need to check again.
  export HOMEBREW_AUTO_UPDATE_CHECKED="1"

  if [[ -n "${HOMEBREW_AUTO_UPDATE_COMMAND}" ]]
  then
    export HOMEBREW_AUTO_UPDATING="1"

    # Look for commands that may be referring to a formula/cask in a specific
    # 3rd-party tap so they can be auto-updated more often (as they do not get
    # their data from the API).
    AUTO_UPDATE_TAP_COMMANDS=(
      install
      outdated
      upgrade
    )
    if check-array-membership "${HOMEBREW_COMMAND}" "${AUTO_UPDATE_TAP_COMMANDS[@]}"
    then
      for arg in "$@"
      do
        if [[ "${arg}" == */*/* ]] && [[ "${arg}" != Homebrew/* ]] && [[ "${arg}" != homebrew/* ]]
        then

          HOMEBREW_AUTO_UPDATE_TAP="1"
          break
        fi
      done
    fi

    # When auto-updating before a zero-argument `brew upgrade` or `brew outdated`,
    # that command lists the outdated packages itself so skip doing so here too.
    # Two-way sync: `dump` in `Library/Homebrew/cmd/update_report/reporter_hub.rb`.
    if [[ "${HOMEBREW_COMMAND}" == "upgrade" || "${HOMEBREW_COMMAND}" == "outdated" ]]
    then
      HOMEBREW_AUTO_UPDATE_SKIP_OUTDATED="1"
      for arg in "${@:2}"
      do
        [[ "${arg}" == -* ]] && continue
        HOMEBREW_AUTO_UPDATE_SKIP_OUTDATED=""
        break
      done
      [[ -n "${HOMEBREW_AUTO_UPDATE_SKIP_OUTDATED}" ]] && export HOMEBREW_AUTO_UPDATE_SKIP_OUTDATED
    fi

    # Keep in sync with the HOMEBREW_AUTO_UPDATE_SECS default in
    # Library/Homebrew/env_config.rb.
    if [[ -z "${HOMEBREW_AUTO_UPDATE_SECS}" ]]
    then
      if [[ -n "${HOMEBREW_NO_INSTALL_FROM_API}" || -n "${HOMEBREW_AUTO_UPDATE_TAP}" ]]
      then
        # 5 minutes
        HOMEBREW_AUTO_UPDATE_SECS="300"
      elif [[ -n "${HOMEBREW_DEV_CMD_RUN}" ]]
      then
        # 1 hour
        HOMEBREW_AUTO_UPDATE_SECS="3600"
      else
        # 24 hours
        HOMEBREW_AUTO_UPDATE_SECS="86400"
      fi
    fi

    repo_fetch_heads=("${HOMEBREW_REPOSITORY}/.git/FETCH_HEAD")
    # We might have done an auto-update recently, but not a core/cask clone auto-update.
    # So we check the core/cask clone FETCH_HEAD too.
    if [[ -n "${HOMEBREW_AUTO_UPDATE_CORE_TAP}" && -d "${HOMEBREW_CORE_REPOSITORY}/.git" ]]
    then
      repo_fetch_heads+=("${HOMEBREW_CORE_REPOSITORY}/.git/FETCH_HEAD")
    fi
    if [[ -n "${HOMEBREW_AUTO_UPDATE_CASK_TAP}" && -d "${HOMEBREW_CASK_REPOSITORY}/.git" ]]
    then
      repo_fetch_heads+=("${HOMEBREW_CASK_REPOSITORY}/.git/FETCH_HEAD")
    fi

    # Skip auto-update if all of the selected repositories have been checked in the
    # last $HOMEBREW_AUTO_UPDATE_SECS.
    needs_auto_update=
    for repo_fetch_head in "${repo_fetch_heads[@]}"
    do
      if [[ ! -f "${repo_fetch_head}" ]] ||
         [[ -z "$(find "${repo_fetch_head}" -type f -newermt "-${HOMEBREW_AUTO_UPDATE_SECS} seconds" 2>/dev/null)" ]]
      then
        needs_auto_update=1
        break
      fi
    done
    if [[ -z "${needs_auto_update}" ]]
    then
      unset HOMEBREW_AUTO_UPDATE_SKIP_OUTDATED
      return
    fi

    brew update --auto-update

    unset HOMEBREW_AUTO_UPDATING
    unset HOMEBREW_AUTO_UPDATE_TAP
    unset HOMEBREW_AUTO_UPDATE_SKIP_OUTDATED

    if [[ $# -gt 0 ]]
    then
      # exec a new process to set any new environment variables.
      exec "${HOMEBREW_BREW_FILE}" "$@"
    fi
  fi

  unset HOMEBREW_AUTO_UPDATE_CORE_TAP
  unset HOMEBREW_AUTO_UPDATE_CASK_TAP
}

# Classify HOMEBREW_COMMAND for auto-update: whether it should run at all and
# whether the homebrew-core or homebrew-cask taps should also be updated.
setup-auto-update() {
  local AUTO_UPDATE_COMMANDS AUTO_UPDATE_CORE_TAP_COMMANDS AUTO_UPDATE_CASK_TAP_COMMANDS

  unset HOMEBREW_AUTO_UPDATE_COMMAND

  # Check for commands that should call `brew update --auto-update` first.
  AUTO_UPDATE_COMMANDS=(
    install
    outdated
    upgrade
    bundle
    release
  )
  if check-array-membership "${HOMEBREW_COMMAND}" "${AUTO_UPDATE_COMMANDS[@]}" ||
     [[ "${HOMEBREW_COMMAND}" == "tap" && "${HOMEBREW_ARG_COUNT}" -gt 1 ]]
  then
    export HOMEBREW_AUTO_UPDATE_COMMAND="1"
  fi

  # Check for commands that should auto-update the homebrew-core tap.
  AUTO_UPDATE_CORE_TAP_COMMANDS=(
    bump
    bump-formula-pr
  )
  if check-array-membership "${HOMEBREW_COMMAND}" "${AUTO_UPDATE_CORE_TAP_COMMANDS[@]}"
  then
    export HOMEBREW_AUTO_UPDATE_COMMAND="1"
    export HOMEBREW_AUTO_UPDATE_CORE_TAP="1"
  elif [[ -z "${HOMEBREW_AUTO_UPDATING}" ]]
  then
    unset HOMEBREW_AUTO_UPDATE_CORE_TAP
  fi

  # Check for commands that should auto-update the homebrew-cask tap.
  AUTO_UPDATE_CASK_TAP_COMMANDS=(
    bump
    bump-cask-pr
    bump-unversioned-casks
  )
  if check-array-membership "${HOMEBREW_COMMAND}" "${AUTO_UPDATE_CASK_TAP_COMMANDS[@]}"
  then
    export HOMEBREW_AUTO_UPDATE_COMMAND="1"
    export HOMEBREW_AUTO_UPDATE_CASK_TAP="1"
  elif [[ -z "${HOMEBREW_AUTO_UPDATING}" ]]
  then
    unset HOMEBREW_AUTO_UPDATE_CASK_TAP
  fi
}
