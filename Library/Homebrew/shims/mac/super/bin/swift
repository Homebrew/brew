#!/bin/bash

# Set SDKROOT to ensure it matches Homebrew's choice of SDK.

# HOMEBREW_LIBRARY is set by bin/brew
# HOMEBREW_SDKROOT is set by extend/ENV/super.rb
# shellcheck disable=SC2154
source "${HOMEBREW_LIBRARY}/Homebrew/shims/utils.sh"

if [[ -z "${SDKROOT}" && -n "${HOMEBREW_SDKROOT}" ]]
then
  export SDKROOT="${HOMEBREW_SDKROOT}"
fi

try_exec_non_system "${SHIM_FILE}" "$@"
safe_exec "/usr/bin/${SHIM_FILE}" "$@"
