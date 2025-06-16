# Documentation defined in Library/Homebrew/cmd/update-reset.rb

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
    case "${option}" in
      -\? | -h | --help | --usage)
        brew help update-reset
        exit $?
        ;;
      --debug) HOMEBREW_DEBUG=1 ;;
      -*)
        [[ "${option}" == *d* ]] && HOMEBREW_DEBUG=1
        ;;
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

  if [[ -n "${HOMEBREW_DEBUG}" ]]
  then
    set -x
  fi

  if [[ -z "${REPOS[*]}" ]]
  then
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
    # HOMEBREW_* variables here may all set by bin/brew or the user
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
