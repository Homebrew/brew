# Documentation defined in Library/Homebrew/cmd/update.rb

# HOMEBREW_API_DOMAIN, HOMEBREW_CURLRC, HOMEBREW_DEBUG, HOMEBREW_DEVELOPER, HOMEBREW_GIT_EMAIL, HOMEBREW_GIT_NAME,
# HOMEBREW_GITHUB_API_TOKEN, HOMEBREW_NO_ENV_HINTS, HOMEBREW_NO_INSTALL_CLEANUP, HOMEBREW_NO_INSTALL_FROM_API,
# HOMEBREW_UPDATE_TO_TAG are from the user environment
# HOMEBREW_LIBRARY, HOMEBREW_PREFIX, HOMEBREW_REPOSITORY are set by bin/brew
# HOMEBREW_API_DEFAULT_DOMAIN, HOMEBREW_AUTO_UPDATE_CASK_TAP, HOMEBREW_AUTO_UPDATE_CORE_TAP,
# HOMEBREW_AUTO_UPDATE_SECS, HOMEBREW_BREW_DEFAULT_GIT_REMOTE, HOMEBREW_BREW_GIT_REMOTE, HOMEBREW_CACHE,
# HOMEBREW_CASK_REPOSITORY, HOMEBREW_CELLAR, HOMEBREW_CORE_DEFAULT_GIT_REMOTE, HOMEBREW_CORE_GIT_REMOTE,
# HOMEBREW_CORE_REPOSITORY, HOMEBREW_CURL, HOMEBREW_DEV_CMD_RUN, HOMEBREW_FORCE_BREWED_CA_CERTIFICATES,
# HOMEBREW_FORCE_BREWED_CURL, HOMEBREW_FORCE_BREWED_GIT, HOMEBREW_LINUXBREW_CORE_MIGRATION,
# HOMEBREW_SYSTEM_CURL_TOO_OLD, HOMEBREW_USER_AGENT_CURL are set by brew.sh
# shellcheck disable=SC2154
source "${HOMEBREW_LIBRARY}/Homebrew/utils/lock.sh"

# Replaces the function in Library/Homebrew/brew.sh to cache the Curl/Git executable to
# provide speedup when using Curl/Git repeatedly (as update.sh does).
curl() {
  if [[ -z "${CURL_EXECUTABLE}" ]]
  then
    CURL_EXECUTABLE="$("${HOMEBREW_LIBRARY}/Homebrew/shims/shared/curl" --homebrew=print-path)"
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
    GIT_EXECUTABLE="$("${HOMEBREW_LIBRARY}/Homebrew/shims/shared/git" --homebrew=print-path)"
    if [[ -z "${GIT_EXECUTABLE}" ]]
    then
      odie "Can't find a working Git!"
    fi
  fi
  "${GIT_EXECUTABLE}" "$@"
}

# "master" is used here so we get a deterministic branch name, no matter
# what git version we're using.
git_init_if_necessary() {
  local branch_name

  safe_cd "${HOMEBREW_REPOSITORY}"
  if [[ ! -d ".git" ]]
  then
    set -e
    trap '{ rm -rf .git; exit 1; }' EXIT
    git -c init.defaultBranch=master init --quiet
    git config --bool core.autocrlf false
    git config --bool core.symlinks true
    if [[ "${HOMEBREW_BREW_DEFAULT_GIT_REMOTE}" != "${HOMEBREW_BREW_GIT_REMOTE}" ]]
    then
      echo "HOMEBREW_BREW_GIT_REMOTE set: using ${HOMEBREW_BREW_GIT_REMOTE} as the Homebrew/brew Git remote."
    fi
    git config remote.origin.url "${HOMEBREW_BREW_GIT_REMOTE}"
    git config remote.origin.fetch "+refs/heads/*:refs/remotes/origin/*"
    git fetch --force --tags origin
    git remote set-head origin --auto >/dev/null
    branch_name="$(upstream_branch)"
    git reset --hard "origin/${branch_name}"
    if [[ "${branch_name}" != "master" ]]
    then
      git branch -m master "${branch_name}"
    fi
    git branch -u "origin/${branch_name}" "${branch_name}"
    SKIP_FETCH_BREW_REPOSITORY=1
    set +e
    trap - EXIT
  fi

  [[ -d "${HOMEBREW_CORE_REPOSITORY}" ]] || return
  safe_cd "${HOMEBREW_CORE_REPOSITORY}"
  if [[ ! -d ".git" ]]
  then
    set -e
    trap '{ rm -rf .git; exit 1; }' EXIT
    git -c init.defaultBranch=master init --quiet
    git config --bool core.autocrlf false
    git config --bool core.symlinks true
    if [[ "${HOMEBREW_CORE_DEFAULT_GIT_REMOTE}" != "${HOMEBREW_CORE_GIT_REMOTE}" ]]
    then
      echo "HOMEBREW_CORE_GIT_REMOTE set: using ${HOMEBREW_CORE_GIT_REMOTE} as the Homebrew/homebrew-core Git remote."
    fi
    git config remote.origin.url "${HOMEBREW_CORE_GIT_REMOTE}"
    git config remote.origin.fetch "+refs/heads/*:refs/remotes/origin/*"
    git fetch --force origin
    git remote set-head origin --auto >/dev/null
    branch_name="$(upstream_branch)"
    git reset --hard "origin/${branch_name}"
    if [[ "${branch_name}" != "master" ]]
    then
      git branch -m master "${branch_name}"
    fi
    git branch -u "origin/${branch_name}" "${branch_name}"
    SKIP_FETCH_CORE_REPOSITORY=1
    set +e
    trap - EXIT
  fi
}

