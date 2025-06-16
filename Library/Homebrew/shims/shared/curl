#!/bin/bash -p

# Make our $HOMEBREW_CURL selection universal - including in formulae usage.

# HOMEBREW_LIBRARY is set by bin/brew
# HOMEBREW_CURL is set by brew.sh
# shellcheck disable=SC2154
if [[ -z "${HOMEBREW_LIBRARY}" ]]
then
  echo "${0##*/}: This shim is internal and must be run via brew." >&2
  exit 1
fi

source "${HOMEBREW_LIBRARY}/Homebrew/shims/utils.sh"

# SSL_CERT_FILE alone does not clear the CAPath setting.
set_certs=0
if [[ -n "${SSL_CERT_FILE}" ]]
then
  set_certs=1
  for arg in "$@"
  do
    if [[ "${arg}" =~ ^--ca(cert|path)$ ]]
    then
      # User passed their own settings - don't use ours!
      set_certs=0
    fi
  done
fi
if [[ ${set_certs} -eq 1 ]]
then
  set -- "--cacert" "${SSL_CERT_FILE}" "--capath" "$(dirname "${SSL_CERT_FILE}")" "$@"
fi

try_exec_non_system "${HOMEBREW_CURL:-curl}" "$@"
safe_exec "/usr/bin/curl" "$@"

echo "Could not execute curl. Try HOMEBREW_FORCE_BREWED_CURL=1" >&2
exit 1
