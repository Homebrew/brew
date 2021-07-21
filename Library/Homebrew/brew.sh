#####
##### First do the essential, fast things to be able to make e.g. brew --prefix and other commands we want to be
##### able to `source` in shell configuration quick.
#####

# Doesn't need a default case because we don't support other OSs
# shellcheck disable=SC2249
HOMEBREW_PROCESSOR="$(uname -m)"
HOMEBREW_SYSTEM="$(uname -s)"
case "${HOMEBREW_SYSTEM}" in
  Darwin) HOMEBREW_MACOS="1" ;;
  Linux)  HOMEBREW_LINUX="1" ;;
esac

# If we're running under macOS Rosetta 2, and it was requested by setting
# HOMEBREW_CHANGE_ARCH_TO_ARM (for example in CI), then we re-exec this
# same file under the native architecture
# These variables are set from the user environment.
# shellcheck disable=SC2154
if [[ "${HOMEBREW_CHANGE_ARCH_TO_ARM}" = "1" ]] && \
   [[ "${HOMEBREW_MACOS}" = "1" ]] && \
   [[ "$(sysctl -n hw.optional.arm64 2>/dev/null)" = "1" ]] && \
   [[ "$(sysctl -n sysctl.proc_translated 2>/dev/null)" = "1" ]]; then
  exec arch -arm64e "${HOMEBREW_BREW_FILE}" "$@"
fi

# Where we store built products; a Cellar in HOMEBREW_PREFIX (often /usr/local
# for bottles) unless there's already a Cellar in HOMEBREW_REPOSITORY.
# These variables are set by bin/brew
# shellcheck disable=SC2154
if [[ -d "${HOMEBREW_REPOSITORY}/Cellar" ]]
then
  HOMEBREW_CELLAR="${HOMEBREW_REPOSITORY}/Cellar"
else
  HOMEBREW_CELLAR="${HOMEBREW_PREFIX}/Cellar"
fi

if [[ -n "${HOMEBREW_MACOS}" ]]
then
  HOMEBREW_DEFAULT_CACHE="${HOME}/Library/Caches/Homebrew"
  HOMEBREW_DEFAULT_LOGS="${HOME}/Library/Logs/Homebrew"
  HOMEBREW_DEFAULT_TEMP="/private/tmp"
else
  CACHE_HOME="${XDG_CACHE_HOME:-${HOME}/.cache}"
  HOMEBREW_DEFAULT_CACHE="${CACHE_HOME}/Homebrew"
  HOMEBREW_DEFAULT_LOGS="${CACHE_HOME}/Homebrew/Logs"
  HOMEBREW_DEFAULT_TEMP="/tmp"
fi

HOMEBREW_CACHE="${HOMEBREW_CACHE:-${HOMEBREW_DEFAULT_CACHE}}"
HOMEBREW_LOGS="${HOMEBREW_LOGS:-${HOMEBREW_DEFAULT_LOGS}}"
HOMEBREW_TEMP="${HOMEBREW_TEMP:-${HOMEBREW_DEFAULT_TEMP}}"

# Don't need to handle a default case.
# HOMEBREW_LIBRARY set by bin/brew
# shellcheck disable=SC2249,SC2154
case "$*" in
  --cellar)            echo "${HOMEBREW_CELLAR}"; exit 0 ;;
  --repository|--repo) echo "${HOMEBREW_REPOSITORY}"; exit 0 ;;
  --caskroom)          echo "${HOMEBREW_PREFIX}/Caskroom"; exit 0 ;;
  --cache)             echo "${HOMEBREW_CACHE}"; exit 0 ;;
  shellenv)            source "${HOMEBREW_LIBRARY}/Homebrew/cmd/shellenv.sh"; homebrew-shellenv; exit 0 ;;
  formulae)            source "${HOMEBREW_LIBRARY}/Homebrew/cmd/formulae.sh"; homebrew-formulae; exit 0 ;;
  casks)               source "${HOMEBREW_LIBRARY}/Homebrew/cmd/casks.sh"; homebrew-casks; exit 0 ;;
  # falls back to cmd/prefix.rb on a non-zero return
  --prefix*)           source "${HOMEBREW_LIBRARY}/Homebrew/prefix.sh"; homebrew-prefix "$@" && exit 0 ;;
