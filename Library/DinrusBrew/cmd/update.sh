# Documentation defined in Library/DinrusBrew/cmd/update.rb

# DINRUSBREW_API_DOMAIN, DINRUSBREW_CURLRC, DINRUSBREW_DEBUG, DINRUSBREW_DEVELOPER, DINRUSBREW_GIT_EMAIL, DINRUSBREW_GIT_NAME,
# DINRUSBREW_GITHUB_API_TOKEN, DINRUSBREW_NO_ENV_HINTS, DINRUSBREW_NO_INSTALL_CLEANUP, DINRUSBREW_NO_INSTALL_FROM_API,
# DINRUSBREW_UPDATE_TO_TAG are from the user environment
# DINRUSBREW_LIBRARY, DINRUSBREW_PREFIX, DINRUSBREW_REPOSITORY are set by bin/brew
# DINRUSBREW_API_DEFAULT_DOMAIN, DINRUSBREW_AUTO_UPDATE_CASK_TAP, DINRUSBREW_AUTO_UPDATE_CORE_TAP,
# DINRUSBREW_AUTO_UPDATE_SECS, DINRUSBREW_BREW_DEFAULT_GIT_REMOTE, DINRUSBREW_BREW_GIT_REMOTE, DINRUSBREW_CACHE,
# DINRUSBREW_CASK_REPOSITORY, DINRUSBREW_CELLAR, DINRUSBREW_CORE_DEFAULT_GIT_REMOTE, DINRUSBREW_CORE_GIT_REMOTE,
# DINRUSBREW_CORE_REPOSITORY, DINRUSBREW_CURL, DINRUSBREW_DEV_CMD_RUN, DINRUSBREW_FORCE_BREWED_CA_CERTIFICATES,
# DINRUSBREW_FORCE_BREWED_CURL, DINRUSBREW_FORCE_BREWED_GIT, DINRUSBREW_LINUXBREW_CORE_MIGRATION,
# DINRUSBREW_SYSTEM_CURL_TOO_OLD, DINRUSBREW_USER_AGENT_CURL are set by brew.sh
# shellcheck disable=SC2154
source "${DINRUSBREW_LIBRARY}/DinrusBrew/utils/lock.sh"

# Replaces the function in Library/DinrusBrew/brew.sh to cache the Curl/Git executable to
# provide speedup when using Curl/Git repeatedly (as update.sh does).
curl() {
  if [[ -z "${CURL_EXECUTABLE}" ]]
  then
    CURL_EXECUTABLE="$("${DINRUSBREW_LIBRARY}/DinrusBrew/shims/shared/curl" --homebrew=print-path)"
    if [[ -z "${CURL_EXECUTABLE}" ]]
    then
      odie "Can't find a working Curl!"
    fi
  fi
  "${CURL_EXECUTABLE}" "$@"
}

git() {
  if [[ -z "${GIT_EXECUTABLE}" ]]
  then
    GIT_EXECUTABLE="$("${DINRUSBREW_LIBRARY}/DinrusBrew/shims/shared/git" --homebrew=print-path)"
    if [[ -z "${GIT_EXECUTABLE}" ]]
    then
      odie "Can't find a working Git!"
    fi
  fi
  "${GIT_EXECUTABLE}" "$@"
}

git_init_if_necessary() {
  safe_cd "${DINRUSBREW_REPOSITORY}"
  if [[ ! -d ".git" ]]
  then
    set -e
    trap '{ rm -rf .git; exit 1; }' EXIT
    git init
    git config --bool core.autocrlf false
    git config --bool core.symlinks true
    if [[ "${DINRUSBREW_BREW_DEFAULT_GIT_REMOTE}" != "${DINRUSBREW_BREW_GIT_REMOTE}" ]]
    then
      echo "DINRUSBREW_BREW_GIT_REMOTE set: using ${DINRUSBREW_BREW_GIT_REMOTE} as the DinrusBrew/brew Git remote."
    fi
    git config remote.origin.url "${DINRUSBREW_BREW_GIT_REMOTE}"
    git config remote.origin.fetch "+refs/heads/*:refs/remotes/origin/*"
    git fetch --force --tags origin
    git remote set-head origin --auto >/dev/null
    git reset --hard origin/master
    SKIP_FETCH_BREW_REPOSITORY=1
    set +e
    trap - EXIT
  fi

  [[ -d "${DINRUSBREW_CORE_REPOSITORY}" ]] || return
  safe_cd "${DINRUSBREW_CORE_REPOSITORY}"
  if [[ ! -d ".git" ]]
  then
    set -e
    trap '{ rm -rf .git; exit 1; }' EXIT
    git init
    git config --bool core.autocrlf false
    git config --bool core.symlinks true
    if [[ "${DINRUSBREW_CORE_DEFAULT_GIT_REMOTE}" != "${DINRUSBREW_CORE_GIT_REMOTE}" ]]
    then
      echo "DINRUSBREW_CORE_GIT_REMOTE set: using ${DINRUSBREW_CORE_GIT_REMOTE} as the DinrusBrew/homebrew-core Git remote."
    fi
    git config remote.origin.url "${DINRUSBREW_CORE_GIT_REMOTE}"
    git config remote.origin.fetch "+refs/heads/*:refs/remotes/origin/*"
    git fetch --force origin refs/heads/master:refs/remotes/origin/master
    git remote set-head origin --auto >/dev/null
    git reset --hard origin/master
    SKIP_FETCH_CORE_REPOSITORY=1
    set +e
    trap - EXIT
  fi
}

