# Documentation defined in Library/DinrusBrew/cmd/--version.rb

# DINRUSBREW_CORE_REPOSITORY, DINRUSBREW_CASK_REPOSITORY, DINRUSBREW_VERSION are set by brew.sh
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
  echo "DinrusBrew ${DINRUSBREW_VERSION}"

  if [[ -n "${DINRUSBREW_NO_INSTALL_FROM_API}" || -d "${DINRUSBREW_CORE_REPOSITORY}" ]]
  then
    echo "DinrusBrew/homebrew-core $(version_string "${DINRUSBREW_CORE_REPOSITORY}")"
  fi

  if [[ -d "${DINRUSBREW_CASK_REPOSITORY}" ]]
  then
    echo "DinrusBrew/homebrew-cask $(version_string "${DINRUSBREW_CASK_REPOSITORY}")"
  fi
}
