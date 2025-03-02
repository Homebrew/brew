#####
##### First do the essential, fast things to ensure commands like `brew --prefix` and others that we want
##### to be able to `source` in shell configurations run quickly.
#####

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
HOMEBREW_MACOS_ARM_DEFAULT_REPOSITORY="${HOMEBREW_MACOS_ARM_DEFAULT_PREFIX}"
HOMEBREW_LINUX_DEFAULT_PREFIX="/home/linuxbrew/.linuxbrew"
HOMEBREW_LINUX_DEFAULT_REPOSITORY="${HOMEBREW_LINUX_DEFAULT_PREFIX}/Homebrew"
HOMEBREW_GENERIC_DEFAULT_PREFIX="/usr/local"
HOMEBREW_GENERIC_DEFAULT_REPOSITORY="${HOMEBREW_GENERIC_DEFAULT_PREFIX}/Homebrew"
if [[ -n "${HOMEBREW_MACOS}" && "${HOMEBREW_PROCESSOR}" == "arm64" ]]
then
  HOMEBREW_DEFAULT_PREFIX="${HOMEBREW_MACOS_ARM_DEFAULT_PREFIX}"
  HOMEBREW_DEFAULT_REPOSITORY="${HOMEBREW_MACOS_ARM_DEFAULT_REPOSITORY}"
elif [[ -n "${HOMEBREW_LINUX}" ]]
then
  HOMEBREW_DEFAULT_PREFIX="${HOMEBREW_LINUX_DEFAULT_PREFIX}"
  HOMEBREW_DEFAULT_REPOSITORY="${HOMEBREW_LINUX_DEFAULT_REPOSITORY}"
else
  HOMEBREW_DEFAULT_PREFIX="${HOMEBREW_GENERIC_DEFAULT_PREFIX}"
  HOMEBREW_DEFAULT_REPOSITORY="${HOMEBREW_GENERIC_DEFAULT_REPOSITORY}"
fi

if [[ -n "${HOMEBREW_MACOS}" ]]
then
  HOMEBREW_DEFAULT_CACHE="${HOME}/Library/Caches/Homebrew"
  HOMEBREW_DEFAULT_LOGS="${HOME}/Library/Logs/Homebrew"
  HOMEBREW_DEFAULT_TEMP="/private/tmp"

  HOMEBREW_MACOS_VERSION="$(/usr/bin/sw_vers -productVersion)"

  IFS=. read -r -a MACOS_VERSION_ARRAY <<<"${HOMEBREW_MACOS_VERSION}"
  printf -v HOMEBREW_MACOS_VERSION_NUMERIC "%02d%02d%02d" "${MACOS_VERSION_ARRAY[@]}"

  unset MACOS_VERSION_ARRAY
else
  CACHE_HOME="${HOMEBREW_XDG_CACHE_HOME:-${HOME}/.cache}"
  HOMEBREW_DEFAULT_CACHE="${CACHE_HOME}/Homebrew"
  HOMEBREW_DEFAULT_LOGS="${CACHE_HOME}/Homebrew/Logs"
  HOMEBREW_DEFAULT_TEMP="/tmp"
fi

realpath() {
  (cd "$1" &>/dev/null && pwd -P)
}

# Support systems where HOMEBREW_PREFIX is the default,
# but a parent directory is a symlink.
# Example: Fedora Silverblue symlinks /home -> var/home
if [[ "${HOMEBREW_PREFIX}" != "${HOMEBREW_DEFAULT_PREFIX}" && "$(realpath "${HOMEBREW_DEFAULT_PREFIX}")" == "${HOMEBREW_PREFIX}" ]]
then
  HOMEBREW_PREFIX="${HOMEBREW_DEFAULT_PREFIX}"
fi

# Support systems where HOMEBREW_REPOSITORY is the default,
# but a parent directory is a symlink.
# Example: Fedora Silverblue symlinks /home -> var/home
if [[ "${HOMEBREW_REPOSITORY}" != "${HOMEBREW_DEFAULT_REPOSITORY}" && "$(realpath "${HOMEBREW_DEFAULT_REPOSITORY}")" == "${HOMEBREW_REPOSITORY}" ]]
then
  HOMEBREW_REPOSITORY="${HOMEBREW_DEFAULT_REPOSITORY}"
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

HOMEBREW_CASKROOM="${HOMEBREW_PREFIX}/Caskroom"

HOMEBREW_CACHE="${HOMEBREW_CACHE:-${HOMEBREW_DEFAULT_CACHE}}"
HOMEBREW_LOGS="${HOMEBREW_LOGS:-${HOMEBREW_DEFAULT_LOGS}}"
HOMEBREW_TEMP="${HOMEBREW_TEMP:-${HOMEBREW_DEFAULT_TEMP}}"

# commands that take a single or no arguments.
# HOMEBREW_LIBRARY set by bin/brew
# shellcheck disable=SC2154
# doesn't need a default case as other arguments handled elsewhere.
# shellcheck disable=SC2249
case "$1" in
  formulae)
    source "${HOMEBREW_LIBRARY}/Homebrew/cmd/formulae.sh"
    homebrew-formulae
    exit 0
    ;;
  casks)
    source "${HOMEBREW_LIBRARY}/Homebrew/cmd/casks.sh"
    homebrew-casks
    exit 0
    ;;
  shellenv)
    source "${HOMEBREW_LIBRARY}/Homebrew/cmd/shellenv.sh"
    shift
    homebrew-shellenv "$1"
    exit 0
    ;;
esac

source "${HOMEBREW_LIBRARY}/Homebrew/help.sh"