esac

#####
##### Next, define all helper functions.
#####

# These variables are set from the user environment.
# shellcheck disable=SC2154
ohai() {
  if [[ -n "${HOMEBREW_COLOR}" || (-t 1 && -z "${HOMEBREW_NO_COLOR}") ]] # check whether stdout is a tty.
  then
    echo -e "\\033[34m==>\\033[0m \\033[1m$*\\033[0m" # blue arrow and bold text
  else
    echo "==> $*"
  fi
}

opoo() {
  if [[ -n "${HOMEBREW_COLOR}" || (-t 2 && -z "${HOMEBREW_NO_COLOR}") ]] # check whether stderr is a tty.
  then
    echo -ne "\\033[4;33mWarning\\033[0m: " >&2 # highlight Warning with underline and yellow color
  else
    echo -n "Warning: " >&2
  fi
  if [[ $# -eq 0 ]]
  then
    cat >&2
  else
    echo "$*" >&2
  fi
}

bold() {
  if [[ -n "${HOMEBREW_COLOR}" || (-t 2 && -z "${HOMEBREW_NO_COLOR}") ]] # check whether stderr is a tty.
  then
    echo -e "\\033[1m""$*""\\033[0m"
  else
    echo "$*"
  fi
}

onoe() {
  if [[ -n "${HOMEBREW_COLOR}" || (-t 2 && -z "${HOMEBREW_NO_COLOR}") ]] # check whether stderr is a tty.
  then
    echo -ne "\\033[4;31mError\\033[0m: " >&2 # highlight Error with underline and red color
  else
    echo -n "Error: " >&2
  fi
  if [[ $# -eq 0 ]]
  then
    cat >&2
  else
    echo "$*" >&2
  fi
}

odie() {
  onoe "$@"
  exit 1
}

safe_cd() {
  cd "$@" >/dev/null || odie "Failed to cd to $*!"
}

brew() {
  "${HOMEBREW_BREW_FILE}" "$@"
}

git() {
  "${HOMEBREW_LIBRARY}/Homebrew/shims/scm/git" "$@"
}

numeric() {
  # Condense the exploded argument into a single return value.
  # shellcheck disable=SC2086,SC2183
  printf "%01d%02d%02d%03d" ${1//[.rc]/ } 2>/dev/null
}

check-run-command-as-root() {
  [[ "$(id -u)" = 0 ]] || return

  # Allow Azure Pipelines/GitHub Actions/Docker/Concourse/Kubernetes to do everything as root (as it's normal there)
  [[ -f /proc/1/cgroup ]] && grep -E "azpl_job|actions_job|docker|garden|kubepods" -q /proc/1/cgroup && return

  # Homebrew Services may need `sudo` for system-wide daemons.
  [[ "${HOMEBREW_COMMAND}" = "services" ]] && return

  # It's fine to run this as root as it's not changing anything.
  [[ "${HOMEBREW_COMMAND}" = "--prefix" ]] && return

  odie <<EOS
Running Homebrew as root is extremely dangerous and no longer supported.
As Homebrew does not drop privileges on installation you would be giving all
build scripts full access to your system.
EOS
}

check-prefix-is-not-tmpdir() {
  [[ -z "${HOMEBREW_MACOS}" ]] && return

  if [[ "${HOMEBREW_PREFIX}" = "${HOMEBREW_TEMP}"* ]]
  then
    odie <<EOS
Your HOMEBREW_PREFIX is in the Homebrew temporary directory, which Homebrew
uses to store downloads and builds. You can resolve this by installing Homebrew to
either the standard prefix (/usr/local) or to a non-standard prefix that is not
in the Homebrew temporary directory.
EOS
  fi
}

# Let user know we're still updating Homebrew if brew update --preinstall
# exceeds 3 seconds.
update-preinstall-timer() {
  sleep 3
  echo 'Updating Homebrew...' >&2
}

# These variables are set from various Homebrew scripts.
# shellcheck disable=SC2154
update-preinstall() {
  [[ -z "${HOMEBREW_HELP}" ]] || return
  [[ -z "${HOMEBREW_NO_AUTO_UPDATE}" ]] || return
  [[ -z "${HOMEBREW_AUTO_UPDATING}" ]] || return
  [[ -z "${HOMEBREW_UPDATE_PREINSTALL}" ]] || return
  [[ -z "${HOMEBREW_AUTO_UPDATE_CHECKED}" ]] || return

  # If we've checked for updates, we don't need to check again.
  export HOMEBREW_AUTO_UPDATE_CHECKED="1"

  if [[ "${HOMEBREW_COMMAND}" = "install" || "${HOMEBREW_COMMAND}" = "upgrade" ||
        "${HOMEBREW_COMMAND}" = "bump-formula-pr" || "${HOMEBREW_COMMAND}" = "bump-cask-pr" ||
        "${HOMEBREW_COMMAND}" = "bundle" || "${HOMEBREW_COMMAND}" = "release" ||
        "${HOMEBREW_COMMAND}" = "tap" && ${HOMEBREW_ARG_COUNT} -gt 1 ]]
  then
    export HOMEBREW_AUTO_UPDATING="1"

    if [[ -z "${HOMEBREW_AUTO_UPDATE_SECS}" ]]
    then
      HOMEBREW_AUTO_UPDATE_SECS="300"
    fi

    # Skip auto-update if the repository has been updated in the
    # last $HOMEBREW_AUTO_UPDATE_SECS.
    repo_fetch_head="${HOMEBREW_REPOSITORY}/.git/FETCH_HEAD"
    if [[ -f "${repo_fetch_head}" &&
          -n "$(find "${repo_fetch_head}" -type f -mtime -"${HOMEBREW_AUTO_UPDATE_SECS}"s 2>/dev/null)" ]]
    then
      return
    fi

    if [[ -z "${HOMEBREW_VERBOSE}" ]]
    then
      update-preinstall-timer &
      timer_pid=$!
    fi

    brew update --preinstall

    if [[ -n "${timer_pid}" ]]
    then
      kill "${timer_pid}" 2>/dev/null
      wait "${timer_pid}" 2>/dev/null
    fi

    unset HOMEBREW_AUTO_UPDATING

    # exec a new process to set any new environment variables.
    exec "${HOMEBREW_BREW_FILE}" "$@"
  fi
}

#####
##### Setup output so e.g. odie looks as nice as possible.
#####

# Colorize output on GitHub Actions.
# This is set by the user environment.
# shellcheck disable=SC2154
if [[ -n "${GITHUB_ACTIONS}" ]]; then
  export HOMEBREW_COLOR="1"
fi

# Force UTF-8 to avoid encoding issues for users with broken locale settings.
if [[ -n "${HOMEBREW_MACOS}" ]]
then
  if [[ "$(locale charmap)" != "UTF-8" ]]
  then
    export LC_ALL="en_US.UTF-8"
  fi
else
  if ! command -v locale >/dev/null
  then
    export LC_ALL=C
  elif [[ "$(locale charmap)" != "UTF-8" ]]
  then
    locales=$(locale -a)
    c_utf_regex='\bC\.(utf8|UTF-8)\b'
    en_us_regex='\ben_US\.(utf8|UTF-8)\b'
    utf_regex='\b[a-z][a-z]_[A-Z][A-Z]\.(utf8|UTF-8)\b'
    if [[ ${locales} =~ ${c_utf_regex} || ${locales} =~ ${en_us_regex} || ${locales} =~ ${utf_regex} ]]
    then
      export LC_ALL=${BASH_REMATCH[0]}
    else
      export LC_ALL=C
    fi
  fi
fi

#####
##### odie as quickly as possible.
#####

if [[ "${HOMEBREW_PREFIX}" = "/" || "${HOMEBREW_PREFIX}" = "/usr" ]]
then
  # it may work, but I only see pain this route and don't want to support it
  odie "Cowardly refusing to continue at this prefix: ${HOMEBREW_PREFIX}"
fi

# Many Pathname operations use getwd when they shouldn't, and then throw
# odd exceptions. Reduce our support burden by showing a user-friendly error.
if [[ ! -d "$(pwd)" ]]
then
  odie "The current working directory doesn't exist, cannot proceed."
fi

#####
##### Now, do everything else (that may be a bit slower).
#####

# USER isn't always set so provide a fall back for `brew` and subprocesses.
export USER=${USER:-$(id -un)}

# A depth of 1 means this command was directly invoked by a user.
# Higher depths mean this command was invoked by another Homebrew command.
export HOMEBREW_COMMAND_DEPTH=$((HOMEBREW_COMMAND_DEPTH + 1))

# This is set by the user environment.
# shellcheck disable=SC2154
if [[ -n "${HOMEBREW_FORCE_BREWED_CURL}" &&
      -x "${HOMEBREW_PREFIX}/opt/curl/bin/curl" ]] &&
         "${HOMEBREW_PREFIX}/opt/curl/bin/curl" --version >/dev/null
then
  HOMEBREW_CURL="${HOMEBREW_PREFIX}/opt/curl/bin/curl"
elif [[ -n "${HOMEBREW_DEVELOPER}" && -x "${HOMEBREW_CURL_PATH}" ]]
then
  HOMEBREW_CURL="${HOMEBREW_CURL_PATH}"
else
  HOMEBREW_CURL="curl"
fi

# This is set by the user environment.
# shellcheck disable=SC2154
if [[ -n "${HOMEBREW_FORCE_BREWED_GIT}" &&
      -x "${HOMEBREW_PREFIX}/opt/git/bin/git" ]] &&
         "${HOMEBREW_PREFIX}/opt/git/bin/git" --version >/dev/null
then
  HOMEBREW_GIT="${HOMEBREW_PREFIX}/opt/git/bin/git"
elif [[ -n "${HOMEBREW_DEVELOPER}" && -x "${HOMEBREW_GIT_PATH}" ]]
then
  HOMEBREW_GIT="${HOMEBREW_GIT_PATH}"
else
  HOMEBREW_GIT="git"
fi

HOMEBREW_VERSION="$("${HOMEBREW_GIT}" -C "${HOMEBREW_REPOSITORY}" describe --tags --dirty --abbrev=7 2>/dev/null)"
HOMEBREW_USER_AGENT_VERSION="${HOMEBREW_VERSION}"
if [[ -z "${HOMEBREW_VERSION}" ]]
then
  HOMEBREW_VERSION=">=2.5.0 (shallow or no git repository)"
  HOMEBREW_USER_AGENT_VERSION="2.X.Y"
fi

HOMEBREW_CORE_REPOSITORY="${HOMEBREW_LIBRARY}/Taps/homebrew/homebrew-core"
# Used in --version.sh
# shellcheck disable=SC2034
HOMEBREW_CASK_REPOSITORY="${HOMEBREW_LIBRARY}/Taps/homebrew/homebrew-cask"

case "$*" in
  --version|-v) source "${HOMEBREW_LIBRARY}/Homebrew/cmd/--version.sh"; homebrew-version; exit 0 ;;
esac

# shellcheck disable=SC2154
if [[ -n "${HOMEBREW_SIMULATE_MACOS_ON_LINUX}" ]]
then
  export HOMEBREW_FORCE_HOMEBREW_ON_LINUX="1"
fi

if [[ -n "${HOMEBREW_MACOS}" ]]
then
  HOMEBREW_PRODUCT="Homebrew"
  HOMEBREW_SYSTEM="Macintosh"
  [[ "${HOMEBREW_PROCESSOR}" = "x86_64" ]] && HOMEBREW_PROCESSOR="Intel"
  HOMEBREW_MACOS_VERSION="$(/usr/bin/sw_vers -productVersion)"
  # Don't change this from Mac OS X to match what macOS itself does in Safari on 10.12
  HOMEBREW_OS_USER_AGENT_VERSION="Mac OS X ${HOMEBREW_MACOS_VERSION}"

  # Intentionally set this variable by exploding another.
  # shellcheck disable=SC2086,SC2183
  printf -v HOMEBREW_MACOS_VERSION_NUMERIC "%02d%02d%02d" ${HOMEBREW_MACOS_VERSION//./ }

  # Don't include minor versions for Big Sur and later.
  if [[ "${HOMEBREW_MACOS_VERSION_NUMERIC}" -gt "110000" ]]
  then
    HOMEBREW_OS_VERSION="macOS ${HOMEBREW_MACOS_VERSION%.*}"
  else
    HOMEBREW_OS_VERSION="macOS ${HOMEBREW_MACOS_VERSION}"
  fi

  # Refuse to run on pre-Yosemite
  if [[ "${HOMEBREW_MACOS_VERSION_NUMERIC}" -lt "101000" ]]
  then
    printf "ERROR: Your version of macOS (%s) is too old to run Homebrew!\\n" "${HOMEBREW_MACOS_VERSION}" >&2
    if [[ "${HOMEBREW_MACOS_VERSION_NUMERIC}" -lt "100700" ]]
    then
      printf "         For 10.4 - 10.6 support see: https://github.com/mistydemeo/tigerbrew\\n" >&2
    fi
    printf "\\n" >&2
  fi

  # The system Git on macOS versions before Sierra is too old for some Homebrew functionality we rely on.
  HOMEBREW_MINIMUM_GIT_VERSION="2.14.3"
  if [[ "${HOMEBREW_MACOS_VERSION_NUMERIC}" -lt "101200" ]]
  then
    HOMEBREW_FORCE_BREWED_GIT="1"
  fi

  # Set a variable when the macOS system Ruby is new enough to avoid spawning
  # a Ruby process unnecessarily.
  # On Catalina the system Ruby is technically new enough but don't allow it:
  # https://github.com/Homebrew/brew/issues/9410
  if [[ "${HOMEBREW_MACOS_VERSION_NUMERIC}" -lt "101600" ]]
  then
    unset HOMEBREW_MACOS_SYSTEM_RUBY_NEW_ENOUGH
  else
    # Used in ruby.sh.
    # shellcheck disable=SC2034
    HOMEBREW_MACOS_SYSTEM_RUBY_NEW_ENOUGH="1"
  fi
else
  HOMEBREW_PRODUCT="${HOMEBREW_SYSTEM}brew"
  [[ -n "${HOMEBREW_LINUX}" ]] && HOMEBREW_OS_VERSION="$(lsb_release -sd 2>/dev/null)"
  : "${HOMEBREW_OS_VERSION:=$(uname -r)}"
  HOMEBREW_OS_USER_AGENT_VERSION="${HOMEBREW_OS_VERSION}"

  # This is set by the user environment.
  # shellcheck disable=SC2154
  if [[ -n "${HOMEBREW_FORCE_HOMEBREW_ON_LINUX}" && -n "${HOMEBREW_ON_DEBIAN7}" ]]
  then
    # Special version for our debian 7 docker container used to build patchelf and binutils
    HOMEBREW_MINIMUM_CURL_VERSION="7.25.0"
  else
    # Ensure the system Curl is a version that supports modern HTTPS certificates.
    HOMEBREW_MINIMUM_CURL_VERSION="7.41.0"
  fi
  curl_version_output="$(${HOMEBREW_CURL} --version 2>/dev/null)"
  curl_name_and_version="${curl_version_output%% (*}"
  # shellcheck disable=SC2248
  if [[ $(numeric "${curl_name_and_version##* }") -lt $(numeric "${HOMEBREW_MINIMUM_CURL_VERSION}") ]]
  then
      message="Please update your system curl.
Minimum required version: ${HOMEBREW_MINIMUM_CURL_VERSION}
Your curl version: ${curl_name_and_version##* }
Your curl executable: $(type -p ${HOMEBREW_CURL})"

    if [[ -z ${HOMEBREW_CURL_PATH} || -z ${HOMEBREW_DEVELOPER} ]]; then
      HOMEBREW_SYSTEM_CURL_TOO_OLD=1
      HOMEBREW_FORCE_BREWED_CURL=1
      if [[ -z ${HOMEBREW_CURL_WARNING} ]]; then
        onoe "${message}"
        HOMEBREW_CURL_WARNING=1
      fi
    else
      odie "${message}"
    fi
  fi

  # Ensure the system Git is at or newer than the minimum required version.
  # Git 2.7.4 is the version of git on Ubuntu 16.04 LTS (Xenial Xerus).
  HOMEBREW_MINIMUM_GIT_VERSION="2.7.0"
  git_version_output="$(${HOMEBREW_GIT} --version 2>/dev/null)"
  # $extra is intentionally discarded.
  # shellcheck disable=SC2034
  IFS=. read -r major minor micro build extra <<< "${git_version_output##* }"
  # shellcheck disable=SC2248
  if [[ $(numeric "${major}.${minor}.${micro}.${build}") -lt $(numeric "${HOMEBREW_MINIMUM_GIT_VERSION}") ]]
  then
    message="Please update your system Git.
Minimum required version: ${HOMEBREW_MINIMUM_GIT_VERSION}
Your Git version: ${major}.${minor}.${micro}.${build}
Your Git executable: $(unset git && type -p ${HOMEBREW_GIT})"
    if [[ -z ${HOMEBREW_GIT_PATH} || -z ${HOMEBREW_DEVELOPER} ]]; then
      HOMEBREW_FORCE_BREWED_GIT="1"
      if [[ -z ${HOMEBREW_GIT_WARNING} ]]; then
        onoe "${message}"
        HOMEBREW_GIT_WARNING=1
      fi
    else
      odie "${message}"
    fi
  fi

  HOMEBREW_LINUX_MINIMUM_GLIBC_VERSION="2.13"
  unset HOMEBREW_MACOS_SYSTEM_RUBY_NEW_ENOUGH
fi

# A bug in the auto-update process prior to 3.1.2 means $HOMEBREW_BOTTLE_DOMAIN
# could be passed down with the default domain.
# This is problematic as this is will be the old bottle domain.
# This workaround is necessary for many CI images starting on old version,
# and will only be unnecessary when updating from <3.1.2 is not a concern.
# That will be when macOS 12 is the minimum required version.
# HOMEBREW_BOTTLE_DOMAIN is set from the user environment
# shellcheck disable=SC2154
if [[ -n "${HOMEBREW_BOTTLE_DEFAULT_DOMAIN}" && "${HOMEBREW_BOTTLE_DOMAIN}" = "${HOMEBREW_BOTTLE_DEFAULT_DOMAIN}" ]]
then
  unset HOMEBREW_BOTTLE_DOMAIN
fi

if [[ -n "${HOMEBREW_MACOS}" || -n "${HOMEBREW_FORCE_HOMEBREW_ON_LINUX}" ]]
then
  HOMEBREW_BOTTLE_DEFAULT_DOMAIN="https://ghcr.io/v2/homebrew/core"
else
  HOMEBREW_BOTTLE_DEFAULT_DOMAIN="https://ghcr.io/v2/linuxbrew/core"
fi

HOMEBREW_USER_AGENT="${HOMEBREW_PRODUCT}/${HOMEBREW_USER_AGENT_VERSION} (${HOMEBREW_SYSTEM}; ${HOMEBREW_PROCESSOR} ${HOMEBREW_OS_USER_AGENT_VERSION})"
curl_version_output="$("${HOMEBREW_CURL}" --version 2>/dev/null)"
curl_name_and_version="${curl_version_output%% (*}"
HOMEBREW_USER_AGENT_CURL="${HOMEBREW_USER_AGENT} ${curl_name_and_version// //}"

export HOMEBREW_VERSION
export HOMEBREW_DEFAULT_CACHE
export HOMEBREW_CACHE
export HOMEBREW_DEFAULT_LOGS
export HOMEBREW_LOGS
export HOMEBREW_DEFAULT_TEMP
export HOMEBREW_TEMP
export HOMEBREW_CELLAR
export HOMEBREW_SYSTEM
export HOMEBREW_CURL
export HOMEBREW_CURL_WARNING
export HOMEBREW_SYSTEM_CURL_TOO_OLD
export HOMEBREW_GIT
export HOMEBREW_GIT_WARNING
export HOMEBREW_MINIMUM_GIT_VERSION
export HOMEBREW_LINUX_MINIMUM_GLIBC_VERSION
export HOMEBREW_PROCESSOR
export HOMEBREW_PRODUCT
export HOMEBREW_OS_VERSION
export HOMEBREW_MACOS_VERSION
export HOMEBREW_MACOS_VERSION_NUMERIC
export HOMEBREW_USER_AGENT
export HOMEBREW_USER_AGENT_CURL
export HOMEBREW_BOTTLE_DEFAULT_DOMAIN
export HOMEBREW_MACOS_SYSTEM_RUBY_NEW_ENOUGH

if [[ -n "${HOMEBREW_MACOS}" && -x "/usr/bin/xcode-select" ]]
then
  XCODE_SELECT_PATH=$('/usr/bin/xcode-select' --print-path 2>/dev/null)
  if [[ "${XCODE_SELECT_PATH}" = "/" ]]
  then
    odie <<EOS
Your xcode-select path is currently set to '/'.
This causes the 'xcrun' tool to hang, and can render Homebrew unusable.
If you are using Xcode, you should:
  sudo xcode-select --switch /Applications/Xcode.app
Otherwise, you should:
  sudo rm -rf /usr/share/xcode-select
EOS
  fi

  # Don't check xcrun if Xcode and the CLT aren't installed, as that opens
  # a popup window asking the user to install the CLT
  if [[ -n "${XCODE_SELECT_PATH}" ]]
  then
    XCRUN_OUTPUT="$(/usr/bin/xcrun clang 2>&1)"
    XCRUN_STATUS="$?"

    if [[ "${XCRUN_STATUS}" -ne 0 && "${XCRUN_OUTPUT}" = *license* ]]
    then
      odie <<EOS
You have not agreed to the Xcode license. Please resolve this by running:
  sudo xcodebuild -license accept
EOS
    fi
  fi
fi

if [[ "$1" = -v ]]
then
  # Shift the -v to the end of the parameter list
  shift
  set -- "$@" -v
fi

for arg in "$@"
do
  [[ ${arg} = "--" ]] && break

  if [[ ${arg} = "--help" || ${arg} = "-h" || ${arg} = "--usage" || ${arg} = "-?" ]]
  then
    export HOMEBREW_HELP="1"
    break
  fi
done

HOMEBREW_ARG_COUNT="$#"
HOMEBREW_COMMAND="$1"
shift
case "${HOMEBREW_COMMAND}" in
  ls)          HOMEBREW_COMMAND="list" ;;
  homepage)    HOMEBREW_COMMAND="home" ;;
  -S)          HOMEBREW_COMMAND="search" ;;
  up)          HOMEBREW_COMMAND="update" ;;
  ln)          HOMEBREW_COMMAND="link" ;;
  instal)      HOMEBREW_COMMAND="install" ;; # gem does the same
  uninstal)    HOMEBREW_COMMAND="uninstall" ;;
  rm)          HOMEBREW_COMMAND="uninstall" ;;
  remove)      HOMEBREW_COMMAND="uninstall" ;;
  configure)   HOMEBREW_COMMAND="diy" ;;
  abv)         HOMEBREW_COMMAND="info" ;;
  dr)          HOMEBREW_COMMAND="doctor" ;;
  --repo)      HOMEBREW_COMMAND="--repository" ;;
  environment) HOMEBREW_COMMAND="--env" ;;
  --config)    HOMEBREW_COMMAND="config" ;;
  -v)          HOMEBREW_COMMAND="--version" ;;