repository_var_suffix() {
  local repository_directory="${1}"
  local repository_var_suffix

  if [[ "${repository_directory}" == "${DINRUSBREW_REPOSITORY}" ]]
  then
    repository_var_suffix=""
  else
    repository_var_suffix="${repository_directory#"${DINRUSBREW_LIBRARY}/Taps"}"
    repository_var_suffix="$(echo -n "${repository_var_suffix}" | tr -C "A-Za-z0-9" "_" | tr "[:lower:]" "[:upper:]")"
  fi
  echo "${repository_var_suffix}"
}

upstream_branch() {
  local upstream_branch

  upstream_branch="$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null)"
  if [[ -z "${upstream_branch}" ]]
  then
    git remote set-head origin --auto >/dev/null
    upstream_branch="$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null)"
  fi
  upstream_branch="${upstream_branch#refs/remotes/origin/}"
  [[ -z "${upstream_branch}" ]] && upstream_branch="master"
  echo "${upstream_branch}"
}

read_current_revision() {
  git rev-parse -q --verify HEAD
}

pop_stash() {
  [[ -z "${STASHED}" ]] && return
  if [[ -n "${DINRUSBREW_VERBOSE}" ]]
  then
    echo "Restoring your stashed changes to ${DIR}..."
    git stash pop
  else
    git stash pop "${QUIET_ARGS[@]}" 1>/dev/null
  fi
  unset STASHED
}

pop_stash_message() {
  [[ -z "${STASHED}" ]] && return
  echo "To restore the stashed changes to ${DIR}, run:"
  echo "  cd ${DIR} && git stash pop"
  unset STASHED
}

reset_on_interrupt() {
  if [[ "${INITIAL_BRANCH}" != "${UPSTREAM_BRANCH}" && -n "${INITIAL_BRANCH}" ]]
  then
    git checkout "${INITIAL_BRANCH}" "${QUIET_ARGS[@]}"
  fi

  if [[ -n "${INITIAL_REVISION}" ]]
  then
    git rebase --abort &>/dev/null
    git merge --abort &>/dev/null
    git reset --hard "${INITIAL_REVISION}" "${QUIET_ARGS[@]}"
  fi

  if [[ -n "${DINRUSBREW_NO_UPDATE_CLEANUP}" ]]
  then
    pop_stash
  else
    pop_stash_message
  fi

  exit 130
}

# Used for testing purposes, e.g. for testing formula migration after
# renaming it in the currently checked-out branch. To test run
# "brew update --simulate-from-current-branch"
simulate_from_current_branch() {
  local DIR
  local TAP_VAR
  local UPSTREAM_BRANCH
  local CURRENT_REVISION

  DIR="$1"
  cd "${DIR}" || return
  TAP_VAR="$2"
  UPSTREAM_BRANCH="$3"
  CURRENT_REVISION="$4"

  INITIAL_REVISION="$(git rev-parse -q --verify "${UPSTREAM_BRANCH}")"
  export DINRUSBREW_UPDATE_BEFORE"${TAP_VAR}"="${INITIAL_REVISION}"
  export DINRUSBREW_UPDATE_AFTER"${TAP_VAR}"="${CURRENT_REVISION}"
  if [[ "${INITIAL_REVISION}" != "${CURRENT_REVISION}" ]]
  then
    DINRUSBREW_UPDATED="1"
  fi
  if ! git merge-base --is-ancestor "${INITIAL_REVISION}" "${CURRENT_REVISION}"
  then
    odie "Your ${DIR} HEAD is not a descendant of ${UPSTREAM_BRANCH}!"
  fi
}

merge_or_rebase() {
  if [[ -n "${DINRUSBREW_VERBOSE}" ]]
  then
    echo "Updating ${DIR}..."
  fi

  local DIR
  local TAP_VAR
  local UPSTREAM_BRANCH

  DIR="$1"
  cd "${DIR}" || return
  TAP_VAR="$2"
  UPSTREAM_BRANCH="$3"
  unset STASHED

  trap reset_on_interrupt SIGINT

  if [[ "${DIR}" == "${DINRUSBREW_REPOSITORY}" && -n "${DINRUSBREW_UPDATE_TO_TAG}" ]]
  then
    UPSTREAM_TAG="$(
      git tag --list |
        sort --field-separator=. --key=1,1nr -k 2,2nr -k 3,3nr |
        grep --max-count=1 '^[0-9]*\.[0-9]*\.[0-9]*$'
    )"
  else
    UPSTREAM_TAG=""
  fi

  if [[ -n "${UPSTREAM_TAG}" ]]
  then
    REMOTE_REF="refs/tags/${UPSTREAM_TAG}"
    UPSTREAM_BRANCH="stable"
  else
    REMOTE_REF="origin/${UPSTREAM_BRANCH}"
  fi

  if [[ -n "$(git status --untracked-files=all --porcelain 2>/dev/null)" ]]
  then
    if [[ -n "${DINRUSBREW_VERBOSE}" ]]
    then
      echo "Stashing uncommitted changes to ${DIR}..."
    fi
    git merge --abort &>/dev/null
    git rebase --abort &>/dev/null
    git reset --mixed "${QUIET_ARGS[@]}"
    if ! git -c "user.email=brew-update@localhost" \
       -c "user.name=brew update" \
       stash save --include-untracked "${QUIET_ARGS[@]}"
    then
      odie <<EOS
Could not 'git stash' in ${DIR}!
Please stash/commit manually if you need to keep your changes or, if not, run:
  cd ${DIR}
  git reset --hard origin/master
