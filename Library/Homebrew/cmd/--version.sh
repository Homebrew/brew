# Documentation defined in Library/Homebrew/cmd/--version.rb

# HOMEBREW_CORE_REPOSITORY, HOMEBREW_CASK_REPOSITORY, HOMEBREW_VERSION are set by brew.sh
# shellcheck disable=SC2154
version_string() {
  local repo="$1"
  if ! [[ -d "${repo}" ]]
  then
    echo "N/A"
    return
  fi

  local pretty_revision
  pretty_revision="$(git -C "${repo}" rev-parse --short --verify --quiet HEAD)"
  if [[ -z "${pretty_revision}" ]]
  then
    echo "(no Git repository)"
    return
  fi

  local git_last_commit_date
  git_last_commit_date="$(git -C "${repo}" show -s --format='%cd' --date=short HEAD)"
  echo "(git revision ${pretty_revision}; last commit ${git_last_commit_date})"
}

homebrew-version() {
  echo "Homebrew ${HOMEBREW_VERSION}"

  if [[ -n "${HOMEBREW_NO_INSTALL_FROM_API}" || -d "${HOMEBREW_CORE_REPOSITORY}" ]]
  then
    echo "Homebrew/homebrew-core $(version_string "${HOMEBREW_CORE_REPOSITORY}")"
  fi

  if [[ -d "${HOMEBREW_CASK_REPOSITORY}" ]]
  then
    echo "Homebrew/homebrew-cask $(version_string "${HOMEBREW_CASK_REPOSITORY}")"
  fi
}
