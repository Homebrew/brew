#!/bin/bash -p

# This script because we support $HOMEBREW_GIT, $HOMEBREW_SVN, etc., Xcode-only and
# no Xcode/CLT configurations. Order is careful to be what the user would want.

# HOMEBREW_LIBRARY is set by bin/brew
# SHIM_FILE is set by shims/utils.sh
# HOMEBREW_GIT is set by brew.sh
# HOMEBREW_SVN is from the user environment.
# HOMEBREW_PREFIX is set by extend/ENV/super.rb
# shellcheck disable=SC2154
if [[ -z "${HOMEBREW_LIBRARY}" ]]
then
  echo "${0##*/}: This shim is internal and must be run via brew." >&2
  exit 1
fi

source "${HOMEBREW_LIBRARY}/Homebrew/shims/utils.sh"

# shellcheck disable=SC2249
case "$(lowercase "${SHIM_FILE}")" in
  git)
    if [[ -n "${HOMEBREW_GIT}" && "${HOMEBREW_GIT}" != git ]]
    then
      safe_exec "$(type -P "${HOMEBREW_GIT}")" "$@"
    fi
    ;;
  svn)
    if [[ -n "${HOMEBREW_SVN}" && "${HOMEBREW_SVN}" != svn ]]
    then
      safe_exec "$(type -P "${HOMEBREW_SVN}")" "$@"
    fi
    ;;
esac

brew_prefix_version="${HOMEBREW_PREFIX}/bin/${SHIM_FILE}"
safe_exec "${brew_prefix_version}" "$@"

try_exec_non_system "${SHIM_FILE}" "$@"

if executable "/usr/bin/xcode-select"
then
  # xcode-select will return empty on no Xcode/CLT configuration.
  #   /usr/bin/<tool> will be a popup stub under such configuration.
  # xcrun hangs if xcode-select is set to "/"
  xcode_path="$(/usr/bin/xcode-select -print-path 2>/dev/null)"
  if [[ -z "${xcode_path}" ]]
  then
    if [[ "${HOMEBREW_MACOS_VERSION_NUMERIC}" -ge "100900" ]]
    then
      popup_stub=1
    fi
  fi
  if [[ -z "${popup_stub}" && "${xcode_path}" != "/" ]]
  then
    path="$(/usr/bin/xcrun -find "${SHIM_FILE}" 2>/dev/null)"
    safe_exec "${path}" "$@"
  fi
fi

path="/Applications/Xcode.app/Contents/Developer/usr/bin/${SHIM_FILE}"
safe_exec "${path}" "$@"

if [[ -z "${popup_stub}" && "${HOMEBREW_MACOS_VERSION_NUMERIC}" -lt "101500" ]]
then
  path="/usr/bin/${SHIM_FILE}"
  safe_exec "${path}" "$@"
fi

echo "You must: brew install ${SHIM_FILE}" >&2
exit 1
