# Documentation defined in Library/DinrusBrew/cmd/formulae.rb

# DINRUSBREW_LIBRARY is set by bin/brew
# shellcheck disable=SC2154
source "${DINRUSBREW_LIBRARY}/DinrusBrew/items.sh"

homebrew-formulae() {
  local find_include_filter='*\.rb'
  local sed_filter='s|/Formula/(.+/)?|/|'
  local grep_filter='^homebrew/core'

  # DINRUSBREW_CACHE is set by brew.sh
  # shellcheck disable=SC2154
  if [[ -z "${DINRUSBREW_NO_INSTALL_FROM_API}" &&
        -f "${DINRUSBREW_CACHE}/api/formula_names.txt" ]]
  then
    {
      cat "${DINRUSBREW_CACHE}/api/formula_names.txt"
      echo
      homebrew-items "${find_include_filter}" '.*Casks(/.*|$)|.*/homebrew/homebrew-core/.*' "${sed_filter}" "${grep_filter}"
    } | sort -uf
  else
    homebrew-items "${find_include_filter}" '.*Casks(/.*|$)' "${sed_filter}" "${grep_filter}"
  fi
}
