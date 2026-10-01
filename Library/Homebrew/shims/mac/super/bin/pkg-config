#!/bin/bash

# HOMEBREW_OPT and HOMEBREW_SDKROOT are set by extend/ENV/super.rb
# shellcheck disable=SC2154
pkg_config="${HOMEBREW_OPT}/pkg-config/bin/pkg-config"

if [[ -z "${HOMEBREW_SDKROOT}" ]]
then
  exec "${pkg_config}" "$@"
fi

exec "${pkg_config}" \
  "--define-variable=homebrew_sdkroot=${HOMEBREW_SDKROOT}" \
  "$@"
