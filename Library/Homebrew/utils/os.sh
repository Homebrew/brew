# Operating system detection, default paths and OS-specific behaviour.
# This is sourced first by brew.sh so only fast, fork-free code may run at
# source time: commands like `brew shellenv` need everything defined here.

# HOMEBREW_* variables set here are used across Homebrew's Bash scripts.
# shellcheck disable=SC2034
# HOME is set by bin/brew and the remaining variables by the user environment.
# shellcheck disable=SC2154

case "${MACHTYPE}" in
  arm64-* | aarch64-*)
    HOMEBREW_PROCESSOR="arm64"
    ;;
  x86_64-*)
    HOMEBREW_PROCESSOR="x86_64"
    ;;
  *)
    HOMEBREW_PROCESSOR="$(uname -m)"
    ;;
esac

case "${OSTYPE}" in
  darwin*)
    HOMEBREW_SYSTEM="Darwin"
    HOMEBREW_MACOS="1"
    ;;
  linux*)
    HOMEBREW_SYSTEM="Linux"
    HOMEBREW_LINUX="1"
    ;;
  *)
    HOMEBREW_SYSTEM="$(uname -s)"
    ;;
esac
HOMEBREW_PHYSICAL_PROCESSOR="${HOMEBREW_PROCESSOR}"

HOMEBREW_MACOS_ARM_DEFAULT_PREFIX="/opt/homebrew"
HOMEBREW_LINUX_DEFAULT_PREFIX="/home/linuxbrew/.linuxbrew"
HOMEBREW_GENERIC_DEFAULT_PREFIX="/usr/local"
if [[ -n "${HOMEBREW_MACOS}" && "${HOMEBREW_PROCESSOR}" == "arm64" ]]
then
  HOMEBREW_DEFAULT_PREFIX="${HOMEBREW_MACOS_ARM_DEFAULT_PREFIX}"
  HOMEBREW_DEFAULT_REPOSITORY="${HOMEBREW_MACOS_ARM_DEFAULT_PREFIX}"
elif [[ -n "${HOMEBREW_LINUX}" ]]
then
  HOMEBREW_DEFAULT_PREFIX="${HOMEBREW_LINUX_DEFAULT_PREFIX}"
  HOMEBREW_DEFAULT_REPOSITORY="${HOMEBREW_LINUX_DEFAULT_PREFIX}/Homebrew"
else
  HOMEBREW_DEFAULT_PREFIX="${HOMEBREW_GENERIC_DEFAULT_PREFIX}"
  HOMEBREW_DEFAULT_REPOSITORY="${HOMEBREW_GENERIC_DEFAULT_PREFIX}/Homebrew"
fi

if [[ -n "${HOMEBREW_MACOS}" ]]
then
  HOMEBREW_DEFAULT_CACHE="${HOME}/Library/Caches/Homebrew"
  HOMEBREW_DEFAULT_LOGS="${HOME}/Library/Logs/Homebrew"
  HOMEBREW_DEFAULT_TEMP="/private/tmp"
else
  CACHE_HOME="${HOMEBREW_XDG_CACHE_HOME:-${HOME}/.cache}"
  HOMEBREW_DEFAULT_CACHE="${CACHE_HOME}/Homebrew"
  HOMEBREW_DEFAULT_LOGS="${CACHE_HOME}/Homebrew/Logs"
  if [[ -r "/var/tmp" && -w "/var/tmp" ]]
  then
    HOMEBREW_DEFAULT_TEMP="/var/tmp"
  else
    HOMEBREW_DEFAULT_TEMP="/tmp"
  fi
fi

# brew shellenv needs HOMEBREW_MACOS_VERSION_NUMERIC
if [[ -n "${HOMEBREW_MACOS}" ]]
then
  # Read ProductVersion directly to avoid forking `sw_vers`, which reads the
  # same file but costs several milliseconds on every invocation.
  HOMEBREW_MACOS_VERSION=""
  SYSTEM_VERSION_PLIST="/System/Library/CoreServices/SystemVersion.plist"
  SYSTEM_VERSION_PRODUCT_VERSION_KEY=""
  while IFS= read -r SYSTEM_VERSION_PLIST_LINE
  do
    if [[ -n "${SYSTEM_VERSION_PRODUCT_VERSION_KEY}" ]]
    then
      HOMEBREW_MACOS_VERSION="${SYSTEM_VERSION_PLIST_LINE#*<string>}"
      HOMEBREW_MACOS_VERSION="${HOMEBREW_MACOS_VERSION%%</string>*}"
      break
    fi
    [[ "${SYSTEM_VERSION_PLIST_LINE}" == *"<key>ProductVersion</key>"* ]] && SYSTEM_VERSION_PRODUCT_VERSION_KEY="1"
  done 2>/dev/null <"${SYSTEM_VERSION_PLIST}"
  MACOS_VERSION_REGEX="^[0-9.]+$"
  if ! [[ "${HOMEBREW_MACOS_VERSION}" =~ ${MACOS_VERSION_REGEX} ]]
  then
    HOMEBREW_MACOS_VERSION="$(/usr/bin/sw_vers -productVersion)"
  fi
  unset SYSTEM_VERSION_PLIST SYSTEM_VERSION_PLIST_LINE SYSTEM_VERSION_PRODUCT_VERSION_KEY MACOS_VERSION_REGEX

  IFS=. read -r -a MACOS_VERSION_ARRAY < <(printf '%s' "${HOMEBREW_MACOS_VERSION}")
  printf -v HOMEBREW_MACOS_VERSION_NUMERIC "%02d%02d%02d" "${MACOS_VERSION_ARRAY[@]}"

  unset MACOS_VERSION_ARRAY
