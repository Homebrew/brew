#!/bin/bash

# System Ruby's mkmf on Mojave (10.14) and later require SDKROOT set to work correctly.

# HOMEBREW_LIBRARY is set by bin/brew
# HOMEBREW_SDKROOT is set by extend/ENV/super.rb
# shellcheck disable=SC2154
source "${HOMEBREW_LIBRARY}/Homebrew/shims/utils.sh"

try_exec_non_system "${SHIM_FILE}" "$@"

if [[ -z "${SDKROOT}" && -n "${HOMEBREW_SDKROOT}" ]]
then
  export SDKROOT="${HOMEBREW_SDKROOT}"
fi

safe_exec "/usr/bin/${SHIM_FILE}" "$@"