# functions that take multiple arguments or handle multiple commands.
# doesn't need a default case as other arguments handled elsewhere.
# shellcheck disable=SC2249
case "$@" in
  --cellar)
    echo "${HOMEBREW_CELLAR}"
    exit 0
    ;;
  --repository | --repo)
    echo "${HOMEBREW_REPOSITORY}"
    exit 0
    ;;
  --caskroom)
    echo "${HOMEBREW_CASKROOM}"
    exit 0
    ;;
  --cache)
    echo "${HOMEBREW_CACHE}"
    exit 0
    ;;
  # falls back to cmd/--prefix.rb and cmd/--cellar.rb on a non-zero return
  --prefix* | --cellar*)
    source "${HOMEBREW_LIBRARY}/Homebrew/formula_path.sh"
    homebrew-formula-path "$@" && exit 0
    ;;
  # falls back to cmd/command.rb on a non-zero return
  command*)
    source "${HOMEBREW_LIBRARY}/Homebrew/command_path.sh"
    homebrew-command-path "$@" && exit 0
    ;;
  # falls back to cmd/list.rb on a non-zero return
  list* | ls*)
    source "${HOMEBREW_LIBRARY}/Homebrew/list.sh"
    homebrew-list "$@" && exit 0
    ;;
  # homebrew-tap only handles invocations with no arguments
  tap)
    source "${HOMEBREW_LIBRARY}/Homebrew/tap.sh"
    homebrew-tap "$@"
    exit 0
    ;;
  # falls back to cmd/help.rb on a non-zero return
  help | --help | -h | --usage | "-?" | "")
    homebrew-help "$@" && exit 0
    ;;
esac

# Include some helper functions.
source "${HOMEBREW_LIBRARY}/Homebrew/utils/helpers.sh"

# Require HOMEBREW_BREW_WRAPPER to be set if HOMEBREW_FORCE_BREW_WRAPPER is set
# (and HOMEBREW_NO_FORCE_BREW_WRAPPER is not set) for all non-trivial commands
# (i.e. not defined above this line e.g. formulae or --cellar).
if [[ -z "${HOMEBREW_NO_FORCE_BREW_WRAPPER:-}" && -n "${HOMEBREW_FORCE_BREW_WRAPPER:-}" ]]
then
  HOMEBREW_FORCE_BREW_WRAPPER_WITHOUT_BREW="${HOMEBREW_FORCE_BREW_WRAPPER%/brew}"
  if [[ -z "${HOMEBREW_BREW_WRAPPER:-}" ]]
  then
    odie <<EOS
conflicting Homebrew wrapper configuration!
HOMEBREW_FORCE_BREW_WRAPPER was set to ${HOMEBREW_FORCE_BREW_WRAPPER}
but   HOMEBREW_BREW_WRAPPER was unset.

$(bold "Ensure you run ${HOMEBREW_FORCE_BREW_WRAPPER} directly (not ${HOMEBREW_BREW_FILE})")!

Manually setting your PATH can interfere with Homebrew wrappers.
Ensure your shell configuration contains:
  eval "\$(${HOMEBREW_BREW_FILE} shellenv)"
or that ${HOMEBREW_FORCE_BREW_WRAPPER_WITHOUT_BREW} comes before ${HOMEBREW_PREFIX}/bin in your PATH:
  export PATH="${HOMEBREW_FORCE_BREW_WRAPPER_WITHOUT_BREW}:${HOMEBREW_PREFIX}/bin:\$PATH"
EOS
  elif [[ "${HOMEBREW_FORCE_BREW_WRAPPER}" != "${HOMEBREW_BREW_WRAPPER}" ]]
  then
    odie <<EOS
conflicting Homebrew wrapper configuration!
HOMEBREW_FORCE_BREW_WRAPPER was set to ${HOMEBREW_FORCE_BREW_WRAPPER}
but HOMEBREW_BREW_WRAPPER   was set to ${HOMEBREW_BREW_WRAPPER}

$(bold "Ensure you run ${HOMEBREW_FORCE_BREW_WRAPPER} directly (not ${HOMEBREW_BREW_FILE})")!

Manually setting your PATH can interfere with Homebrew wrappers.
Ensure your shell configuration contains:
  eval "\$(${HOMEBREW_BREW_FILE} shellenv)"
or that ${HOMEBREW_FORCE_BREW_WRAPPER_WITHOUT_BREW} comes before ${HOMEBREW_PREFIX}/bin in your PATH:
  export PATH="${HOMEBREW_FORCE_BREW_WRAPPER_WITHOUT_BREW}:${HOMEBREW_PREFIX}/bin:\$PATH"
EOS
  fi
fi

# commands that take a single or no arguments and need to write to HOMEBREW_PREFIX.
# HOMEBREW_LIBRARY set by bin/brew
# shellcheck disable=SC2154
# doesn't need a default case as other arguments handled elsewhere.
# shellcheck disable=SC2249
case "$1" in
  setup-ruby)
    source "${HOMEBREW_LIBRARY}/Homebrew/cmd/setup-ruby.sh"
    shift
    homebrew-setup-ruby "$1"
    exit 0
    ;;
esac

#####
##### Next, define all other helper functions.
#####

check-run-command-as-root() {
  [[ "${EUID}" == 0 || "${UID}" == 0 ]] || return

  # Allow Azure Pipelines/GitHub Actions/Docker/Podman/Concourse/Kubernetes to do everything as root (as it's normal there)
  [[ -f /.dockerenv ]] && return
  [[ -f /run/.containerenv ]] && return
  [[ -f /proc/1/cgroup ]] && grep -E "azpl_job|actions_job|docker|garden|kubepods" -q /proc/1/cgroup && return

  # Homebrew Services may need `sudo` for system-wide daemons.
  [[ "${HOMEBREW_COMMAND}" == "services" ]] && return

  # It's fine to run this as root as it's not changing anything.
  [[ "${HOMEBREW_COMMAND}" == "--prefix" ]] && return

  odie <<EOS
Running Homebrew as root is extremely dangerous and no longer supported.
As Homebrew does not drop privileges on installation you would be giving all
build scripts full access to your system.
EOS
}

check-prefix-is-not-tmpdir() {
  [[ -z "${HOMEBREW_MACOS}" ]] && return

  if [[ "${HOMEBREW_PREFIX}" == "${HOMEBREW_TEMP}"* ]]
  then
    odie <<EOS
Your HOMEBREW_PREFIX is in the Homebrew temporary directory, which Homebrew
uses to store downloads and builds. You can resolve this by installing Homebrew
to either the standard prefix for your platform or to a non-standard prefix that
is not in the Homebrew temporary directory.
EOS
  fi
}