EOS
    fi
    git reset --hard "${QUIET_ARGS[@]}"
    STASHED="1"
  fi

  INITIAL_BRANCH="$(git symbolic-ref --short HEAD 2>/dev/null)"
  if [[ -n "${UPSTREAM_TAG}" ]] ||
     [[ "${INITIAL_BRANCH}" != "${UPSTREAM_BRANCH}" && -n "${INITIAL_BRANCH}" ]]
  then
    # Recreate and check out `#{upstream_branch}` if unable to fast-forward
    # it to `origin/#{@upstream_branch}`. Otherwise, just check it out.
    if [[ -z "${UPSTREAM_TAG}" ]] &&
       git merge-base --is-ancestor "${UPSTREAM_BRANCH}" "${REMOTE_REF}" &>/dev/null
    then
      git checkout --force "${UPSTREAM_BRANCH}" "${QUIET_ARGS[@]}"
    else
      if [[ -n "${UPSTREAM_TAG}" && "${UPSTREAM_BRANCH}" != "master" ]] &&
         [[ "${INITIAL_BRANCH}" != "master" ]]
      then
        git branch --force "master" "origin/master" "${QUIET_ARGS[@]}"
      fi

      git checkout --force -B "${UPSTREAM_BRANCH}" "${REMOTE_REF}" "${QUIET_ARGS[@]}"
    fi
  fi

  INITIAL_REVISION="$(read_current_revision)"
  export DINRUSBREW_UPDATE_BEFORE"${TAP_VAR}"="${INITIAL_REVISION}"

  # ensure we don't munge line endings on checkout
  git config --bool core.autocrlf false

  # make sure symlinks are saved as-is
  git config --bool core.symlinks true

  if [[ "${DIR}" == "${DINRUSBREW_CORE_REPOSITORY}" && -n "${DINRUSBREW_LINUXBREW_CORE_MIGRATION}" ]]
  then
    # Don't even try to rebase/merge on linuxbrew-core migration but rely on
    # stashing etc. above.
    git reset --hard "${QUIET_ARGS[@]}" "${REMOTE_REF}"
    unset DINRUSBREW_LINUXBREW_CORE_MIGRATION
  elif [[ -z "${DINRUSBREW_MERGE}" ]]
  then
    # Work around bug where git rebase --quiet is not quiet
    if [[ -z "${DINRUSBREW_VERBOSE}" ]]
    then
      git rebase "${QUIET_ARGS[@]}" "${REMOTE_REF}" >/dev/null
    else
      git rebase "${QUIET_ARGS[@]}" "${REMOTE_REF}"
    fi
  else
    git merge --no-edit --ff "${QUIET_ARGS[@]}" "${REMOTE_REF}" \
      --strategy=recursive \
      --strategy-option=ours \
      --strategy-option=ignore-all-space
  fi

  CURRENT_REVISION="$(read_current_revision)"
  export DINRUSBREW_UPDATE_AFTER"${TAP_VAR}"="${CURRENT_REVISION}"

  if [[ "${INITIAL_REVISION}" != "${CURRENT_REVISION}" ]]
  then
    DINRUSBREW_UPDATED="1"
  fi

  trap '' SIGINT

  if [[ -n "${DINRUSBREW_NO_UPDATE_CLEANUP}" ]]
  then
    if [[ "${INITIAL_BRANCH}" != "${UPSTREAM_BRANCH}" && -n "${INITIAL_BRANCH}" ]] &&
       [[ ! "${INITIAL_BRANCH}" =~ ^v[0-9]+\.[0-9]+\.[0-9]|stable$ ]]
    then
      git checkout "${INITIAL_BRANCH}" "${QUIET_ARGS[@]}"
    fi

    pop_stash
  else
    pop_stash_message
  fi

  trap - SIGINT
}

homebrew-update() {
  local option
  local DIR
  local UPSTREAM_BRANCH

  for option in "$@"
  do
    case "${option}" in
      -\? | -h | --help | --usage)
        brew help update
        exit $?
        ;;
      --verbose) DINRUSBREW_VERBOSE=1 ;;
      --debug) DINRUSBREW_DEBUG=1 ;;
      --quiet) DINRUSBREW_QUIET=1 ;;
      --merge)
        shift
        DINRUSBREW_MERGE=1
        ;;
      --force) DINRUSBREW_UPDATE_FORCE=1 ;;
      --simulate-from-current-branch)
        shift
        DINRUSBREW_SIMULATE_FROM_CURRENT_BRANCH=1
        ;;
      --auto-update) export DINRUSBREW_UPDATE_AUTO=1 ;;
      --*)
        onoe "Unknown option: ${option}"
        brew help update
        exit 1
        ;;
      -*)
        [[ "${option}" == *v* ]] && DINRUSBREW_VERBOSE=1
        [[ "${option}" == *q* ]] && DINRUSBREW_QUIET=1
        [[ "${option}" == *d* ]] && DINRUSBREW_DEBUG=1
        [[ "${option}" == *f* ]] && DINRUSBREW_UPDATE_FORCE=1
        ;;
      *)
        odie <<EOS