esac

# Set HOMEBREW_DEV_CMD_RUN for users who have run a development command.
# This makes them behave like HOMEBREW_DEVELOPERs for brew update.
if [[ -z "${HOMEBREW_DEVELOPER}" ]]
then
  export HOMEBREW_GIT_CONFIG_FILE="${HOMEBREW_REPOSITORY}/.git/config"
  HOMEBREW_GIT_CONFIG_DEVELOPERMODE="$(git config --file="${HOMEBREW_GIT_CONFIG_FILE}" --get homebrew.devcmdrun 2>/dev/null)"
  if [[ "${HOMEBREW_GIT_CONFIG_DEVELOPERMODE}" = "true" ]]
  then
    export HOMEBREW_DEV_CMD_RUN="1"
  fi

  # Don't allow non-developers to customise Ruby warnings.
  unset HOMEBREW_RUBY_WARNINGS
fi

# Disable Ruby options we don't need.
RUBY_DISABLE_OPTIONS="--disable=rubyopt"

if [[ -z "${HOMEBREW_RUBY_WARNINGS}" ]]
then
  export HOMEBREW_RUBY_WARNINGS="-W1"
fi

export HOMEBREW_BREW_DEFAULT_GIT_REMOTE="https://github.com/Homebrew/brew"
if [[ -z "${HOMEBREW_BREW_GIT_REMOTE}" ]]
then
  HOMEBREW_BREW_GIT_REMOTE="${HOMEBREW_BREW_DEFAULT_GIT_REMOTE}"