# NOTE: The members of the array in the second arg must not have spaces!
check-array-membership() {
  local item=$1
  shift

  if [[ " ${*} " == *" ${item} "* ]]
  then
    return 0
  else
    return 1
  fi
}

# These variables are set from various Homebrew scripts.
# shellcheck disable=SC2154
auto-update() {
  [[ -z "${HOMEBREW_HELP}" ]] || return
  [[ -z "${HOMEBREW_NO_AUTO_UPDATE}" ]] || return
  [[ -z "${HOMEBREW_AUTO_UPDATING}" ]] || return
  [[ -z "${HOMEBREW_UPDATE_AUTO}" ]] || return
  [[ -z "${HOMEBREW_AUTO_UPDATE_CHECKED}" ]] || return

  # If we've checked for updates, we don't need to check again.
  export HOMEBREW_AUTO_UPDATE_CHECKED="1"

  if [[ -n "${HOMEBREW_AUTO_UPDATE_COMMAND}" ]]
  then
    export HOMEBREW_AUTO_UPDATING="1"

    # Look for commands that may be referring to a formula/cask in a specific
    # 3rd-party tap so they can be auto-updated more often (as they do not get
    # their data from the API).
    AUTO_UPDATE_TAP_COMMANDS=(
      install
      outdated
      upgrade
    )
    if check-array-membership "${HOMEBREW_COMMAND}" "${AUTO_UPDATE_TAP_COMMANDS[@]}"
    then
      for arg in "$@"
      do
        if [[ "${arg}" == */*/* ]] && [[ "${arg}" != Homebrew/* ]] && [[ "${arg}" != homebrew/* ]]
        then

          HOMEBREW_AUTO_UPDATE_TAP="1"
          break
        fi
      done
    fi

    if [[ -z "${HOMEBREW_AUTO_UPDATE_SECS}" ]]
    then
      if [[ -n "${HOMEBREW_NO_INSTALL_FROM_API}" || -n "${HOMEBREW_AUTO_UPDATE_TAP}" ]]
      then
        # 5 minutes
        HOMEBREW_AUTO_UPDATE_SECS="300"
      elif [[ -n "${HOMEBREW_DEV_CMD_RUN}" ]]
      then
        # 1 hour
        HOMEBREW_AUTO_UPDATE_SECS="3600"
      else
        # 24 hours
        HOMEBREW_AUTO_UPDATE_SECS="86400"
      fi
    fi

    repo_fetch_heads=("${HOMEBREW_REPOSITORY}/.git/FETCH_HEAD")
    # We might have done an auto-update recently, but not a core/cask clone auto-update.
    # So we check the core/cask clone FETCH_HEAD too.
    if [[ -n "${HOMEBREW_AUTO_UPDATE_CORE_TAP}" && -d "${HOMEBREW_CORE_REPOSITORY}/.git" ]]
    then
      repo_fetch_heads+=("${HOMEBREW_CORE_REPOSITORY}/.git/FETCH_HEAD")
    fi
    if [[ -n "${HOMEBREW_AUTO_UPDATE_CASK_TAP}" && -d "${HOMEBREW_CASK_REPOSITORY}/.git" ]]
    then
      repo_fetch_heads+=("${HOMEBREW_CASK_REPOSITORY}/.git/FETCH_HEAD")
    fi

    # Skip auto-update if all of the selected repositories have been checked in the
    # last $HOMEBREW_AUTO_UPDATE_SECS.
    needs_auto_update=
    for repo_fetch_head in "${repo_fetch_heads[@]}"
    do
      if [[ ! -f "${repo_fetch_head}" ]] ||
         [[ -z "$(find "${repo_fetch_head}" -type f -newermt "-${HOMEBREW_AUTO_UPDATE_SECS} seconds" 2>/dev/null)" ]]
      then
        needs_auto_update=1
        break
      fi
    done
    if [[ -z "${needs_auto_update}" ]]
    then
      return
    fi

    brew update --auto-update

    unset HOMEBREW_AUTO_UPDATING
    unset HOMEBREW_AUTO_UPDATE_TAP

    # exec a new process to set any new environment variables.
    exec "${HOMEBREW_BREW_FILE}" "$@"
  fi

  unset AUTO_UPDATE_COMMANDS
  unset AUTO_UPDATE_CORE_TAP_COMMANDS
  unset AUTO_UPDATE_CASK_TAP_COMMANDS
  unset HOMEBREW_AUTO_UPDATE_CORE_TAP
  unset HOMEBREW_AUTO_UPDATE_CASK_TAP
}

#####
##### Setup output so e.g. odie looks as nice as possible.
#####

# Colorize output on GitHub Actions.
# This is set by the user environment.
# shellcheck disable=SC2154
if [[ -n "${GITHUB_ACTIONS}" ]]
then
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

#####
##### odie as quickly as possible.
#####

if [[ "${HOMEBREW_PREFIX}" == "/" || "${HOMEBREW_PREFIX}" == "/usr" ]]
then
  # it may work, but I only see pain this route and don't want to support it
  odie "Cowardly refusing to continue at this prefix: ${HOMEBREW_PREFIX}"
fi

#####
##### Now, do everything else (that may be a bit slower).
#####

# Docker image deprecation
if [[ -f "${HOMEBREW_REPOSITORY}/.docker-deprecate" ]]
then
  read -r DOCKER_DEPRECATION_MESSAGE <"${HOMEBREW_REPOSITORY}/.docker-deprecate"
  if [[ -n "${GITHUB_ACTIONS}" ]]
  then
    echo "::warning::${DOCKER_DEPRECATION_MESSAGE}" >&2
  else
    opoo "${DOCKER_DEPRECATION_MESSAGE}"
  fi
fi

# USER isn't always set so provide a fall back for `brew` and subprocesses.
export USER="${USER:-$(id -un)}"

# A depth of 1 means this command was directly invoked by a user.
# Higher depths mean this command was invoked by another Homebrew command.
export HOMEBREW_COMMAND_DEPTH="$((HOMEBREW_COMMAND_DEPTH + 1))"

setup_curl() {
  # This is set by the user environment.
  # shellcheck disable=SC2154
  HOMEBREW_BREWED_CURL_PATH="${HOMEBREW_PREFIX}/opt/curl/bin/curl"
  if [[ -n "${HOMEBREW_FORCE_BREWED_CURL}" && -x "${HOMEBREW_BREWED_CURL_PATH}" ]] &&
     "${HOMEBREW_BREWED_CURL_PATH}" --version &>/dev/null
  then
    HOMEBREW_CURL="${HOMEBREW_BREWED_CURL_PATH}"
  elif [[ -n "${HOMEBREW_CURL_PATH}" ]]
  then
    HOMEBREW_CURL="${HOMEBREW_CURL_PATH}"
  else
    HOMEBREW_CURL="curl"
  fi
}

setup_git() {
  # This is set by the user environment.
  # shellcheck disable=SC2154
  if [[ -n "${HOMEBREW_FORCE_BREWED_GIT}" && -x "${HOMEBREW_PREFIX}/opt/git/bin/git" ]] &&
     "${HOMEBREW_PREFIX}/opt/git/bin/git" --version &>/dev/null
  then
    HOMEBREW_GIT="${HOMEBREW_PREFIX}/opt/git/bin/git"
  elif [[ -n "${HOMEBREW_GIT_PATH}" ]]
  then
    HOMEBREW_GIT="${HOMEBREW_GIT_PATH}"
  else
    HOMEBREW_GIT="git"
  fi
}

setup_curl
setup_git

GIT_DESCRIBE_CACHE="${HOMEBREW_REPOSITORY}/.git/describe-cache"
GIT_REVISION=$("${HOMEBREW_GIT}" -C "${HOMEBREW_REPOSITORY}" rev-parse HEAD 2>/dev/null)

# safe fallback in case git rev-parse fails e.g. if this is not considered a safe git directory
if [[ -z "${GIT_REVISION}" ]]
then
  read -r GIT_HEAD 2>/dev/null <"${HOMEBREW_REPOSITORY}/.git/HEAD"
  if [[ "${GIT_HEAD}" == "ref: refs/heads/master" ]]
  then
    read -r GIT_REVISION 2>/dev/null <"${HOMEBREW_REPOSITORY}/.git/refs/heads/master"
  elif [[ "${GIT_HEAD}" == "ref: refs/heads/stable" ]]
  then
    read -r GIT_REVISION 2>/dev/null <"${HOMEBREW_REPOSITORY}/.git/refs/heads/stable"
  fi
  unset GIT_HEAD
fi

if [[ -n "${GIT_REVISION}" ]]
then
  GIT_DESCRIBE_CACHE_FILE="${GIT_DESCRIBE_CACHE}/${GIT_REVISION}"
  if [[ -r "${GIT_DESCRIBE_CACHE_FILE}" ]] && "${HOMEBREW_GIT}" -C "${HOMEBREW_REPOSITORY}" diff --quiet --no-ext-diff 2>/dev/null
  then
    read -r GIT_DESCRIBE_CACHE_HOMEBREW_VERSION <"${GIT_DESCRIBE_CACHE_FILE}"
    if [[ -n "${GIT_DESCRIBE_CACHE_HOMEBREW_VERSION}" && "${GIT_DESCRIBE_CACHE_HOMEBREW_VERSION}" != *"-dirty" ]]
    then
      HOMEBREW_VERSION="${GIT_DESCRIBE_CACHE_HOMEBREW_VERSION}"
    fi
    unset GIT_DESCRIBE_CACHE_HOMEBREW_VERSION
  fi

  if [[ -z "${HOMEBREW_VERSION}" ]]
  then
    HOMEBREW_VERSION="$("${HOMEBREW_GIT}" -C "${HOMEBREW_REPOSITORY}" describe --tags --dirty --abbrev=7 2>/dev/null)"
    # Don't output any permissions errors here. The user may not have write
    # permissions to the cache but we don't care because it's an optional
    # performance improvement.
    rm -rf "${GIT_DESCRIBE_CACHE}" 2>/dev/null
    mkdir -p "${GIT_DESCRIBE_CACHE}" 2>/dev/null
    echo "${HOMEBREW_VERSION}" | tee "${GIT_DESCRIBE_CACHE_FILE}" &>/dev/null
  fi
  unset GIT_DESCRIBE_CACHE_FILE
else
  # Don't care about permission errors here either.
  rm -rf "${GIT_DESCRIBE_CACHE}" 2>/dev/null
fi
unset GIT_REVISION
unset GIT_DESCRIBE_CACHE

HOMEBREW_USER_AGENT_VERSION="${HOMEBREW_VERSION}"
if [[ -z "${HOMEBREW_VERSION}" ]]
then
  HOMEBREW_VERSION=">=4.3.0 (shallow or no git repository)"
  HOMEBREW_USER_AGENT_VERSION="4.X.Y"
fi

HOMEBREW_CORE_REPOSITORY="${HOMEBREW_LIBRARY}/Taps/homebrew/homebrew-core"
# Used in --version.sh
# shellcheck disable=SC2034
HOMEBREW_CASK_REPOSITORY="${HOMEBREW_LIBRARY}/Taps/homebrew/homebrew-cask"

# Shift the -v to the end of the parameter list
if [[ "$1" == "-v" ]]
then
  shift
  set -- "$@" -v
fi

# commands that take a single or no arguments.
# doesn't need a default case as other arguments handled elsewhere.
# shellcheck disable=SC2249
case "$1" in
  --version | -v)
    source "${HOMEBREW_LIBRARY}/Homebrew/cmd/--version.sh"
    homebrew-version
    exit 0
    ;;
esac

# TODO: bump version when new macOS is released or announced and update references in:
# - docs/Installation.md
# - https://github.com/Homebrew/install/blob/HEAD/install.sh
# - Library/Homebrew/os/mac.rb (latest_sdk_version)
# and, if needed:
# - MacOSVersion::SYMBOLS
HOMEBREW_MACOS_NEWEST_UNSUPPORTED="16"
# TODO: bump version when new macOS is released and update references in:
# - docs/Installation.md
# - HOMEBREW_MACOS_OLDEST_SUPPORTED in .github/workflows/pkg-installer.yml
# - `os-version min` in package/Distribution.xml
# - https://github.com/Homebrew/install/blob/HEAD/install.sh
HOMEBREW_MACOS_OLDEST_SUPPORTED="13"
HOMEBREW_MACOS_OLDEST_ALLOWED="10.11"

if [[ -n "${HOMEBREW_MACOS}" ]]
then
  HOMEBREW_PRODUCT="Homebrew"
  HOMEBREW_SYSTEM="Macintosh"
  [[ "${HOMEBREW_PROCESSOR}" == "x86_64" ]] && HOMEBREW_PROCESSOR="Intel"
  # Don't change this from Mac OS X to match what macOS itself does in Safari on 10.12
  HOMEBREW_OS_USER_AGENT_VERSION="Mac OS X ${HOMEBREW_MACOS_VERSION}"

  if [[ "$(sysctl -n hw.optional.arm64 2>/dev/null)" == "1" ]]
  then
    # used in vendor-install.sh
    # shellcheck disable=SC2034
    HOMEBREW_PHYSICAL_PROCESSOR="arm64"
  fi

  IFS=. read -r -a MACOS_VERSION_ARRAY <<<"${HOMEBREW_MACOS_OLDEST_ALLOWED}"
  printf -v HOMEBREW_MACOS_OLDEST_ALLOWED_NUMERIC "%02d%02d%02d" "${MACOS_VERSION_ARRAY[@]}"

  unset MACOS_VERSION_ARRAY

  # Don't include minor versions for Big Sur and later.
  if [[ "${HOMEBREW_MACOS_VERSION_NUMERIC}" -gt "110000" ]]
  then
    HOMEBREW_OS_VERSION="macOS ${HOMEBREW_MACOS_VERSION%.*}"
  else
    HOMEBREW_OS_VERSION="macOS ${HOMEBREW_MACOS_VERSION}"
  fi

  # Refuse to run on pre-El Capitan
  if [[ "${HOMEBREW_MACOS_VERSION_NUMERIC}" -lt "${HOMEBREW_MACOS_OLDEST_ALLOWED_NUMERIC}" ]]
  then
    printf "ERROR: Your version of macOS (%s) is too old to run Homebrew!\\n" "${HOMEBREW_MACOS_VERSION}" >&2
    if [[ "${HOMEBREW_MACOS_VERSION_NUMERIC}" -lt "100700" ]]
    then
      printf "         For 10.4 - 10.6 support see: https://github.com/mistydemeo/tigerbrew\\n" >&2
    fi
    printf "\\n" >&2
  fi

  # Versions before Sierra don't handle custom cert files correctly, so need a full brewed curl.
  if [[ "${HOMEBREW_MACOS_VERSION_NUMERIC}" -lt "101200" ]]
  then
    HOMEBREW_SYSTEM_CURL_TOO_OLD="1"
    HOMEBREW_FORCE_BREWED_CURL="1"
  fi

  # The system libressl has a bug before macOS 10.15.6 where it incorrectly handles expired roots.
  if [[ -z "${HOMEBREW_SYSTEM_CURL_TOO_OLD}" && "${HOMEBREW_MACOS_VERSION_NUMERIC}" -lt "101506" ]]
  then
    HOMEBREW_SYSTEM_CA_CERTIFICATES_TOO_OLD="1"
    HOMEBREW_FORCE_BREWED_CA_CERTIFICATES="1"
  fi

  # TEMP: backwards compatiblity with existing 10.11-cross image
  # Can (probably) be removed in March 2024.
  if [[ -n "${HOMEBREW_FAKE_EL_CAPITAN}" ]]
  then
    export HOMEBREW_FAKE_MACOS="10.11.6"
  fi

  if [[ "${HOMEBREW_FAKE_MACOS}" =~ ^10\.11(\.|$) ]]
  then
    # We only need this to work enough to update brew and build the set portable formulae, so relax the requirement.
    HOMEBREW_MINIMUM_GIT_VERSION="2.7.4"
  else
    # The system Git on macOS versions before Sierra is too old for some Homebrew functionality we rely on.
    HOMEBREW_MINIMUM_GIT_VERSION="2.14.3"
    if [[ "${HOMEBREW_MACOS_VERSION_NUMERIC}" -lt "101200" ]]
    then
      HOMEBREW_FORCE_BREWED_GIT="1"
    fi
  fi
else
  HOMEBREW_PRODUCT="${HOMEBREW_SYSTEM}brew"
  # Don't try to follow /etc/os-release
  # shellcheck disable=SC1091,SC2154
  [[ -n "${HOMEBREW_LINUX}" ]] && HOMEBREW_OS_VERSION="$(source /etc/os-release && echo "${PRETTY_NAME}")"
  : "${HOMEBREW_OS_VERSION:=$(uname -r)}"
  HOMEBREW_OS_USER_AGENT_VERSION="${HOMEBREW_OS_VERSION}"

  # Ensure the system Curl is a version that supports modern HTTPS certificates.
  HOMEBREW_MINIMUM_CURL_VERSION="7.41.0"

  curl_version_output="$(${HOMEBREW_CURL} --version 2>/dev/null)"
  curl_name_and_version="${curl_version_output%% (*}"
  if [[ "$(numeric "${curl_name_and_version##* }")" -lt "$(numeric "${HOMEBREW_MINIMUM_CURL_VERSION}")" ]]
  then
    message="Please update your system curl or set HOMEBREW_CURL_PATH to a newer version.
Minimum required version: ${HOMEBREW_MINIMUM_CURL_VERSION}
Your curl version: ${curl_name_and_version##* }
Your curl executable: $(type -p "${HOMEBREW_CURL}")"

    if [[ -z ${HOMEBREW_CURL_PATH} ]]
    then
      HOMEBREW_SYSTEM_CURL_TOO_OLD=1
      HOMEBREW_FORCE_BREWED_CURL=1
      if [[ -z ${HOMEBREW_CURL_WARNING} ]]
      then
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
  IFS='.' read -r major minor micro build extra <<<"${git_version_output##* }"
  if [[ "$(numeric "${major}.${minor}.${micro}.${build}")" -lt "$(numeric "${HOMEBREW_MINIMUM_GIT_VERSION}")" ]]
  then
    message="Please update your system Git or set HOMEBREW_GIT_PATH to a newer version.
Minimum required version: ${HOMEBREW_MINIMUM_GIT_VERSION}
Your Git version: ${major}.${minor}.${micro}.${build}
Your Git executable: $(unset git && type -p "${HOMEBREW_GIT}")"
    if [[ -z ${HOMEBREW_GIT_PATH} ]]
    then
      HOMEBREW_FORCE_BREWED_GIT="1"
      if [[ -z ${HOMEBREW_GIT_WARNING} ]]
      then
        onoe "${message}"
        HOMEBREW_GIT_WARNING=1
      fi
    else
      odie "${message}"
    fi
  fi

  HOMEBREW_LINUX_MINIMUM_GLIBC_VERSION="2.13"

  HOMEBREW_CORE_REPOSITORY_ORIGIN="$("${HOMEBREW_GIT}" -C "${HOMEBREW_CORE_REPOSITORY}" remote get-url origin 2>/dev/null)"
  if [[ "${HOMEBREW_CORE_REPOSITORY_ORIGIN}" =~ (/linuxbrew|Linuxbrew/homebrew)-core(\.git)?$ ]]
  then
    # triggers migration code in update.sh
    # shellcheck disable=SC2034
    HOMEBREW_LINUXBREW_CORE_MIGRATION=1
  fi
fi

setup_ca_certificates() {
  if [[ -n "${HOMEBREW_FORCE_BREWED_CA_CERTIFICATES}" && -f "${HOMEBREW_PREFIX}/etc/ca-certificates/cert.pem" ]]
  then
    export SSL_CERT_FILE="${HOMEBREW_PREFIX}/etc/ca-certificates/cert.pem"
    export GIT_SSL_CAINFO="${HOMEBREW_PREFIX}/etc/ca-certificates/cert.pem"
    export GIT_SSL_CAPATH="${HOMEBREW_PREFIX}/etc/ca-certificates"
  fi
}
setup_ca_certificates

# Redetermine curl and git paths as we may have forced some options above.
setup_curl
setup_git

# A bug in the auto-update process prior to 3.1.2 means $HOMEBREW_BOTTLE_DOMAIN
# could be passed down with the default domain.
# This is problematic as this is will be the old bottle domain.
# This workaround is necessary for many CI images starting on old version,
# and will only be unnecessary when updating from <3.1.2 is not a concern.
# That will be when macOS 12 is the minimum required version.
# HOMEBREW_BOTTLE_DOMAIN is set from the user environment
# shellcheck disable=SC2154
if [[ -n "${HOMEBREW_BOTTLE_DEFAULT_DOMAIN}" ]] &&
   [[ "${HOMEBREW_BOTTLE_DOMAIN}" == "${HOMEBREW_BOTTLE_DEFAULT_DOMAIN}" ]]
then
  unset HOMEBREW_BOTTLE_DOMAIN
fi

HOMEBREW_API_DEFAULT_DOMAIN="https://formulae.brew.sh/api"
HOMEBREW_BOTTLE_DEFAULT_DOMAIN="https://ghcr.io/v2/homebrew/core"

HOMEBREW_USER_AGENT="${HOMEBREW_PRODUCT}/${HOMEBREW_USER_AGENT_VERSION} (${HOMEBREW_SYSTEM}; ${HOMEBREW_PROCESSOR} ${HOMEBREW_OS_USER_AGENT_VERSION})"
curl_version_output="$(curl --version 2>/dev/null)"
curl_name_and_version="${curl_version_output%% (*}"
HOMEBREW_USER_AGENT_CURL="${HOMEBREW_USER_AGENT} ${curl_name_and_version// //}"

# Timeout values to check for dead connections
# We don't use --max-time to support slow connections
HOMEBREW_CURL_SPEED_LIMIT=100
HOMEBREW_CURL_SPEED_TIME=5

export HOMEBREW_HELP_MESSAGE
export HOMEBREW_VERSION
export HOMEBREW_MACOS_ARM_DEFAULT_PREFIX
export HOMEBREW_LINUX_DEFAULT_PREFIX
export HOMEBREW_GENERIC_DEFAULT_PREFIX
export HOMEBREW_DEFAULT_PREFIX
export HOMEBREW_MACOS_ARM_DEFAULT_REPOSITORY
export HOMEBREW_LINUX_DEFAULT_REPOSITORY
export HOMEBREW_GENERIC_DEFAULT_REPOSITORY
export HOMEBREW_DEFAULT_REPOSITORY
export HOMEBREW_DEFAULT_CACHE
export HOMEBREW_CACHE
export HOMEBREW_DEFAULT_LOGS
export HOMEBREW_LOGS
export HOMEBREW_DEFAULT_TEMP
export HOMEBREW_TEMP
export HOMEBREW_CELLAR
export HOMEBREW_CASKROOM
export HOMEBREW_SYSTEM
export HOMEBREW_SYSTEM_CA_CERTIFICATES_TOO_OLD
export HOMEBREW_CURL
export HOMEBREW_BREWED_CURL_PATH
export HOMEBREW_CURL_WARNING
export HOMEBREW_SYSTEM_CURL_TOO_OLD
export HOMEBREW_GIT
export HOMEBREW_GIT_WARNING
export HOMEBREW_MINIMUM_GIT_VERSION
export HOMEBREW_LINUX_MINIMUM_GLIBC_VERSION
export HOMEBREW_PHYSICAL_PROCESSOR
export HOMEBREW_PROCESSOR
export HOMEBREW_PRODUCT
export HOMEBREW_OS_VERSION
export HOMEBREW_MACOS_VERSION
export HOMEBREW_MACOS_VERSION_NUMERIC
export HOMEBREW_MACOS_NEWEST_UNSUPPORTED
export HOMEBREW_MACOS_OLDEST_SUPPORTED
export HOMEBREW_MACOS_OLDEST_ALLOWED
export HOMEBREW_USER_AGENT
export HOMEBREW_USER_AGENT_CURL
export HOMEBREW_API_DEFAULT_DOMAIN
export HOMEBREW_BOTTLE_DEFAULT_DOMAIN
export HOMEBREW_CURL_SPEED_LIMIT
export HOMEBREW_CURL_SPEED_TIME

if [[ -n "${HOMEBREW_MACOS}" && -x "/usr/bin/xcode-select" ]]
then
  XCODE_SELECT_PATH="$('/usr/bin/xcode-select' --print-path 2>/dev/null)"
  if [[ "${XCODE_SELECT_PATH}" == "/" ]]
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
    # TODO: this is fairly slow, figure out if there's a faster way.
    XCRUN_OUTPUT="$(/usr/bin/xcrun clang 2>&1)"
    XCRUN_STATUS="$?"

    if [[ "${XCRUN_STATUS}" -ne 0 && "${XCRUN_OUTPUT}" == *license* ]]
    then
      odie <<EOS
You have not agreed to the Xcode license. Please resolve this by running:
  sudo xcodebuild -license accept
EOS
    fi
  fi
fi

for arg in "$@"
do
  [[ "${arg}" == "--" ]] && break

  if [[ "${arg}" == "--help" || "${arg}" == "-h" || "${arg}" == "--usage" || "${arg}" == "-?" ]]
  then
    export HOMEBREW_HELP="1"
    break
  fi
done

HOMEBREW_ARG_COUNT="$#"
HOMEBREW_COMMAND="$1"
shift
# If you are going to change anything in below case statement,
# be sure to also update HOMEBREW_INTERNAL_COMMAND_ALIASES hash in commands.rb
# doesn't need a default case as other arguments handled elsewhere.
# shellcheck disable=SC2249
case "${HOMEBREW_COMMAND}" in
  ls) HOMEBREW_COMMAND="list" ;;
  homepage) HOMEBREW_COMMAND="home" ;;
  -S) HOMEBREW_COMMAND="search" ;;
  up) HOMEBREW_COMMAND="update" ;;
  ln) HOMEBREW_COMMAND="link" ;;
  instal) HOMEBREW_COMMAND="install" ;; # gem does the same
  uninstal) HOMEBREW_COMMAND="uninstall" ;;
  post_install) HOMEBREW_COMMAND="postinstall" ;;
  rm) HOMEBREW_COMMAND="uninstall" ;;
  remove) HOMEBREW_COMMAND="uninstall" ;;
  abv) HOMEBREW_COMMAND="info" ;;
  dr) HOMEBREW_COMMAND="doctor" ;;
  --repo) HOMEBREW_COMMAND="--repository" ;;
  environment) HOMEBREW_COMMAND="--env" ;;
  --config) HOMEBREW_COMMAND="config" ;;
  -v) HOMEBREW_COMMAND="--version" ;;
  lc) HOMEBREW_COMMAND="livecheck" ;;
  tc) HOMEBREW_COMMAND="typecheck" ;;
esac

# Set HOMEBREW_DEV_CMD_RUN for users who have run a development command.
# This makes them behave like HOMEBREW_DEVELOPERs for brew update.
if [[ -z "${HOMEBREW_DEVELOPER}" ]]
then
  export HOMEBREW_GIT_CONFIG_FILE="${HOMEBREW_REPOSITORY}/.git/config"
  HOMEBREW_GIT_CONFIG_DEVELOPERMODE="$(git config --file="${HOMEBREW_GIT_CONFIG_FILE}" --get homebrew.devcmdrun 2>/dev/null)"
  if [[ "${HOMEBREW_GIT_CONFIG_DEVELOPERMODE}" == "true" ]]
  then
    export HOMEBREW_DEV_CMD_RUN="1"
  fi

  # Don't allow non-developers to customise Ruby warnings.
  unset HOMEBREW_RUBY_WARNINGS
fi

unset HOMEBREW_AUTO_UPDATE_COMMAND

# Check for commands that should call `brew update --auto-update` first.
AUTO_UPDATE_COMMANDS=(
  install
  outdated
  upgrade
  bundle
  release
)
if check-array-membership "${HOMEBREW_COMMAND}" "${AUTO_UPDATE_COMMANDS[@]}" ||
   [[ "${HOMEBREW_COMMAND}" == "tap" && "${HOMEBREW_ARG_COUNT}" -gt 1 ]]
then
  export HOMEBREW_AUTO_UPDATE_COMMAND="1"
fi

# Check for commands that should auto-update the homebrew-core tap.
AUTO_UPDATE_CORE_TAP_COMMANDS=(
  bump
  bump-formula-pr
)
if check-array-membership "${HOMEBREW_COMMAND}" "${AUTO_UPDATE_CORE_TAP_COMMANDS[@]}"
then
  export HOMEBREW_AUTO_UPDATE_COMMAND="1"
  export HOMEBREW_AUTO_UPDATE_CORE_TAP="1"
elif [[ -z "${HOMEBREW_AUTO_UPDATING}" ]]
then
  unset HOMEBREW_AUTO_UPDATE_CORE_TAP
fi

# Check for commands that should auto-update the homebrew-cask tap.
AUTO_UPDATE_CASK_TAP_COMMANDS=(
  bump
  bump-cask-pr
  bump-unversioned-casks
)
if check-array-membership "${HOMEBREW_COMMAND}" "${AUTO_UPDATE_CASK_TAP_COMMANDS[@]}"
then
  export HOMEBREW_AUTO_UPDATE_COMMAND="1"
  export HOMEBREW_AUTO_UPDATE_CASK_TAP="1"
elif [[ -z "${HOMEBREW_AUTO_UPDATING}" ]]
then
  unset HOMEBREW_AUTO_UPDATE_CASK_TAP
fi

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

export HOMEBREW_CORE_DEFAULT_GIT_REMOTE="https://github.com/Homebrew/homebrew-core"
if [[ -z "${HOMEBREW_CORE_GIT_REMOTE}" ]]
then
  HOMEBREW_CORE_GIT_REMOTE="${HOMEBREW_CORE_DEFAULT_GIT_REMOTE}"
fi
export HOMEBREW_CORE_GIT_REMOTE

# Set HOMEBREW_DEVELOPER_COMMAND if the command being run is a developer command
unset HOMEBREW_DEVELOPER_COMMAND
if [[ -f "${HOMEBREW_LIBRARY}/Homebrew/dev-cmd/${HOMEBREW_COMMAND}.sh" ]] ||
   [[ -f "${HOMEBREW_LIBRARY}/Homebrew/dev-cmd/${HOMEBREW_COMMAND}.rb" ]]
then
  export HOMEBREW_DEVELOPER_COMMAND="1"
fi

if [[ -n "${HOMEBREW_DEVELOPER_COMMAND}" && -z "${HOMEBREW_DEVELOPER}" ]]
then
  if [[ -z "${HOMEBREW_DEV_CMD_RUN}" ]]
  then
    opoo <<EOS
$(bold "${HOMEBREW_COMMAND}") is a developer command, so Homebrew's
developer mode has been automatically turned on.
To turn developer mode off, run:
  brew developer off

EOS
  fi

  git config --file="${HOMEBREW_GIT_CONFIG_FILE}" --replace-all homebrew.devcmdrun true 2>/dev/null
  export HOMEBREW_DEV_CMD_RUN="1"
fi

if [[ -n "${HOMEBREW_DEVELOPER}" || -n "${HOMEBREW_DEV_CMD_RUN}" ]]
then
  # Always run with Sorbet for Homebrew developers or when a Homebrew developer command has been run.
  export HOMEBREW_SORBET_RUNTIME="1"
fi

# Provide a (temporary, undocumented) way to disable Sorbet globally if needed
# to avoid reverting the above.
if [[ -n "${HOMEBREW_NO_SORBET_RUNTIME}" ]]
then
  unset HOMEBREW_SORBET_RUNTIME
fi

if [[ -f "${HOMEBREW_LIBRARY}/Homebrew/cmd/${HOMEBREW_COMMAND}.sh" ]]
then
  HOMEBREW_BASH_COMMAND="${HOMEBREW_LIBRARY}/Homebrew/cmd/${HOMEBREW_COMMAND}.sh"
elif [[ -f "${HOMEBREW_LIBRARY}/Homebrew/dev-cmd/${HOMEBREW_COMMAND}.sh" ]]
then
  HOMEBREW_BASH_COMMAND="${HOMEBREW_LIBRARY}/Homebrew/dev-cmd/${HOMEBREW_COMMAND}.sh"
fi

check-run-command-as-root

check-prefix-is-not-tmpdir

if [[ "${HOMEBREW_PREFIX}" == "/usr/local" ]] &&
   [[ "${HOMEBREW_PREFIX}" != "${HOMEBREW_REPOSITORY}" ]] &&
   [[ "${HOMEBREW_CELLAR}" == "${HOMEBREW_REPOSITORY}/Cellar" ]]
then
  cat >&2 <<EOS
Warning: your HOMEBREW_PREFIX is set to /usr/local but HOMEBREW_CELLAR is set
to ${HOMEBREW_CELLAR}. Your current HOMEBREW_CELLAR location will stop
you being able to use all the binary packages (bottles) Homebrew provides. We
recommend you move your HOMEBREW_CELLAR to /usr/local/Cellar which will get you
access to all bottles.
EOS
fi

source "${HOMEBREW_LIBRARY}/Homebrew/utils/analytics.sh"
setup-analytics

# Use this configuration file instead of ~/.ssh/config when fetching git over SSH.
if [[ -n "${HOMEBREW_SSH_CONFIG_PATH}" ]]
then
  export GIT_SSH_COMMAND="ssh -F${HOMEBREW_SSH_CONFIG_PATH}"
fi

if [[ -n "${HOMEBREW_DOCKER_REGISTRY_TOKEN}" ]]
then
  export HOMEBREW_GITHUB_PACKAGES_AUTH="Bearer ${HOMEBREW_DOCKER_REGISTRY_TOKEN}"
elif [[ -n "${HOMEBREW_DOCKER_REGISTRY_BASIC_AUTH_TOKEN}" ]]
then
  export HOMEBREW_GITHUB_PACKAGES_AUTH="Basic ${HOMEBREW_DOCKER_REGISTRY_BASIC_AUTH_TOKEN}"
else
  export HOMEBREW_GITHUB_PACKAGES_AUTH="Bearer QQ=="
fi

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

  {
    auto-update "$@"
    "homebrew-${HOMEBREW_COMMAND}" "$@"
    exit $?
  }

else
  source "${HOMEBREW_LIBRARY}/Homebrew/utils/ruby.sh"
  setup-ruby-path

  # Unshift command back into argument list (unless argument list was empty).
  [[ "${HOMEBREW_ARG_COUNT}" -gt 0 ]] && set -- "${HOMEBREW_COMMAND}" "$@"
  # HOMEBREW_RUBY_PATH set by utils/ruby.sh
  # shellcheck disable=SC2154
  {
    auto-update "$@"
    exec "${HOMEBREW_RUBY_PATH}" "${HOMEBREW_RUBY_WARNINGS}" "${HOMEBREW_RUBY_DISABLE_OPTIONS}" \
      "${HOMEBREW_LIBRARY}/Homebrew/brew.rb" "$@"
  }
fi
