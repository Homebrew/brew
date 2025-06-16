#!/bin/bash

# HOMEBREW_CCCFG is set by extend/ENV/super.rb
# HOMEBREW_LIBRARY is set by bin/brew
# shellcheck disable=SC2154,SC2250
pathremove() {
  local IFS=':'
  local NEWPATH=""
  local DIR=""
  local PATHVARIABLE="${2:-PATH}"

  for DIR in ${!PATHVARIABLE}
  do
    if [[ "${DIR}" != "$1" ]]
    then
      NEWPATH="${NEWPATH:+$NEWPATH:}${DIR}"
    fi
  done
  export "${PATHVARIABLE}"="${NEWPATH}"
}

SAVED_PATH="${PATH}"
pathremove "${HOMEBREW_LIBRARY}/Homebrew/shims/linux/super"
MAKE="$(command -v make)"
export MAKE
export PATH="${SAVED_PATH}"

export HOMEBREW_CCCFG="O${HOMEBREW_CCCFG}"

exec "${MAKE}" "$@"