fi
export HOMEBREW_BREW_GIT_REMOTE

if [[ -n "${HOMEBREW_MACOS}" ]] || [[ -n "${HOMEBREW_FORCE_HOMEBREW_ON_LINUX}" ]]
then
  HOMEBREW_CORE_DEFAULT_GIT_REMOTE="https://github.com/Homebrew/homebrew-core"
else
  HOMEBREW_CORE_DEFAULT_GIT_REMOTE="https://github.com/Homebrew/linuxbrew-core"
fi
export HOMEBREW_CORE_DEFAULT_GIT_REMOTE

if [[ -z "${HOMEBREW_CORE_GIT_REMOTE}" ]]
then
  HOMEBREW_CORE_GIT_REMOTE="${HOMEBREW_CORE_DEFAULT_GIT_REMOTE}"
fi
export HOMEBREW_CORE_GIT_REMOTE

if [[ -f "${HOMEBREW_LIBRARY}/Homebrew/cmd/${HOMEBREW_COMMAND}.sh" ]]
then
  HOMEBREW_BASH_COMMAND="${HOMEBREW_LIBRARY}/Homebrew/cmd/${HOMEBREW_COMMAND}.sh"
elif [[ -f "${HOMEBREW_LIBRARY}/Homebrew/dev-cmd/${HOMEBREW_COMMAND}.sh" ]]
then
  if [[ -z "${HOMEBREW_DEVELOPER}" ]]
  then
    if [[ -z "${HOMEBREW_DEV_CMD_RUN}" ]]
    then
      message="$(bold "${HOMEBREW_COMMAND}") is a developer command, so
