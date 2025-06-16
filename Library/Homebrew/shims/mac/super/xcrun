#!/bin/bash

# Historically, xcrun has had various bugs, and in some cases it didn't
# work at all (e.g. CLT-only in the Xcode 4.3 era). This script emulates
# it and attempts to avoid these issues.

# These could be used in conjunction with `--sdk` which ignores SDKROOT.
# HOMEBREW_DEVELOPER_DIR, HOMEBREW_SDKROOT and HOMEBREW_PREFER_CLT_PROXIES are set by extend/ENV/super.rb
# shellcheck disable=SC2154
if [[ "$*" =~ (^| )-?-show-sdk-(path|version|build) && -n "${HOMEBREW_DEVELOPER_DIR}" ]]
then
  export DEVELOPER_DIR="${HOMEBREW_DEVELOPER_DIR}"
else
  # Some build tools set DEVELOPER_DIR, so discard it
  unset DEVELOPER_DIR
fi

if [[ -z "${SDKROOT}" && -n "${HOMEBREW_SDKROOT}" ]]
then
  export SDKROOT="${HOMEBREW_SDKROOT}"
fi

if [[ $# -eq 0 ]]
then
  exec /usr/bin/xcrun "$@"
fi

# shellcheck disable=SC2249
case "$1" in
  -*) exec /usr/bin/xcrun "$@" ;;
esac

arg0="$1"
shift

exe="/usr/bin/${arg0}"
if [[ -x "${exe}" ]]
then
  if [[ -n "${HOMEBREW_PREFER_CLT_PROXIES}" ]]
  then
    exec "${exe}" "$@"
  elif [[ -z "${HOMEBREW_SDKROOT}" || ! -d "${HOMEBREW_SDKROOT}" ]]
  then
    exec "${exe}" "$@"
  fi
fi

SUPERBIN="$(cd "${0%/*}" && pwd -P)"

exe="$(/usr/bin/xcrun --find "${arg0}" 2>/dev/null)"
if [[ -x "${exe}" && "${exe%/*}" != "${SUPERBIN}" ]]
then
  exec "${exe}" "$@"
fi

old_IFS="${IFS}"
IFS=':'
for path in ${PATH}
do
  if [[ "${path}" == "${SUPERBIN}" ]]
  then
    continue
  fi

  exe="${path}/${arg0}"
  if [[ -x "${exe}" ]]
  then
    exec "${exe}" "$@"
  fi
done
IFS="${old_IFS}"

echo >&2 "
Failed to execute ${arg0} ${*}

Xcode and/or the CLT appear to be misconfigured. Try one or both of the following:
  xcodebuild -license
  sudo xcode-select --switch /path/to/Xcode.app
"
exit 1