fi

# Force UTF-8 to avoid encoding issues for users with broken locale settings.
# Validate the active locale's charmap rather than trusting its name before
# selecting a usable fallback.
setup-locale() {
  local locales c_utf_regex en_us_regex utf_regex
  if [[ -z "${HOMEBREW_MACOS}" ]]
  then
    [[ -z "${HOMEBREW_LANG:-}" ]] || export LANG="${HOMEBREW_LANG}"
    [[ -z "${HOMEBREW_LC_CTYPE:-}" ]] || export LC_CTYPE="${HOMEBREW_LC_CTYPE}"
    [[ -z "${HOMEBREW_LC_ALL:-}" ]] || export LC_ALL="${HOMEBREW_LC_ALL}"
  fi
  unset HOMEBREW_LANG HOMEBREW_LC_CTYPE HOMEBREW_LC_ALL

  if [[ -n "${HOMEBREW_MACOS}" ]]
  then
    if [[ -z "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" ]] || [[ "$(locale charmap)" != "UTF-8" ]]
    then
      export LC_ALL="en_US.UTF-8"
    fi
  else
    if ! command -v locale >/dev/null
    then
      export LC_ALL=C
    elif [[ "$(locale charmap)" != "UTF-8" ]]
    then
      locales="$(locale -a)"
      c_utf_regex='\bC\.(utf8|UTF-8)\b'
      en_us_regex='\ben_US\.(utf8|UTF-8)\b'
      utf_regex='\b[a-z][a-z]_[A-Z][A-Z]\.(utf8|UTF-8)\b'
      if [[ ${locales} =~ ${c_utf_regex} || ${locales} =~ ${en_us_regex} || ${locales} =~ ${utf_regex} ]]
      then
        export LC_ALL="${BASH_REMATCH[0]}"
      else
        export LC_ALL=C
      fi
    fi
  fi
}

# Derive the OS-specific product naming and user agent details and check the
# OS version and hardware are supported.
setup-os-details() {
  local MACOS_VERSION_ARRAY
  if [[ -n "${HOMEBREW_MACOS}" ]]
  then
    HOMEBREW_PRODUCT="Homebrew"
    HOMEBREW_SYSTEM="Macintosh"
    [[ "${HOMEBREW_PROCESSOR}" == "x86_64" ]] && HOMEBREW_PROCESSOR="Intel"
    # Don't change this from Mac OS X to match what macOS itself does in Safari
    HOMEBREW_OS_USER_AGENT_VERSION="Mac OS X ${HOMEBREW_MACOS_VERSION}"

    # `sysctl` is only needed to detect Rosetta so don't fork it on ARM.
    if [[ "${HOMEBREW_PHYSICAL_PROCESSOR}" == "x86_64" ]] &&
       [[ "$(sysctl -n hw.optional.arm64 2>/dev/null)" == "1" ]]
    then
      # used in vendor-install.sh and update.sh
      HOMEBREW_PHYSICAL_PROCESSOR="arm64"
    fi

    IFS=. read -r -a MACOS_VERSION_ARRAY < <(printf '%s' "${HOMEBREW_MACOS_OLDEST_ALLOWED}")
    printf -v HOMEBREW_MACOS_OLDEST_ALLOWED_NUMERIC "%02d%02d%02d" "${MACOS_VERSION_ARRAY[@]}"

    HOMEBREW_OS_VERSION="macOS ${HOMEBREW_MACOS_VERSION%.*}"

    # Refuse to run on pre-Big Sur
    if [[ "${HOMEBREW_MACOS_VERSION_NUMERIC}" -lt "${HOMEBREW_MACOS_OLDEST_ALLOWED_NUMERIC}" ]]
    then
      printf "ERROR: Your version of macOS (%s) is too old to run Homebrew!\\n" "${HOMEBREW_MACOS_VERSION}" >&2
      printf "         For this macOS version see: https://www.macports.org\\n" >&2
      printf "\\n" >&2
    fi

  else
    if [[ -r "/proc/cpuinfo" ]] &&
       [[ "${HOMEBREW_PROCESSOR}" == "x86_64" ]]
    then
      if ! grep -qE '^(flags|Features).*\bssse3\b' /proc/cpuinfo
      then
        odie "Homebrew's x86_64 support on Linux requires a CPU with SSSE3 support!"
      fi
    fi

    HOMEBREW_PRODUCT="${HOMEBREW_SYSTEM}brew"
    # Don't try to follow /etc/os-release
    # shellcheck disable=SC1091
    [[ -n "${HOMEBREW_LINUX}" ]] && HOMEBREW_OS_VERSION="$(source /etc/os-release && echo "${PRETTY_NAME}")"
    : "${HOMEBREW_OS_VERSION:=$(uname -r)}"
    HOMEBREW_OS_USER_AGENT_VERSION="${HOMEBREW_OS_VERSION}"

    HOMEBREW_LINUX_MINIMUM_GLIBC_VERSION="2.13"
  fi
}
