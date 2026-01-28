#!/bin/bash

# HOMEBREW_LIBRARY is set by bin/brew
# HOMEBREW_CCCFG and HOMEBREW_OPT are set by extend/ENV/super.rb
# shellcheck disable=SC2154
if [[ -z "${HOMEBREW_LIBRARY}" ]]
then
  echo "${0##*/}: This shim is internal and must be run via brew." >&2
  exit 1
fi

source "${HOMEBREW_LIBRARY}/Homebrew/shims/utils.sh"

parallel_args=()
if [[ -n "${HOMEBREW_MAKE_JOBS}" ]]
then
  parallel_args+=(-j "${HOMEBREW_MAKE_JOBS}")
fi

# shellcheck disable=SC2154
export HOMEBREW_CCCFG="O${HOMEBREW_CCCFG}"
try_exec_non_system "ninja" "${parallel_args[@]}" "$@"

echo "ninja: Shim failed to find ninja in PATH."
exit 1
