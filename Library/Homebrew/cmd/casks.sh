# Documentation defined in Library/Homebrew/cmd/casks.rb

# HOMEBREW_LIBRARY is set in bin/brew
# shellcheck disable=SC2154
source "${HOMEBREW_LIBRARY}/Homebrew/items.sh"

homebrew-casks() {
  local find_include_filter='*/Casks/*\.rb'
  local sed_filter='s|/Casks/(.+/)?|/|'
  local grep_filter='^homebrew/cask'

  if homebrew-tap-trust-required
  then
    if homebrew-trusted-items-with-api-names "${find_include_filter}" '^\b$' \
       "trustedcasks" "homebrew/cask" "Casks" "cask_names.txt"
    then
      return
    fi
    opoo "jq is unavailable; falling back to Ruby to apply tap trust."
    HOMEBREW_FORCE_RUBY_COMMAND=1 "${HOMEBREW_BREW_FILE}" casks
    return
  fi

  # HOMEBREW_CACHE is set by brew.sh
  # shellcheck disable=SC2154
  if [[ -z "${HOMEBREW_NO_INSTALL_FROM_API}" &&
        -f "${HOMEBREW_CACHE}/api/cask_names.txt" ]]
  then
    {
      cat "${HOMEBREW_CACHE}/api/cask_names.txt"
      echo
      homebrew-items "${find_include_filter}" '.*/homebrew/homebrew-cask/.*' "${sed_filter}" "${grep_filter}"
    } | sort -uf
  else
    homebrew-items "${find_include_filter}" '^\b$' "${sed_filter}" "${grep_filter}"
  fi
}
