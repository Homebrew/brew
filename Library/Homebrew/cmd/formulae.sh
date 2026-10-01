# Documentation defined in Library/Homebrew/cmd/formulae.rb

# HOMEBREW_LIBRARY is set by bin/brew
# shellcheck disable=SC2154
source "${HOMEBREW_LIBRARY}/Homebrew/items.sh"

homebrew-formulae() {
  local find_include_filter='*\.rb'
  local sed_filter='s|/Formula/(.+/)?|/|'
  local grep_filter='^homebrew/core'

  if homebrew-tap-trust-required
  then
    if homebrew-trusted-items-with-api-names "${find_include_filter}" '.*Casks(/.*|$)' \
       "trustedformulae" "homebrew/core" "Formula" "formula_names.txt"
    then
      return
    fi
    opoo "jq is unavailable; falling back to Ruby to apply tap trust."
    HOMEBREW_FORCE_RUBY_COMMAND=1 "${HOMEBREW_BREW_FILE}" formulae
    return
  fi

  # HOMEBREW_CACHE is set by brew.sh
  # shellcheck disable=SC2154
  if [[ -z "${HOMEBREW_NO_INSTALL_FROM_API}" &&
        -f "${HOMEBREW_CACHE}/api/formula_names.txt" ]]
  then
    {
      cat "${HOMEBREW_CACHE}/api/formula_names.txt"
      echo
      homebrew-items "${find_include_filter}" '.*Casks(/.*|$)|.*/homebrew/homebrew-core/.*' "${sed_filter}" "${grep_filter}"
    } | sort -uf
  else
    homebrew-items "${find_include_filter}" '.*Casks(/.*|$)' "${sed_filter}" "${grep_filter}"
  fi
}