This command updates brew itself, and does not take formula names.
Use \`brew upgrade $@\` instead.
EOS
        ;;
    esac
  done

  if [[ -n "${DINRUSBREW_DEBUG}" ]]
  then
    set -x
  fi

  if [[ -z "${DINRUSBREW_UPDATE_TO_TAG}" ]]
  then
    if [[ -n "${DINRUSBREW_DEVELOPER}" || -n "${DINRUSBREW_DEV_CMD_RUN}" ]]
    then
      export DINRUSBREW_NO_UPDATE_CLEANUP="1"
    else
      export DINRUSBREW_UPDATE_TO_TAG="1"
    fi
  fi

  # check permissions
  if [[ -e "${DINRUSBREW_CELLAR}" && ! -w "${DINRUSBREW_CELLAR}" ]]
  then
    odie <<EOS
${DINRUSBREW_CELLAR} is not writable. You should change the
ownership and permissions of ${DINRUSBREW_CELLAR} back to your
user account:
  sudo chown -R ${USER-\$(whoami)} ${DINRUSBREW_CELLAR}
EOS
  fi

  if [[ -d "${DINRUSBREW_CORE_REPOSITORY}" ]] ||
     [[ -z "${DINRUSBREW_NO_INSTALL_FROM_API}" ]]
  then
    DINRUSBREW_CORE_AVAILABLE="1"
  fi

  if [[ ! -w "${DINRUSBREW_REPOSITORY}" ]]
  then
    odie <<EOS
${DINRUSBREW_REPOSITORY} is not writable. You should change the
ownership and permissions of ${DINRUSBREW_REPOSITORY} back to your
user account:
  sudo chown -R ${USER-\$(whoami)} ${DINRUSBREW_REPOSITORY}
EOS
  fi

  # we may want to use DinrusBrew CA certificates
  if [[ -n "${DINRUSBREW_FORCE_BREWED_CA_CERTIFICATES}" && ! -f "${DINRUSBREW_PREFIX}/etc/ca-certificates/cert.pem" ]]
  then
    # we cannot install DinrusBrew CA certificates if homebrew/core is unavailable.
    if [[ -n "${DINRUSBREW_CORE_AVAILABLE}" ]]
    then
      brew install ca-certificates
      setup_ca_certificates
    fi
  fi

  # we may want to use a DinrusBrew curl
  if [[ -n "${DINRUSBREW_FORCE_BREWED_CURL}" && ! -x "${DINRUSBREW_PREFIX}/opt/curl/bin/curl" ]]
  then
    # we cannot install a DinrusBrew cURL if homebrew/core is unavailable.
    if [[ -z "${DINRUSBREW_CORE_AVAILABLE}" ]] || ! brew install curl
    then
      odie "'curl' must be installed and in your PATH!"
    fi

    setup_curl
  fi

  if ! git --version &>/dev/null ||
     [[ -n "${DINRUSBREW_FORCE_BREWED_GIT}" && ! -x "${DINRUSBREW_PREFIX}/opt/git/bin/git" ]]
  then
    # we cannot install a DinrusBrew Git if homebrew/core is unavailable.
    if [[ -z "${DINRUSBREW_CORE_AVAILABLE}" ]] || ! brew install git
    then
      odie "'git' must be installed and in your PATH!"
    fi

    setup_git
  fi

  [[ -f "${DINRUSBREW_CORE_REPOSITORY}/.git/shallow" ]] && DINRUSBREW_CORE_SHALLOW=1
  [[ -f "${DINRUSBREW_CASK_REPOSITORY}/.git/shallow" ]] && DINRUSBREW_CASK_SHALLOW=1
  if [[ -n "${DINRUSBREW_CORE_SHALLOW}" && -n "${DINRUSBREW_CASK_SHALLOW}" ]]
  then
    SHALLOW_COMMAND_PHRASE="These commands"
    SHALLOW_REPO_PHRASE="repositories"
  else
    SHALLOW_COMMAND_PHRASE="This command"
    SHALLOW_REPO_PHRASE="repository"
  fi

  if [[ -n "${DINRUSBREW_CORE_SHALLOW}" || -n "${DINRUSBREW_CASK_SHALLOW}" ]]
  then
    odie <<EOS
${DINRUSBREW_CORE_SHALLOW:+
  homebrew-core is a shallow clone.}${DINRUSBREW_CASK_SHALLOW:+
  homebrew-cask is a shallow clone.}
To \`brew update\`, first run:${DINRUSBREW_CORE_SHALLOW:+
  git -C "${DINRUSBREW_CORE_REPOSITORY}" fetch --unshallow}${DINRUSBREW_CASK_SHALLOW:+
  git -C "${DINRUSBREW_CASK_REPOSITORY}" fetch --unshallow}
${SHALLOW_COMMAND_PHRASE} may take a few minutes to run due to the large size of the ${SHALLOW_REPO_PHRASE}.
This restriction has been made on GitHub's request because updating shallow
clones is an extremely expensive operation due to the tree layout and traffic of
DinrusBrew/homebrew-core and DinrusBrew/homebrew-cask. We don't do this for you
automatically to avoid repeatedly performing an expensive unshallow operation in
CI systems (which should instead be fixed to not use shallow clones). Sorry for
the inconvenience!
EOS
  fi

  export GIT_TERMINAL_PROMPT="0"
  export GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh} -oBatchMode=yes"

  if [[ -n "${DINRUSBREW_GIT_NAME}" ]]
  then
    export GIT_AUTHOR_NAME="${DINRUSBREW_GIT_NAME}"
    export GIT_COMMITTER_NAME="${DINRUSBREW_GIT_NAME}"
  fi

  if [[ -n "${DINRUSBREW_GIT_EMAIL}" ]]
  then
    export GIT_AUTHOR_EMAIL="${DINRUSBREW_GIT_EMAIL}"
    export GIT_COMMITTER_EMAIL="${DINRUSBREW_GIT_EMAIL}"
  fi

  if [[ -z "${DINRUSBREW_VERBOSE}" ]]
  then
    export GIT_ADVICE="false"
    QUIET_ARGS=(-q)
  else
    QUIET_ARGS=()
  fi

  # DINRUSBREW_CURLRC is optionally defined in the user environment.
  # shellcheck disable=SC2153
  if [[ -z "${DINRUSBREW_CURLRC}" ]]
  then
    CURL_DISABLE_CURLRC_ARGS=(-q)
  else
    CURL_DISABLE_CURLRC_ARGS=()
  fi

  # only allow one instance of brew update
  lock update

  git_init_if_necessary

  if [[ "${DINRUSBREW_BREW_DEFAULT_GIT_REMOTE}" != "${DINRUSBREW_BREW_GIT_REMOTE}" ]]
  then
    safe_cd "${DINRUSBREW_REPOSITORY}"
    echo "DINRUSBREW_BREW_GIT_REMOTE set: using ${DINRUSBREW_BREW_GIT_REMOTE} as the DinrusBrew/brew Git remote."
    git remote set-url origin "${DINRUSBREW_BREW_GIT_REMOTE}"
    git config remote.origin.fetch "+refs/heads/*:refs/remotes/origin/*"
    git fetch --force --tags origin
    SKIP_FETCH_BREW_REPOSITORY=1
  fi

  if [[ -d "${DINRUSBREW_CORE_REPOSITORY}" ]] &&
     [[ "${DINRUSBREW_CORE_DEFAULT_GIT_REMOTE}" != "${DINRUSBREW_CORE_GIT_REMOTE}" ||
        -n "${DINRUSBREW_LINUXBREW_CORE_MIGRATION}" ]]
  then
    if [[ -n "${DINRUSBREW_LINUXBREW_CORE_MIGRATION}" ]]
    then
      # This means a migration is needed (in case it isn't run this time)
      safe_cd "${DINRUSBREW_REPOSITORY}"
      git config --bool homebrew.linuxbrewmigrated false
    fi

    safe_cd "${DINRUSBREW_CORE_REPOSITORY}"
    echo "DINRUSBREW_CORE_GIT_REMOTE set: using ${DINRUSBREW_CORE_GIT_REMOTE} as the DinrusBrew/homebrew-core Git remote."
    git remote set-url origin "${DINRUSBREW_CORE_GIT_REMOTE}"
    git config remote.origin.fetch "+refs/heads/*:refs/remotes/origin/*"
    git fetch --force origin refs/heads/master:refs/remotes/origin/master
    SKIP_FETCH_CORE_REPOSITORY=1
  fi

  safe_cd "${DINRUSBREW_REPOSITORY}"

  # This means a migration is needed but hasn't completed (yet).
  if [[ "$(git config homebrew.linuxbrewmigrated 2>/dev/null)" == "false" ]]
  then
    export DINRUSBREW_MIGRATE_LINUXBREW_FORMULAE=1
  fi

  # if an older system had a newer curl installed, change each repo's remote URL from git to https
  if [[ -n "${DINRUSBREW_SYSTEM_CURL_TOO_OLD}" && -x "${DINRUSBREW_PREFIX}/opt/curl/bin/curl" ]] &&
     [[ "$(git config remote.origin.url)" =~ ^git:// ]]
  then
    git config remote.origin.url "${DINRUSBREW_BREW_GIT_REMOTE}"
    git config -f "${DINRUSBREW_CORE_REPOSITORY}/.git/config" remote.origin.url "${DINRUSBREW_CORE_GIT_REMOTE}"
  fi

  # kill all of subprocess on interrupt
  trap '{ /usr/bin/pkill -P $$; wait; exit 130; }' SIGINT

  local update_failed_file="${DINRUSBREW_REPOSITORY}/.git/UPDATE_FAILED"
  local missing_remote_ref_dirs_file="${DINRUSBREW_REPOSITORY}/.git/FAILED_FETCH_DIRS"
  rm -f "${update_failed_file}"
  rm -f "${missing_remote_ref_dirs_file}"

  for DIR in "${DINRUSBREW_REPOSITORY}" "${DINRUSBREW_LIBRARY}"/Taps/*/*
  do
    if [[ -z "${DINRUSBREW_NO_INSTALL_FROM_API}" ]] &&
       [[ -n "${DINRUSBREW_UPDATE_AUTO}" || (-z "${DINRUSBREW_DEVELOPER}" && -z "${DINRUSBREW_DEV_CMD_RUN}") ]] &&
       [[ -n "${DINRUSBREW_UPDATE_AUTO}" &&
          (("${DIR}" == "${DINRUSBREW_CORE_REPOSITORY}" && -z "${DINRUSBREW_AUTO_UPDATE_CORE_TAP}") ||
          ("${DIR}" == "${DINRUSBREW_CASK_REPOSITORY}" && -z "${DINRUSBREW_AUTO_UPDATE_CASK_TAP}")) ]]
    then
      continue
    fi

    [[ -d "${DIR}/.git" ]] || continue
    cd "${DIR}" || continue

    if [[ "${DIR}" = "${DINRUSBREW_REPOSITORY}" && "${DINRUSBREW_REPOSITORY}" = "${DINRUSBREW_PREFIX}" ]]
    then
      # Git's fsmonitor prevents the release of our locks
      git config --bool core.fsmonitor false
    fi

    if ! git config --local --get remote.origin.url &>/dev/null
    then
      opoo "No remote 'origin' in ${DIR}, skipping update!"
      continue
    fi

    if [[ -n "${DINRUSBREW_VERBOSE}" ]]
    then
      echo "Checking if we need to fetch ${DIR}..."
    fi

    TAP_VAR="$(repository_var_suffix "${DIR}")"
    UPSTREAM_BRANCH_DIR="$(upstream_branch)"
    declare UPSTREAM_BRANCH"${TAP_VAR}"="${UPSTREAM_BRANCH_DIR}"
    declare PREFETCH_REVISION"${TAP_VAR}"="$(git rev-parse -q --verify refs/remotes/origin/"${UPSTREAM_BRANCH_DIR}")"

    if [[ -n "${GITHUB_ACTIONS}" && -n "${DINRUSBREW_UPDATE_SKIP_BREW}" && "${DIR}" == "${DINRUSBREW_REPOSITORY}" ]]
    then
      continue
    fi

    # Force a full update if we don't have any tags.
    if [[ "${DIR}" == "${DINRUSBREW_REPOSITORY}" && -z "$(git tag --list)" ]]
    then
      DINRUSBREW_UPDATE_FORCE=1
    fi

    if [[ -z "${DINRUSBREW_UPDATE_FORCE}" ]]
    then
      [[ -n "${SKIP_FETCH_BREW_REPOSITORY}" && "${DIR}" == "${DINRUSBREW_REPOSITORY}" ]] && continue
      [[ -n "${SKIP_FETCH_CORE_REPOSITORY}" && "${DIR}" == "${DINRUSBREW_CORE_REPOSITORY}" ]] && continue
    fi

    if [[ -z "${UPDATING_MESSAGE_SHOWN}" ]]
    then
      if [[ -n "${DINRUSBREW_UPDATE_AUTO}" ]]
      then
        # Outputting a command but don't want to run it, hence single quotes.
        # shellcheck disable=SC2016
        ohai 'Auto-updating DinrusBrew...' >&2
        if [[ -z "${DINRUSBREW_NO_ENV_HINTS}" && -z "${DINRUSBREW_AUTO_UPDATE_SECS}" ]]
        then
          # shellcheck disable=SC2016
          echo 'Adjust how often this is run with DINRUSBREW_AUTO_UPDATE_SECS or disable with' >&2
          # shellcheck disable=SC2016
          echo 'DINRUSBREW_NO_AUTO_UPDATE. Hide these hints with DINRUSBREW_NO_ENV_HINTS (see `man brew`).' >&2
        fi
      else
        ohai 'Updating DinrusBrew...' >&2
      fi
      UPDATING_MESSAGE_SHOWN=1
    fi

    # The upstream repository's default branch may not be master;
    # check refs/remotes/origin/HEAD to see what the default
    # origin branch name is, and use that. If not set, fall back to "master".
    # the refspec ensures that the default upstream branch gets updated
    (
      UPSTREAM_REPOSITORY_URL="$(git config remote.origin.url)"
      unset UPSTREAM_REPOSITORY
      unset UPSTREAM_REPOSITORY_TOKEN

      # DINRUSBREW_UPDATE_FORCE and DINRUSBREW_UPDATE_AUTO aren't modified here so ignore subshell warning.
      # shellcheck disable=SC2030
      if [[ "${UPSTREAM_REPOSITORY_URL}" == "https://github.com/"* ]]
      then
        UPSTREAM_REPOSITORY="${UPSTREAM_REPOSITORY_URL#https://github.com/}"
        UPSTREAM_REPOSITORY="${UPSTREAM_REPOSITORY%.git}"
      elif [[ "${DIR}" != "${DINRUSBREW_REPOSITORY}" ]] &&
           [[ "${UPSTREAM_REPOSITORY_URL}" =~ https://([[:alnum:]_:]+)@github.com/(.*)$ ]]
      then
        UPSTREAM_REPOSITORY="${BASH_REMATCH[2]%.git}"
        UPSTREAM_REPOSITORY_TOKEN="${BASH_REMATCH[1]#*:}"
      fi

      if [[ -n "${UPSTREAM_REPOSITORY}" ]]
      then
        # UPSTREAM_REPOSITORY_TOKEN is parsed (if exists) from UPSTREAM_REPOSITORY_URL
        # DINRUSBREW_GITHUB_API_TOKEN is optionally defined in the user environment.
        # shellcheck disable=SC2153
        if [[ -n "${UPSTREAM_REPOSITORY_TOKEN}" ]]
        then
          CURL_GITHUB_API_ARGS=("--header" "Authorization: token ${UPSTREAM_REPOSITORY_TOKEN}")
        elif [[ -n "${DINRUSBREW_GITHUB_API_TOKEN}" ]]
        then
          CURL_GITHUB_API_ARGS=("--header" "Authorization: token ${DINRUSBREW_GITHUB_API_TOKEN}")
        else
          CURL_GITHUB_API_ARGS=()
        fi

        if [[ "${DIR}" == "${DINRUSBREW_REPOSITORY}" && -n "${DINRUSBREW_UPDATE_TO_TAG}" ]]
        then
          # Only try to `git fetch` when the upstream tags have changed
          # (so the API does not return 304: unmodified).
          GITHUB_API_ETAG="$(sed -n 's/^ETag: "\([a-f0-9]\{32\}\)".*/\1/p' ".git/GITHUB_HEADERS" 2>/dev/null)"
          GITHUB_API_ACCEPT="application/vnd.github+json"
          GITHUB_API_ENDPOINT="tags"
        else
          # Only try to `git fetch` when the upstream branch is at a different SHA
          # (so the API does not return 304: unmodified).
          GITHUB_API_ETAG="$(git rev-parse "refs/remotes/origin/${UPSTREAM_BRANCH_DIR}")"
          GITHUB_API_ACCEPT="application/vnd.github.sha"
          GITHUB_API_ENDPOINT="commits/${UPSTREAM_BRANCH_DIR}"
        fi

        # DINRUSBREW_CURL is set by brew.sh (and isn't misspelt here)
        # shellcheck disable=SC2153
        UPSTREAM_SHA_HTTP_CODE="$(
          curl \
            "${CURL_DISABLE_CURLRC_ARGS[@]}" \
            "${CURL_GITHUB_API_ARGS[@]}" \
            --silent --max-time 3 \
            --location --no-remote-time --output /dev/null --write-out "%{http_code}" \
            --dump-header "${DIR}/.git/GITHUB_HEADERS" \
            --user-agent "${DINRUSBREW_USER_AGENT_CURL}" \
            --header "X-GitHub-Api-Version:2022-11-28" \
            --header "Accept: ${GITHUB_API_ACCEPT}" \
            --header "If-None-Match: \"${GITHUB_API_ETAG}\"" \
            "https://api.github.com/repos/${UPSTREAM_REPOSITORY}/${GITHUB_API_ENDPOINT}"
        )"

        # Touch FETCH_HEAD to confirm we've checked for an update.
        [[ -f "${DIR}/.git/FETCH_HEAD" ]] && touch "${DIR}/.git/FETCH_HEAD"
        [[ -z "${DINRUSBREW_UPDATE_FORCE}" ]] && [[ "${UPSTREAM_SHA_HTTP_CODE}" == "304" ]] && exit
      fi

      # DINRUSBREW_VERBOSE isn't modified here so ignore subshell warning.
      # shellcheck disable=SC2030
      if [[ -n "${DINRUSBREW_VERBOSE}" ]]
      then
        echo "Fetching ${DIR}..."
      fi

      local tmp_failure_file="${DIR}/.git/TMP_FETCH_FAILURES"
      rm -f "${tmp_failure_file}"

      if [[ -n "${DINRUSBREW_UPDATE_AUTO}" ]]
      then
        git fetch --tags --force "${QUIET_ARGS[@]}" origin \
          "refs/heads/${UPSTREAM_BRANCH_DIR}:refs/remotes/origin/${UPSTREAM_BRANCH_DIR}" 2>/dev/null
      else
        # Capture stderr to tmp_failure_file
        if ! git fetch --tags --force "${QUIET_ARGS[@]}" origin \
           "refs/heads/${UPSTREAM_BRANCH_DIR}:refs/remotes/origin/${UPSTREAM_BRANCH_DIR}" 2>>"${tmp_failure_file}"
        then
          # Reprint fetch errors to stderr
          [[ -f "${tmp_failure_file}" ]] && cat "${tmp_failure_file}" 1>&2

          if [[ "${UPSTREAM_SHA_HTTP_CODE}" == "404" ]]
          then
            TAP="${DIR#"${DINRUSBREW_LIBRARY}"/Taps/}"
            echo "${TAP} does not exist! Run \`brew untap ${TAP}\` to remove it." >>"${update_failed_file}"
          else
            echo "Fetching ${DIR} failed!" >>"${update_failed_file}"

            if [[ -f "${tmp_failure_file}" ]] &&
               [[ "$(cat "${tmp_failure_file}")" == "fatal: couldn't find remote ref refs/heads/${UPSTREAM_BRANCH_DIR}" ]]
            then
              echo "${DIR}" >>"${missing_remote_ref_dirs_file}"
            fi
          fi
        fi
      fi

      rm -f "${tmp_failure_file}"
    ) &
  done

  wait
  trap - SIGINT

  if [[ -f "${missing_remote_ref_dirs_file}" ]]
  then
    DINRUSBREW_MISSING_REMOTE_REF_DIRS="$(cat "${missing_remote_ref_dirs_file}")"
    rm -f "${missing_remote_ref_dirs_file}"
    export DINRUSBREW_MISSING_REMOTE_REF_DIRS
  fi

  for DIR in "${DINRUSBREW_REPOSITORY}" "${DINRUSBREW_LIBRARY}"/Taps/*/*
  do
    if [[ -z "${DINRUSBREW_NO_INSTALL_FROM_API}" ]] &&
       [[ -n "${DINRUSBREW_UPDATE_AUTO}" || (-z "${DINRUSBREW_DEVELOPER}" && -z "${DINRUSBREW_DEV_CMD_RUN}") ]] &&
       [[ -n "${DINRUSBREW_UPDATE_AUTO}" &&
          (("${DIR}" == "${DINRUSBREW_CORE_REPOSITORY}" && -z "${DINRUSBREW_AUTO_UPDATE_CORE_TAP}") ||
          ("${DIR}" == "${DINRUSBREW_CASK_REPOSITORY}" && -z "${DINRUSBREW_AUTO_UPDATE_CASK_TAP}")) ]]
    then
      continue
    fi

    [[ -d "${DIR}/.git" ]] || continue
    cd "${DIR}" || continue
    if ! git config --local --get remote.origin.url &>/dev/null
    then
      # No need to display a (duplicate) warning here
      continue
    fi

    TAP_VAR="$(repository_var_suffix "${DIR}")"
    UPSTREAM_BRANCH_VAR="UPSTREAM_BRANCH${TAP_VAR}"
    UPSTREAM_BRANCH="${!UPSTREAM_BRANCH_VAR}"
    CURRENT_REVISION="$(read_current_revision)"

    PREFETCH_REVISION_VAR="PREFETCH_REVISION${TAP_VAR}"
    PREFETCH_REVISION="${!PREFETCH_REVISION_VAR}"
    POSTFETCH_REVISION="$(git rev-parse -q --verify refs/remotes/origin/"${UPSTREAM_BRANCH}")"

    # DINRUSBREW_UPDATE_FORCE and DINRUSBREW_VERBOSE weren't modified in subshell.
    # shellcheck disable=SC2031
    if [[ -n "${DINRUSBREW_SIMULATE_FROM_CURRENT_BRANCH}" ]]
    then
      simulate_from_current_branch "${DIR}" "${TAP_VAR}" "${UPSTREAM_BRANCH}" "${CURRENT_REVISION}"
    elif [[ -z "${DINRUSBREW_UPDATE_FORCE}" &&
            "${PREFETCH_REVISION}" == "${POSTFETCH_REVISION}" &&
            "${CURRENT_REVISION}" == "${POSTFETCH_REVISION}" ]] ||
         [[ -n "${GITHUB_ACTIONS}" && -n "${DINRUSBREW_UPDATE_SKIP_BREW}" && "${DIR}" == "${DINRUSBREW_REPOSITORY}" ]]
    then
      export DINRUSBREW_UPDATE_BEFORE"${TAP_VAR}"="${CURRENT_REVISION}"
      export DINRUSBREW_UPDATE_AFTER"${TAP_VAR}"="${CURRENT_REVISION}"
    else
      merge_or_rebase "${DIR}" "${TAP_VAR}" "${UPSTREAM_BRANCH}"
    fi
  done

  if [[ -z "${DINRUSBREW_NO_INSTALL_FROM_API}" ]]
  then
    local api_cache="${DINRUSBREW_CACHE}/api"
    mkdir -p "${api_cache}"

    for json in formula cask formula_tap_migrations cask_tap_migrations
    do
      local filename="${json}.jws.json"
      local cache_path="${api_cache}/${filename}"
      if [[ -f "${cache_path}" ]]
      then
        INITIAL_JSON_BYTESIZE="$(wc -c "${cache_path}")"
      fi

      if [[ -n "${DINRUSBREW_VERBOSE}" ]]
      then
        echo "Checking if we need to fetch ${filename}..."
      fi

      JSON_URLS=()
      if [[ -n "${DINRUSBREW_API_DOMAIN}" && "${DINRUSBREW_API_DOMAIN}" != "${DINRUSBREW_API_DEFAULT_DOMAIN}" ]]
      then
        JSON_URLS=("${DINRUSBREW_API_DOMAIN}/${filename}")
      fi

      JSON_URLS+=("${DINRUSBREW_API_DEFAULT_DOMAIN}/${filename}")
      for json_url in "${JSON_URLS[@]}"
      do
        time_cond=()
        if [[ -s "${cache_path}" ]]
        then
          time_cond=("--time-cond" "${cache_path}")
        fi
        curl \
          "${CURL_DISABLE_CURLRC_ARGS[@]}" \
          --fail --compressed --silent \
          --speed-limit "${DINRUSBREW_CURL_SPEED_LIMIT}" --speed-time "${DINRUSBREW_CURL_SPEED_TIME}" \
          --location --remote-time --output "${cache_path}" \
          "${time_cond[@]}" \
          --user-agent "${DINRUSBREW_USER_AGENT_CURL}" \
          "${json_url}"
        curl_exit_code=$?
        [[ ${curl_exit_code} -eq 0 ]] && break
      done

      if [[ "${json}" == "formula" ]] && [[ -f "${api_cache}/formula_names.txt" ]]
      then
        mv -f "${api_cache}/formula_names.txt" "${api_cache}/formula_names.before.txt"
      elif [[ "${json}" == "cask" ]] && [[ -f "${api_cache}/cask_names.txt" ]]
      then
        mv -f "${api_cache}/cask_names.txt" "${api_cache}/cask_names.before.txt"
      fi

      if [[ ${curl_exit_code} -eq 0 ]]
      then
        touch "${cache_path}"

        CURRENT_JSON_BYTESIZE="$(wc -c "${cache_path}")"
        if [[ "${INITIAL_JSON_BYTESIZE}" != "${CURRENT_JSON_BYTESIZE}" ]]
        then

          if [[ "${json}" == "formula" ]]
          then
            rm -f "${api_cache}/formula_aliases.txt"
          fi
          DINRUSBREW_UPDATED="1"

          if [[ -n "${DINRUSBREW_VERBOSE}" ]]
          then
            echo "Updated ${filename}."
          fi
        fi
      else
        echo "Failed to download ${json_url}!" >>"${update_failed_file}"
      fi

    done

    # Not a typo, these are the files we used to download that no longer need so should cleanup.
    rm -f "${DINRUSBREW_CACHE}/api/formula.json" "${DINRUSBREW_CACHE}/api/cask.json"
  else
    if [[ -n "${DINRUSBREW_VERBOSE}" ]]
    then
      echo "DINRUSBREW_NO_INSTALL_FROM_API set: skipping API JSON downloads."
    fi
  fi

  if [[ -f "${update_failed_file}" ]]
  then
    onoe <"${update_failed_file}"
    rm -f "${update_failed_file}"
    export DINRUSBREW_UPDATE_FAILED="1"
  fi

  safe_cd "${DINRUSBREW_REPOSITORY}"

  # DINRUSBREW_UPDATE_AUTO wasn't modified in subshell.
  # shellcheck disable=SC2031
  if [[ -n "${DINRUSBREW_UPDATED}" ]] ||
     [[ -n "${DINRUSBREW_UPDATE_FAILED}" ]] ||
     [[ -n "${DINRUSBREW_MISSING_REMOTE_REF_DIRS}" ]] ||
     [[ -n "${DINRUSBREW_UPDATE_FORCE}" ]] ||
     [[ -n "${DINRUSBREW_MIGRATE_LINUXBREW_FORMULAE}" ]] ||
     [[ -d "${DINRUSBREW_LIBRARY}/LinkedKegs" ]] ||
     [[ ! -f "${DINRUSBREW_CACHE}/all_commands_list.txt" ]] ||
     [[ -n "${DINRUSBREW_DEVELOPER}" && -z "${DINRUSBREW_UPDATE_AUTO}" ]]
  then
    brew update-report "$@"
    return $?
  elif [[ -z "${DINRUSBREW_UPDATE_AUTO}" && -z "${DINRUSBREW_QUIET}" ]]
  then
    echo "Already up-to-date."
  fi
}
