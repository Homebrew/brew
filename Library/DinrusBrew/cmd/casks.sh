# Documentation defined in Library/DinrusBrew/cmd/casks.rb

# DINRUSBREW_LIBRARY is set in bin/brew
# shellcheck disable=SC2154
source "${DINRUSBREW_LIBRARY}/DinrusBrew/items.sh"

homebrew-casks() {
  local find_include_filter='*/Casks/*\.rb'
  local sed_filter='s|/Casks/(.+/)?|/|'
  local grep_filter='^homebrew/cask'

  # DINRUSBREW_CACHE is set by brew.sh
  # shellcheck disable=SC2154
  if [[ -z "${DINRUSBREW_NO_INSTALL_FROM_API}" &&
        -f "${DINRUSBREW_CACHE}/api/cask_names.txt" ]]
  then
    {
      cat "${DINRUSBREW_CACHE}/api/cask_names.txt"
      echo
      homebrew-items "${find_include_filter}" '.*/homebrew/homebrew-cask/.*' "${sed_filter}" "${grep_filter}"
    } | sort -uf
  else
    homebrew-items "${find_include_filter}" '^\b$' "${sed_filter}" "${grep_filter}"
  fi
}