Homebrew's developer mode has been automatically turned on.
To turn developer mode off, run $(bold "brew developer off")
"
      opoo "${message}"
    fi

    git config --file="${HOMEBREW_GIT_CONFIG_FILE}" --replace-all homebrew.devcmdrun true 2>/dev/null
    export HOMEBREW_DEV_CMD_RUN="1"
  fi
  HOMEBREW_BASH_COMMAND="${HOMEBREW_LIBRARY}/Homebrew/dev-cmd/${HOMEBREW_COMMAND}.sh"
fi

check-run-command-as-root

check-prefix-is-not-tmpdir

# shellcheck disable=SC2250
if [[ "${HOMEBREW_PREFIX}" = "/usr/local" &&
      "${HOMEBREW_PREFIX}" != "${HOMEBREW_REPOSITORY}" &&
      "${HOMEBREW_CELLAR}" = "${HOMEBREW_REPOSITORY}/Cellar" ]]
then
  cat >&2 <<EOS
Warning: your HOMEBREW_PREFIX is set to /usr/local but HOMEBREW_CELLAR is set
to $HOMEBREW_CELLAR. Your current HOMEBREW_CELLAR location will stop
you being able to use all the binary packages (bottles) Homebrew provides. We
recommend you move your HOMEBREW_CELLAR to /usr/local/Cellar which will get you
access to all bottles."
EOS
fi

