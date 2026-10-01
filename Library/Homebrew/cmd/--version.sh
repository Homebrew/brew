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

  local git_revision_and_date
  git_revision_and_date="$(git -C "${repo}" log -1 --format='%h %cd' --date=short HEAD 2>/dev/null)"
  if [[ -z "${git_revision_and_date}" ]]
  then
    echo "(no Git repository)"
    return
  fi

  echo "(git revision ${git_revision_and_date%% *}; last commit ${git_revision_and_date#* })"
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
