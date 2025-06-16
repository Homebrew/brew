#!/bin/bash

# HOMEBREW_LIBRARY is set by bin/brew
# shellcheck disable=SC2154
source "${HOMEBREW_LIBRARY}/Homebrew/shims/utils.sh"

export HOMEBREW_CCCFG="O${HOMEBREW_CCCFG}"

try_exec_non_system "${SHIM_FILE}" "$@"
safe_exec "/usr/bin/make" "$@"