repository_var_suffix() {
  local repository_directory="${1}"
  local repository_var_suffix

  if [[ "${repository_directory}" == "${HOMEBREW_REPOSITORY}" ]]
  then
    repository_var_suffix=""
  else
    repository_var_suffix="${repository_directory#"${HOMEBREW_LIBRARY}/Taps"}"
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
  if [[ -n "${HOMEBREW_VERBOSE}" ]]
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

  if [[ -n "${HOMEBREW_NO_UPDATE_CLEANUP}" ]]
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
  export HOMEBREW_UPDATE_BEFORE"${TAP_VAR}"="${INITIAL_REVISION}"
  export HOMEBREW_UPDATE_AFTER"${TAP_VAR}"="${CURRENT_REVISION}"
  if [[ "${INITIAL_REVISION}" != "${CURRENT_REVISION}" ]]
  then
    HOMEBREW_UPDATED="1"
  fi
  if ! git merge-base --is-ancestor "${INITIAL_REVISION}" "${CURRENT_REVISION}"
  then
    odie "Your ${DIR} HEAD is not a descendant of ${UPSTREAM_BRANCH}!"
  fi
}

merge_or_rebase() {
  if [[ -n "${HOMEBREW_VERBOSE}" ]]
  then
    echo "Updating ${DIR}..."
  fi

  local DIR
  local TAP_VAR
  local UPSTREAM_BRANCH
  local UPSTREAM_DEFAULT_BRANCH

  DIR="$1"
  cd "${DIR}" || return
  TAP_VAR="$2"
  UPSTREAM_BRANCH="$3"
  UPSTREAM_DEFAULT_BRANCH="${UPSTREAM_BRANCH}"
  unset STASHED

  trap reset_on_interrupt SIGINT

  if [[ "${DIR}" == "${HOMEBREW_REPOSITORY}" && -n "${HOMEBREW_UPDATE_TO_TAG}" ]]
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
    if [[ -n "${HOMEBREW_VERBOSE}" ]]
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
  git reset --hard origin/${UPSTREAM_DEFAULT_BRANCH}
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
      if [[ -n "${UPSTREAM_TAG}" && "${UPSTREAM_BRANCH}" != "${UPSTREAM_DEFAULT_BRANCH}" ]] &&
         [[ "${INITIAL_BRANCH}" != "${UPSTREAM_DEFAULT_BRANCH}" ]]
      then
        git branch --force "${UPSTREAM_DEFAULT_BRANCH}" "origin/${UPSTREAM_DEFAULT_BRANCH}" "${QUIET_ARGS[@]}"
      fi

      git checkout --force -B "${UPSTREAM_BRANCH}" "${REMOTE_REF}" "${QUIET_ARGS[@]}"
    fi
  fi

  INITIAL_REVISION="$(read_current_revision)"
  export HOMEBREW_UPDATE_BEFORE"${TAP_VAR}"="${INITIAL_REVISION}"

  # ensure we don't munge line endings on checkout
  git config --bool core.autocrlf false

  # make sure symlinks are saved as-is
  git config --bool core.symlinks true

  if [[ "${DIR}" == "${HOMEBREW_CORE_REPOSITORY}" && -n "${HOMEBREW_LINUXBREW_CORE_MIGRATION}" ]]
  then
    # Don't even try to rebase/merge on linuxbrew-core migration but rely on
    # stashing etc. above.
    git reset --hard "${QUIET_ARGS[@]}" "${REMOTE_REF}"
    unset HOMEBREW_LINUXBREW_CORE_MIGRATION
  elif [[ -z "${HOMEBREW_MERGE}" ]]
  then
    # Work around bug where git rebase --quiet is not quiet
    if [[ -z "${HOMEBREW_VERBOSE}" ]]
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
  export HOMEBREW_UPDATE_AFTER"${TAP_VAR}"="${CURRENT_REVISION}"

  if [[ "${INITIAL_REVISION}" != "${CURRENT_REVISION}" ]]
  then
    HOMEBREW_UPDATED="1"
  fi

  trap '' SIGINT

  if [[ -n "${HOMEBREW_NO_UPDATE_CLEANUP}" ]]
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
      --verbose) HOMEBREW_VERBOSE=1 ;;
      --debug) HOMEBREW_DEBUG=1 ;;
      --quiet) HOMEBREW_QUIET=1 ;;
      --merge)
        shift
        HOMEBREW_MERGE=1
        ;;
      --force) HOMEBREW_UPDATE_FORCE=1 ;;
      --simulate-from-current-branch)
        shift
        HOMEBREW_SIMULATE_FROM_CURRENT_BRANCH=1
        ;;
      --auto-update) export HOMEBREW_UPDATE_AUTO=1 ;;
      --*)
        onoe "Unknown option: ${option}"
        brew help update
        exit 1
        ;;
      -*)
        [[ "${option}" == *v* ]] && HOMEBREW_VERBOSE=1
        [[ "${option}" == *q* ]] && HOMEBREW_QUIET=1
        [[ "${option}" == *d* ]] && HOMEBREW_DEBUG=1
        [[ "${option}" == *f* ]] && HOMEBREW_UPDATE_FORCE=1
        ;;
      *)
        odie <<EOS
