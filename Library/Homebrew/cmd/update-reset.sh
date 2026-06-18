# Documentation defined in Library/Homebrew/cmd/update-reset.rb

# HOMEBREW_LIBRARY is set by bin/brew
# shellcheck disable=SC2154
source "${HOMEBREW_LIBRARY}/Homebrew/utils/cmd.sh"

# Replaces the function in Library/Homebrew/brew.sh to cache the Git executable to provide
# speedup when using Git repeatedly and prevent errors if the shim changes mid-update.
git() {
  if [[ -z "${GIT_EXECUTABLE}" ]]
  then
    # HOMEBREW_LIBRARY is set by bin/brew
    # shellcheck disable=SC2154
    GIT_EXECUTABLE="$("${HOMEBREW_LIBRARY}/Homebrew/shims/shared/git" --homebrew=print-path)"
    if [[ -z "${GIT_EXECUTABLE}" ]]
    then
      odie "Can't find a working Git!"
    fi
  fi
  "${GIT_EXECUTABLE}" "$@"
}

homebrew-update-reset() {
  local option
  local DIR
  local -a REPOS=()

  for option in "$@"
  do
    if homebrew-command-help update-reset "${option}"
    then
      exit $?
    fi
    if homebrew-command-common-option "${option}"
    then
      continue
    fi

    case "${option}" in
      -*) homebrew-command-common-short-options "${option}" ;;
      *)
        if [[ -d "${option}/.git" ]]
        then
          REPOS+=("${option}")
        else
          onoe "${option} is not a Git repository!"
          brew help update-reset
          exit 1
        fi
        ;;
    esac
  done

  homebrew-command-enable-debug

  if [[ -z "${REPOS[*]}" ]]
  then
    # HOMEBREW_REPOSITORY is set by bin/brew
    # shellcheck disable=SC2154
    REPOS+=("${HOMEBREW_REPOSITORY}" "${HOMEBREW_LIBRARY}"/Taps/*/*)
  fi

  for DIR in "${REPOS[@]}"
  do
    [[ -d "${DIR}/.git" ]] || continue
    if ! git -C "${DIR}" config --local --get remote.origin.url &>/dev/null
    then
      opoo "No remote 'origin' in ${DIR}, skipping update and reset!"
      continue
    fi
    git -C "${DIR}" config --bool core.autocrlf false
    git -C "${DIR}" config --bool core.symlinks true
    ohai "Fetching ${DIR}..."
    git -C "${DIR}" fetch --force --tags origin
    git -C "${DIR}" remote set-head origin --auto >/dev/null
    echo

    ohai "Resetting ${DIR}..."
    # HOMEBREW_* variables here may all be set by bin/brew or the user
    # shellcheck disable=SC2154
    if [[ "${DIR}" == "${HOMEBREW_REPOSITORY}" &&
       (-n "${HOMEBREW_UPDATE_TO_TAG}" ||
       (-z "${HOMEBREW_DEVELOPER}" && -z "${HOMEBREW_DEV_CMD_RUN}")) ]]
    then
      local latest_git_tag
      latest_git_tag="$(git -C "${DIR}" tag --list --sort="-version:refname" | head -n1)"

      git -C "${DIR}" checkout --force -B stable "refs/tags/${latest_git_tag}"
    else
      head="$(git -C "${DIR}" symbolic-ref refs/remotes/origin/HEAD)"
      head="${head#refs/remotes/origin/}"
      git -C "${DIR}" checkout --force -B "${head}" origin/HEAD
    fi
    rm -rf "${DIR}/.git/describe-cache"
    echo
  done
}