source "${HOMEBREW_LIBRARY}/Homebrew/utils/analytics.sh"
setup-analytics

if [[ -n "${HOMEBREW_BASH_COMMAND}" ]]
then
  # source rather than executing directly to ensure the entire file is read into
  # memory before it is run. This makes running a Bash script behave more like
  # a Ruby script and avoids hard-to-debug issues if the Bash script is updated
  # at the same time as being run.
  #
  # Shellcheck can't follow this dynamic `source`.
  # shellcheck disable=SC1090
  source "${HOMEBREW_BASH_COMMAND}"
  { update-preinstall "$@"; "homebrew-${HOMEBREW_COMMAND}" "$@"; exit $?; }
else
  source "${HOMEBREW_LIBRARY}/Homebrew/utils/ruby.sh"
  setup-ruby-path

  # Unshift command back into argument list (unless argument list was empty).
  [[ "${HOMEBREW_ARG_COUNT}" -gt 0 ]] && set -- "${HOMEBREW_COMMAND}" "$@"
  # HOMEBREW_RUBY_PATH set by utils/ruby.sh
  # shellcheck disable=SC2154
  { update-preinstall "$@"; exec "${HOMEBREW_RUBY_PATH}" "${HOMEBREW_RUBY_WARNINGS}" "${RUBY_DISABLE_OPTIONS}" "${HOMEBREW_LIBRARY}/Homebrew/brew.rb" "$@"; }
fi