This command updates brew itself, and does not take formula names.
Use \`brew upgrade $@\` instead.
EOS
        ;;
    esac
  done

  if [[ -n "${HOMEBREW_DEBUG}" ]]
  then
    set -x
  fi

  if [[ -z "${HOMEBREW_UPDATE_TO_TAG}" ]]
  then
    if [[ -n "${HOMEBREW_DEVELOPER}" || -n "${HOMEBREW_DEV_CMD_RUN}" ]]
    then
      export HOMEBREW_NO_UPDATE_CLEANUP="1"
    else
      export HOMEBREW_UPDATE_TO_TAG="1"
    fi
  fi

  # check permissions
  if [[ -e "${HOMEBREW_CELLAR}" && ! -w "${HOMEBREW_CELLAR}" ]]
  then
    odie <<EOS
${HOMEBREW_CELLAR} is not writable. You should change the
ownership and permissions of ${HOMEBREW_CELLAR} back to your
user account:
  sudo chown -R ${USER-\$(whoami)} ${HOMEBREW_CELLAR}
EOS
  fi

  if [[ -d "${HOMEBREW_CORE_REPOSITORY}" ]] ||
     [[ -z "${HOMEBREW_NO_INSTALL_FROM_API}" ]]
  then
    HOMEBREW_CORE_AVAILABLE="1"
  fi

  if [[ ! -w "${HOMEBREW_REPOSITORY}" ]]
  then
    odie <<EOS
${HOMEBREW_REPOSITORY} is not writable. You should change the
ownership and permissions of ${HOMEBREW_REPOSITORY} back to your
user account:
  sudo chown -R ${USER-\$(whoami)} ${HOMEBREW_REPOSITORY}
EOS
  fi

  # we may want to use Homebrew CA certificates
  if [[ -n "${HOMEBREW_FORCE_BREWED_CA_CERTIFICATES}" && ! -f "${HOMEBREW_PREFIX}/etc/ca-certificates/cert.pem" ]]
  then
    # we cannot install Homebrew CA certificates if homebrew/core is unavailable.
    if [[ -n "${HOMEBREW_CORE_AVAILABLE}" ]]
    then
      brew install ca-certificates
      setup_ca_certificates
    fi
  fi

  # we may want to use a Homebrew curl
  if [[ -n "${HOMEBREW_FORCE_BREWED_CURL}" && ! -x "${HOMEBREW_PREFIX}/opt/curl/bin/curl" ]]
  then
    # we cannot install a Homebrew cURL if homebrew/core is unavailable.
    if [[ -z "${HOMEBREW_CORE_AVAILABLE}" ]] || ! brew install curl
    then
      odie "'curl' must be installed and in your PATH!"
    fi

    setup_curl
  fi

  if ! git --version &>/dev/null ||
     [[ -n "${HOMEBREW_FORCE_BREWED_GIT}" && ! -x "${HOMEBREW_PREFIX}/opt/git/bin/git" ]]
  then
    # we cannot install a Homebrew Git if homebrew/core is unavailable.
    if [[ -z "${HOMEBREW_CORE_AVAILABLE}" ]] || ! brew install git
    then
      odie "'git' must be installed and in your PATH!"
    fi

    setup_git
  fi

  [[ -f "${HOMEBREW_CORE_REPOSITORY}/.git/shallow" ]] && HOMEBREW_CORE_SHALLOW=1
  [[ -f "${HOMEBREW_CASK_REPOSITORY}/.git/shallow" ]] && HOMEBREW_CASK_SHALLOW=1
  if [[ -n "${HOMEBREW_CORE_SHALLOW}" && -n "${HOMEBREW_CASK_SHALLOW}" ]]
  then
    SHALLOW_COMMAND_PHRASE="These commands"
    SHALLOW_REPO_PHRASE="repositories"
  else
    SHALLOW_COMMAND_PHRASE="This command"
    SHALLOW_REPO_PHRASE="repository"
  fi

  if [[ -n "${HOMEBREW_CORE_SHALLOW}" || -n "${HOMEBREW_CASK_SHALLOW}" ]]
  then
    odie <<EOS
${HOMEBREW_CORE_SHALLOW:+
  homebrew-core is a shallow clone.}${HOMEBREW_CASK_SHALLOW:+
  homebrew-cask is a shallow clone.}
To \`brew update\`, first run:${HOMEBREW_CORE_SHALLOW:+
  git -C "${HOMEBREW_CORE_REPOSITORY}" fetch --unshallow}${HOMEBREW_CASK_SHALLOW:+
  git -C "${HOMEBREW_CASK_REPOSITORY}" fetch --unshallow}
${SHALLOW_COMMAND_PHRASE} may take a few minutes to run due to the large size of the ${SHALLOW_REPO_PHRASE}.
This restriction has been made on GitHub's request because updating shallow
clones is an extremely expensive operation due to the tree layout and traffic of
Homebrew/homebrew-core and Homebrew/homebrew-cask. We don't do this for you
automatically to avoid repeatedly performing an expensive unshallow operation in
CI systems (which should instead be fixed to not use shallow clones). Sorry for
the inconvenience!
EOS
  fi

  export GIT_TERMINAL_PROMPT="0"
  export GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh} -oBatchMode=yes"

  if [[ -n "${HOMEBREW_GIT_NAME}" ]]
  then
    export GIT_AUTHOR_NAME="${HOMEBREW_GIT_NAME}"
    export GIT_COMMITTER_NAME="${HOMEBREW_GIT_NAME}"
  fi

  if [[ -n "${HOMEBREW_GIT_EMAIL}" ]]
  then
    export GIT_AUTHOR_EMAIL="${HOMEBREW_GIT_EMAIL}"
    export GIT_COMMITTER_EMAIL="${HOMEBREW_GIT_EMAIL}"
  fi

  if [[ -z "${HOMEBREW_VERBOSE}" ]]
  then
    export GIT_ADVICE="false"
    QUIET_ARGS=(-q)
  else
    QUIET_ARGS=()
  fi

  # HOMEBREW_CURLRC is optionally defined in the user environment.
  # shellcheck disable=SC2153
  if [[ -z "${HOMEBREW_CURLRC}" ]]
  then
    CURL_DISABLE_CURLRC_ARGS=(-q)
  else
    CURL_DISABLE_CURLRC_ARGS=()
  fi

  # only allow one instance of brew update
  lock update

  git_init_if_necessary

  if [[ "${HOMEBREW_BREW_DEFAULT_GIT_REMOTE}" != "${HOMEBREW_BREW_GIT_REMOTE}" ]]
  then
    safe_cd "${HOMEBREW_REPOSITORY}"
    echo "HOMEBREW_BREW_GIT_REMOTE set: using ${HOMEBREW_BREW_GIT_REMOTE} as the Homebrew/brew Git remote."
    git remote set-url origin "${HOMEBREW_BREW_GIT_REMOTE}"
    git config remote.origin.fetch "+refs/heads/*:refs/remotes/origin/*"
  fi

  if [[ -d "${HOMEBREW_CORE_REPOSITORY}" ]] &&
     [[ "${HOMEBREW_CORE_DEFAULT_GIT_REMOTE}" != "${HOMEBREW_CORE_GIT_REMOTE}" ||
        -n "${HOMEBREW_LINUXBREW_CORE_MIGRATION}" ]]
  then
    if [[ -n "${HOMEBREW_LINUXBREW_CORE_MIGRATION}" ]]
    then
      # This means a migration is needed (in case it isn't run this time)
      safe_cd "${HOMEBREW_REPOSITORY}"
      git config --bool homebrew.linuxbrewmigrated false
    fi

    safe_cd "${HOMEBREW_CORE_REPOSITORY}"
    echo "HOMEBREW_CORE_GIT_REMOTE set: using ${HOMEBREW_CORE_GIT_REMOTE} as the Homebrew/homebrew-core Git remote."
    git remote set-url origin "${HOMEBREW_CORE_GIT_REMOTE}"
    git config remote.origin.fetch "+refs/heads/*:refs/remotes/origin/*"
  fi

  safe_cd "${HOMEBREW_REPOSITORY}"

  # This means a migration is needed but hasn't completed (yet).
  if [[ "$(git config homebrew.linuxbrewmigrated 2>/dev/null)" == "false" ]]
  then
    export HOMEBREW_MIGRATE_LINUXBREW_FORMULAE=1
  fi

  # if an older system had a newer curl installed, change each repo's remote URL from git to https
  if [[ -n "${HOMEBREW_SYSTEM_CURL_TOO_OLD}" && -x "${HOMEBREW_PREFIX}/opt/curl/bin/curl" ]] &&
     [[ "$(git config remote.origin.url)" =~ ^git:// ]]
  then
    git config remote.origin.url "${HOMEBREW_BREW_GIT_REMOTE}"
    git config -f "${HOMEBREW_CORE_REPOSITORY}/.git/config" remote.origin.url "${HOMEBREW_CORE_GIT_REMOTE}"
  fi

  # kill all of subprocess on interrupt
  trap '{ /usr/bin/pkill -P $$; wait; exit 130; }' SIGINT

  local update_failed_file="${HOMEBREW_REPOSITORY}/.git/UPDATE_FAILED"
  local missing_remote_ref_dirs_file="${HOMEBREW_REPOSITORY}/.git/FAILED_FETCH_DIRS"
  rm -f "${update_failed_file}"
  rm -f "${missing_remote_ref_dirs_file}"

  for DIR in "${HOMEBREW_REPOSITORY}" "${HOMEBREW_LIBRARY}"/Taps/*/*
  do
    if [[ -z "${HOMEBREW_NO_INSTALL_FROM_API}" ]] &&
       [[ -n "${HOMEBREW_UPDATE_AUTO}" || (-z "${HOMEBREW_DEVELOPER}" && -z "${HOMEBREW_DEV_CMD_RUN}") ]] &&
       [[ -n "${HOMEBREW_UPDATE_AUTO}" &&
          (("${DIR}" == "${HOMEBREW_CORE_REPOSITORY}" && -z "${HOMEBREW_AUTO_UPDATE_CORE_TAP}") ||
          ("${DIR}" == "${HOMEBREW_CASK_REPOSITORY}" && -z "${HOMEBREW_AUTO_UPDATE_CASK_TAP}")) ]]
    then
      continue
    fi

    [[ -d "${DIR}/.git" ]] || continue
    cd "${DIR}" || continue

    if [[ "${DIR}" = "${HOMEBREW_REPOSITORY}" && "${HOMEBREW_REPOSITORY}" = "${HOMEBREW_PREFIX}" ]]
    then
      # Git's fsmonitor prevents the release of our locks
      git config --bool core.fsmonitor false
    fi

    if ! git config --local --get remote.origin.url &>/dev/null
    then
      opoo "No remote 'origin' in ${DIR}, skipping update!"
      continue
    fi

    if [[ -n "${HOMEBREW_VERBOSE}" ]]
    then
      echo "Checking if we need to fetch ${DIR}..."
    fi

    TAP_VAR="$(repository_var_suffix "${DIR}")"
    UPSTREAM_BRANCH_DIR="$(upstream_branch)"
    declare UPSTREAM_BRANCH"${TAP_VAR}"="${UPSTREAM_BRANCH_DIR}"
    declare PREFETCH_REVISION"${TAP_VAR}"="$(git rev-parse -q --verify refs/remotes/origin/"${UPSTREAM_BRANCH_DIR}")"

    if [[ -n "${GITHUB_ACTIONS}" && -n "${HOMEBREW_UPDATE_SKIP_BREW}" && "${DIR}" == "${HOMEBREW_REPOSITORY}" ]]
    then
      continue
    fi

    # Force a full update if we don't have any tags.
    if [[ "${DIR}" == "${HOMEBREW_REPOSITORY}" && -z "$(git tag --list)" ]]
    then
      HOMEBREW_UPDATE_FORCE=1
    fi

    if [[ -z "${HOMEBREW_UPDATE_FORCE}" ]]
    then
      [[ -n "${SKIP_FETCH_BREW_REPOSITORY}" && "${DIR}" == "${HOMEBREW_REPOSITORY}" ]] && continue
      [[ -n "${SKIP_FETCH_CORE_REPOSITORY}" && "${DIR}" == "${HOMEBREW_CORE_REPOSITORY}" ]] && continue
    fi

    if [[ -z "${UPDATING_MESSAGE_SHOWN}" ]]
    then
      if [[ -n "${HOMEBREW_UPDATE_AUTO}" ]]
      then
        # Outputting a command but don't want to run it, hence single quotes.
        # shellcheck disable=SC2016
        ohai 'Auto-updating Homebrew...' >&2
        if [[ -z "${HOMEBREW_NO_ENV_HINTS}" && -z "${HOMEBREW_AUTO_UPDATE_SECS}" ]]
        then
          # shellcheck disable=SC2016
          echo 'Adjust how often this is run with HOMEBREW_AUTO_UPDATE_SECS or disable with' >&2
          # shellcheck disable=SC2016
          echo 'HOMEBREW_NO_AUTO_UPDATE. Hide these hints with HOMEBREW_NO_ENV_HINTS (see `man brew`).' >&2
        fi
      else
        ohai 'Updating Homebrew...' >&2
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

      # HOMEBREW_UPDATE_FORCE and HOMEBREW_UPDATE_AUTO aren't modified here so ignore subshell warning.
      # shellcheck disable=SC2030
      if [[ "${UPSTREAM_REPOSITORY_URL}" == "https://github.com/"* ]]
      then
        UPSTREAM_REPOSITORY="${UPSTREAM_REPOSITORY_URL#https://github.com/}"
        UPSTREAM_REPOSITORY="${UPSTREAM_REPOSITORY%.git}"
      elif [[ "${DIR}" != "${HOMEBREW_REPOSITORY}" ]] &&
           [[ "${UPSTREAM_REPOSITORY_URL}" =~ https://([[:alnum:]_:]+)@github.com/(.*)$ ]]
      then
        UPSTREAM_REPOSITORY="${BASH_REMATCH[2]%.git}"
        UPSTREAM_REPOSITORY_TOKEN="${BASH_REMATCH[1]#*:}"
      fi

      if [[ -n "${UPSTREAM_REPOSITORY}" ]]
      then
        # UPSTREAM_REPOSITORY_TOKEN is parsed (if exists) from UPSTREAM_REPOSITORY_URL
        # HOMEBREW_GITHUB_API_TOKEN is optionally defined in the user environment.
        # shellcheck disable=SC2153
        if [[ -n "${UPSTREAM_REPOSITORY_TOKEN}" ]]
        then
          CURL_GITHUB_API_ARGS=("--header" "Authorization: token ${UPSTREAM_REPOSITORY_TOKEN}")
        elif [[ -n "${HOMEBREW_GITHUB_API_TOKEN}" ]]
        then
          CURL_GITHUB_API_ARGS=("--header" "Authorization: token ${HOMEBREW_GITHUB_API_TOKEN}")
        else
          CURL_GITHUB_API_ARGS=()
        fi

        if [[ "${DIR}" == "${HOMEBREW_REPOSITORY}" && -n "${HOMEBREW_UPDATE_TO_TAG}" ]]
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

        # HOMEBREW_CURL is set by brew.sh (and isn't misspelt here)
        # shellcheck disable=SC2153
        UPSTREAM_SHA_HTTP_CODE="$(
          curl \
            "${CURL_DISABLE_CURLRC_ARGS[@]}" \
            "${CURL_GITHUB_API_ARGS[@]}" \
            --silent --max-time 3 \
            --location --no-remote-time --output /dev/null --write-out "%{http_code}" \
            --dump-header "${DIR}/.git/GITHUB_HEADERS" \
            --user-agent "${HOMEBREW_USER_AGENT_CURL}" \
            --header "X-GitHub-Api-Version:2022-11-28" \
            --header "Accept: ${GITHUB_API_ACCEPT}" \
            --header "If-None-Match: \"${GITHUB_API_ETAG}\"" \
            "https://api.github.com/repos/${UPSTREAM_REPOSITORY}/${GITHUB_API_ENDPOINT}"
        )"

        # Touch FETCH_HEAD to confirm we've checked for an update.
        [[ -f "${DIR}/.git/FETCH_HEAD" ]] && touch "${DIR}/.git/FETCH_HEAD"
        [[ -z "${HOMEBREW_UPDATE_FORCE}" ]] && [[ "${UPSTREAM_SHA_HTTP_CODE}" == "304" ]] && exit
      fi

      # HOMEBREW_VERBOSE isn't modified here so ignore subshell warning.
      # shellcheck disable=SC2030
      if [[ -n "${HOMEBREW_VERBOSE}" ]]
      then
        echo "Fetching ${DIR}..."
      fi

      local tmp_failure_file="${DIR}/.git/TMP_FETCH_FAILURES"
      rm -f "${tmp_failure_file}"

      # Capture stderr to tmp_failure_file
      if ! git fetch --tags --force "${QUIET_ARGS[@]}" origin \
         "refs/heads/${UPSTREAM_BRANCH_DIR}:refs/remotes/origin/${UPSTREAM_BRANCH_DIR}" 2>>"${tmp_failure_file}"
      then
        if [[ -f "${tmp_failure_file}" ]] &&
           [[ "$(cat "${tmp_failure_file}")" == "fatal: couldn't find remote ref refs/heads/${UPSTREAM_BRANCH_DIR}" ]]
        then
          echo "${DIR}" >>"${missing_remote_ref_dirs_file}"
        elif [[ -z "${HOMEBREW_UPDATE_AUTO}" ]]
        then
          # Reprint fetch errors to stderr
          [[ -f "${tmp_failure_file}" ]] && cat "${tmp_failure_file}" 1>&2

          if [[ "${UPSTREAM_SHA_HTTP_CODE}" == "404" ]]
          then
            TAP="${DIR#"${HOMEBREW_LIBRARY}"/Taps/}"
            echo "${TAP} does not exist! Run \`brew untap ${TAP}\` to remove it." >>"${update_failed_file}"
          else
            echo "Fetching ${DIR} failed!" >>"${update_failed_file}"
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
    while IFS='' read -r DIR
    do
      cd "${DIR}"
      TAP_VAR="$(repository_var_suffix "${DIR}")"
      UPSTREAM_BRANCH_VAR="UPSTREAM_BRANCH${TAP_VAR}"
      OLD_BRANCH="${!UPSTREAM_BRANCH_VAR}"

      git fetch "${QUIET_ARGS[@]}" origin "+refs/heads/*:refs/remotes/origin/*"
      git remote set-head origin --auto >/dev/null
      NEW_BRANCH="$(upstream_branch)"

      git config remote.origin.fetch "+refs/heads/*:refs/remotes/origin/*"
      git branch "${QUIET_ARGS[@]}" -m "${OLD_BRANCH}" "${NEW_BRANCH}"
      git branch "${QUIET_ARGS[@]}" -u "origin/${NEW_BRANCH}" "${NEW_BRANCH}"
      ohai "${DIR#"${HOMEBREW_LIBRARY}/Taps/"}: changed default branch name from \"${OLD_BRANCH}\" to \"${NEW_BRANCH}\"!" >&2
      declare UPSTREAM_BRANCH"${TAP_VAR}"="${NEW_BRANCH}"

      # retry fetch
      git fetch --tags --force "${QUIET_ARGS[@]}" origin \
        "refs/heads/${NEW_BRANCH}:refs/remotes/origin/${NEW_BRANCH}"
    done <"${missing_remote_ref_dirs_file}"

    rm -f "${missing_remote_ref_dirs_file}"
  fi

  for DIR in "${HOMEBREW_REPOSITORY}" "${HOMEBREW_LIBRARY}"/Taps/*/*
  do
    if [[ -z "${HOMEBREW_NO_INSTALL_FROM_API}" ]] &&
       [[ -n "${HOMEBREW_UPDATE_AUTO}" || (-z "${HOMEBREW_DEVELOPER}" && -z "${HOMEBREW_DEV_CMD_RUN}") ]] &&
       [[ -n "${HOMEBREW_UPDATE_AUTO}" &&
          (("${DIR}" == "${HOMEBREW_CORE_REPOSITORY}" && -z "${HOMEBREW_AUTO_UPDATE_CORE_TAP}") ||
          ("${DIR}" == "${HOMEBREW_CASK_REPOSITORY}" && -z "${HOMEBREW_AUTO_UPDATE_CASK_TAP}")) ]]
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

    # HOMEBREW_UPDATE_FORCE and HOMEBREW_VERBOSE weren't modified in subshell.
    # shellcheck disable=SC2031
    if [[ -n "${HOMEBREW_SIMULATE_FROM_CURRENT_BRANCH}" ]]
    then
      simulate_from_current_branch "${DIR}" "${TAP_VAR}" "${UPSTREAM_BRANCH}" "${CURRENT_REVISION}"
    elif [[ -z "${HOMEBREW_UPDATE_FORCE}" &&
            "${PREFETCH_REVISION}" == "${POSTFETCH_REVISION}" &&
            "${CURRENT_REVISION}" == "${POSTFETCH_REVISION}" ]] ||
         [[ -n "${GITHUB_ACTIONS}" && -n "${HOMEBREW_UPDATE_SKIP_BREW}" && "${DIR}" == "${HOMEBREW_REPOSITORY}" ]]
    then
      export HOMEBREW_UPDATE_BEFORE"${TAP_VAR}"="${CURRENT_REVISION}"
      export HOMEBREW_UPDATE_AFTER"${TAP_VAR}"="${CURRENT_REVISION}"
    else
      merge_or_rebase "${DIR}" "${TAP_VAR}" "${UPSTREAM_BRANCH}"
    fi
  done

  if [[ -z "${HOMEBREW_NO_INSTALL_FROM_API}" ]]
  then
    local api_cache="${HOMEBREW_CACHE}/api"
    mkdir -p "${api_cache}"

    for json in formula cask formula_tap_migrations cask_tap_migrations
    do
      local filename="${json}.jws.json"
      local cache_path="${api_cache}/${filename}"
      if [[ -f "${cache_path}" ]]
      then
        INITIAL_JSON_BYTESIZE="$(wc -c "${cache_path}")"
      fi

      if [[ -n "${HOMEBREW_VERBOSE}" ]]
      then
        echo "Checking if we need to fetch ${filename}..."
      fi

      JSON_URLS=()
      if [[ -n "${HOMEBREW_API_DOMAIN}" && "${HOMEBREW_API_DOMAIN}" != "${HOMEBREW_API_DEFAULT_DOMAIN}" ]]
      then
        JSON_URLS=("${HOMEBREW_API_DOMAIN}/${filename}")
      fi

      JSON_URLS+=("${HOMEBREW_API_DEFAULT_DOMAIN}/${filename}")
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
          --speed-limit "${HOMEBREW_CURL_SPEED_LIMIT}" --speed-time "${HOMEBREW_CURL_SPEED_TIME}" \
          --location --remote-time --output "${cache_path}" \
          "${time_cond[@]}" \
          --user-agent "${HOMEBREW_USER_AGENT_CURL}" \
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
          HOMEBREW_UPDATED="1"

          if [[ -n "${HOMEBREW_VERBOSE}" ]]
          then
            echo "Updated ${filename}."
          fi
        fi
      else
        echo "Failed to download ${json_url}!" >>"${update_failed_file}"
      fi

    done

    # Not a typo, these are the files we used to download that no longer need so should cleanup.
    rm -f "${HOMEBREW_CACHE}/api/formula.json" "${HOMEBREW_CACHE}/api/cask.json"
  else
    if [[ -n "${HOMEBREW_VERBOSE}" ]]
    then
      echo "HOMEBREW_NO_INSTALL_FROM_API set: skipping API JSON downloads."
    fi
  fi

  if [[ -f "${update_failed_file}" ]]
  then
    onoe <"${update_failed_file}"
    rm -f "${update_failed_file}"
    export HOMEBREW_UPDATE_FAILED="1"
  fi

  safe_cd "${HOMEBREW_REPOSITORY}"

  # HOMEBREW_UPDATE_AUTO wasn't modified in subshell.
  # shellcheck disable=SC2031
  if [[ -n "${HOMEBREW_UPDATED}" ]] ||
     [[ -n "${HOMEBREW_UPDATE_FAILED}" ]] ||
     [[ -n "${HOMEBREW_UPDATE_FORCE}" ]] ||
     [[ -n "${HOMEBREW_MIGRATE_LINUXBREW_FORMULAE}" ]] ||
     [[ -d "${HOMEBREW_LIBRARY}/LinkedKegs" ]] ||
     [[ ! -f "${HOMEBREW_CACHE}/all_commands_list.txt" ]] ||
     [[ -n "${HOMEBREW_DEVELOPER}" && -z "${HOMEBREW_UPDATE_AUTO}" ]]
  then
    brew update-report "$@"
    return $?
  elif [[ -z "${HOMEBREW_UPDATE_AUTO}" && -z "${HOMEBREW_QUIET}" ]]
  then
    echo "Already up-to-date."
  fi
}
