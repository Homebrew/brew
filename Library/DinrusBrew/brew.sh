#####
##### First do the essential, fast things to ensure commands like `brew --prefix` and others that we want
##### to be able to `source` in shell configurations run quickly.
#####

case "${MACHTYPE}" in
  arm64-* | aarch64-*)
    DINRUSBREW_PROCESSOR="arm64"
    ;;
  x86_64-*)
    DINRUSBREW_PROCESSOR="x86_64"
    ;;
  *)
    DINRUSBREW_PROCESSOR="$(uname -m)"
    ;;
esac

case "${OSTYPE}" in
  darwin*)
    DINRUSBREW_SYSTEM="Darwin"
    DINRUSBREW_MACOS="1"
    ;;
  linux*)
    DINRUSBREW_SYSTEM="Linux"
    DINRUSBREW_LINUX="1"
    ;;
  *)
    DINRUSBREW_SYSTEM="$(uname -s)"
    ;;
esac
DINRUSBREW_PHYSICAL_PROCESSOR="${DINRUSBREW_PROCESSOR}"

DINRUSBREW_MACOS_ARM_DEFAULT_PREFIX="/opt/homebrew"
DINRUSBREW_MACOS_ARM_DEFAULT_REPOSITORY="${DINRUSBREW_MACOS_ARM_DEFAULT_PREFIX}"
DINRUSBREW_LINUX_DEFAULT_PREFIX="/home/linuxbrew/.linuxbrew"
DINRUSBREW_LINUX_DEFAULT_REPOSITORY="${DINRUSBREW_LINUX_DEFAULT_PREFIX}/DinrusBrew"
DINRUSBREW_GENERIC_DEFAULT_PREFIX="/usr/local"
DINRUSBREW_GENERIC_DEFAULT_REPOSITORY="${DINRUSBREW_GENERIC_DEFAULT_PREFIX}/DinrusBrew"
if [[ -n "${DINRUSBREW_MACOS}" && "${DINRUSBREW_PROCESSOR}" == "arm64" ]]
then
  DINRUSBREW_DEFAULT_PREFIX="${DINRUSBREW_MACOS_ARM_DEFAULT_PREFIX}"
  DINRUSBREW_DEFAULT_REPOSITORY="${DINRUSBREW_MACOS_ARM_DEFAULT_REPOSITORY}"
elif [[ -n "${DINRUSBREW_LINUX}" ]]
then
  DINRUSBREW_DEFAULT_PREFIX="${DINRUSBREW_LINUX_DEFAULT_PREFIX}"
  DINRUSBREW_DEFAULT_REPOSITORY="${DINRUSBREW_LINUX_DEFAULT_REPOSITORY}"
else
  DINRUSBREW_DEFAULT_PREFIX="${DINRUSBREW_GENERIC_DEFAULT_PREFIX}"
  DINRUSBREW_DEFAULT_REPOSITORY="${DINRUSBREW_GENERIC_DEFAULT_REPOSITORY}"
fi

if [[ -n "${DINRUSBREW_MACOS}" ]]
then
  DINRUSBREW_DEFAULT_CACHE="${HOME}/Library/Caches/DinrusBrew"
  DINRUSBREW_DEFAULT_LOGS="${HOME}/Library/Logs/DinrusBrew"
  DINRUSBREW_DEFAULT_TEMP="/private/tmp"

  DINRUSBREW_MACOS_VERSION="$(/usr/bin/sw_vers -productVersion)"

  IFS=. read -r -a MACOS_VERSION_ARRAY <<<"${DINRUSBREW_MACOS_VERSION}"
  printf -v DINRUSBREW_MACOS_VERSION_NUMERIC "%02d%02d%02d" "${MACOS_VERSION_ARRAY[@]}"

  unset MACOS_VERSION_ARRAY
else
  CACHE_HOME="${DINRUSBREW_XDG_CACHE_HOME:-${HOME}/.cache}"
  DINRUSBREW_DEFAULT_CACHE="${CACHE_HOME}/DinrusBrew"
  DINRUSBREW_DEFAULT_LOGS="${CACHE_HOME}/DinrusBrew/Logs"
  DINRUSBREW_DEFAULT_TEMP="/tmp"
fi

realpath() {
  (cd "$1" &>/dev/null && pwd -P)
}

# Support systems where DINRUSBREW_PREFIX is the default,
# but a parent directory is a symlink.
# Example: Fedora Silverblue symlinks /home -> var/home
if [[ "${DINRUSBREW_PREFIX}" != "${DINRUSBREW_DEFAULT_PREFIX}" && "$(realpath "${DINRUSBREW_DEFAULT_PREFIX}")" == "${DINRUSBREW_PREFIX}" ]]
then
  DINRUSBREW_PREFIX="${DINRUSBREW_DEFAULT_PREFIX}"
fi

# Support systems where DINRUSBREW_REPOSITORY is the default,
# but a parent directory is a symlink.
# Example: Fedora Silverblue symlinks /home -> var/home
if [[ "${DINRUSBREW_REPOSITORY}" != "${DINRUSBREW_DEFAULT_REPOSITORY}" && "$(realpath "${DINRUSBREW_DEFAULT_REPOSITORY}")" == "${DINRUSBREW_REPOSITORY}" ]]
then
  DINRUSBREW_REPOSITORY="${DINRUSBREW_DEFAULT_REPOSITORY}"
fi

# Where we store built products; a Cellar in DINRUSBREW_PREFIX (often /usr/local
# for bottles) unless there's already a Cellar in DINRUSBREW_REPOSITORY.
# These variables are set by bin/brew
# shellcheck disable=SC2154
if [[ -d "${DINRUSBREW_REPOSITORY}/Cellar" ]]
then
  DINRUSBREW_CELLAR="${DINRUSBREW_REPOSITORY}/Cellar"
else
  DINRUSBREW_CELLAR="${DINRUSBREW_PREFIX}/Cellar"
fi

DINRUSBREW_CASKROOM="${DINRUSBREW_PREFIX}/Caskroom"

DINRUSBREW_CACHE="${DINRUSBREW_CACHE:-${DINRUSBREW_DEFAULT_CACHE}}"
DINRUSBREW_LOGS="${DINRUSBREW_LOGS:-${DINRUSBREW_DEFAULT_LOGS}}"
DINRUSBREW_TEMP="${DINRUSBREW_TEMP:-${DINRUSBREW_DEFAULT_TEMP}}"

# commands that take a single or no arguments.
# DINRUSBREW_LIBRARY set by bin/brew
# shellcheck disable=SC2154
# doesn't need a default case as other arguments handled elsewhere.
# shellcheck disable=SC2249
case "$1" in
  formulae)
    source "${DINRUSBREW_LIBRARY}/DinrusBrew/cmd/formulae.sh"
    homebrew-formulae
    exit 0
    ;;
  casks)
    source "${DINRUSBREW_LIBRARY}/DinrusBrew/cmd/casks.sh"
    homebrew-casks
    exit 0
    ;;
  shellenv)
    source "${DINRUSBREW_LIBRARY}/DinrusBrew/cmd/shellenv.sh"
    shift
    homebrew-shellenv "$1"
    exit 0
    ;;
esac

source "${DINRUSBREW_LIBRARY}/DinrusBrew/help.sh"

# functions that take multiple arguments or handle multiple commands.
# doesn't need a default case as other arguments handled elsewhere.
# shellcheck disable=SC2249
case "$@" in
  --cellar)
    echo "${DINRUSBREW_CELLAR}"
    exit 0
    ;;
  --repository | --repo)
    echo "${DINRUSBREW_REPOSITORY}"
    exit 0
    ;;
  --caskroom)
    echo "${DINRUSBREW_CASKROOM}"
    exit 0
    ;;
  --cache)
    echo "${DINRUSBREW_CACHE}"
    exit 0
    ;;
  # falls back to cmd/--prefix.rb and cmd/--cellar.rb on a non-zero return
  --prefix* | --cellar*)
    source "${DINRUSBREW_LIBRARY}/DinrusBrew/formula_path.sh"
    homebrew-formula-path "$@" && exit 0
    ;;
  # falls back to cmd/command.rb on a non-zero return
  command*)
    source "${DINRUSBREW_LIBRARY}/DinrusBrew/command_path.sh"
    homebrew-command-path "$@" && exit 0
    ;;
  # falls back to cmd/list.rb on a non-zero return
  list* | ls*)
    source "${DINRUSBREW_LIBRARY}/DinrusBrew/list.sh"
    homebrew-list "$@" && exit 0
    ;;
  # homebrew-tap only handles invocations with no arguments
  tap)
    source "${DINRUSBREW_LIBRARY}/DinrusBrew/tap.sh"
    homebrew-tap "$@"
    exit 0
    ;;
  # falls back to cmd/help.rb on a non-zero return
  help | --help | -h | --usage | "-?" | "")
    homebrew-help "$@" && exit 0
    ;;
esac

# Include some helper functions.
source "${DINRUSBREW_LIBRARY}/DinrusBrew/utils/helpers.sh"

# Require DINRUSBREW_BREW_WRAPPER to be set if DINRUSBREW_FORCE_BREW_WRAPPER is set
# (and DINRUSBREW_NO_FORCE_BREW_WRAPPER is not set) for all non-trivial commands
# (i.e. not defined above this line e.g. formulae or --cellar).
if [[ -z "${DINRUSBREW_NO_FORCE_BREW_WRAPPER:-}" && -n "${DINRUSBREW_FORCE_BREW_WRAPPER:-}" ]]
then
  if [[ -z "${DINRUSBREW_BREW_WRAPPER:-}" ]]
  then
    odie <<EOS
DINRUSBREW_FORCE_BREW_WRAPPER установлен в
  ${DINRUSBREW_FORCE_BREW_WRAPPER},
но DINRUSBREW_BREW_WRAPPER не установлен. Это говорит о том, что выполняется
  ${DINRUSBREW_BREW_FILE}
непосредственно, но следовало бы выполняться
  ${DINRUSBREW_FORCE_BREW_WRAPPER}
EOS
  elif [[ "${DINRUSBREW_FORCE_BREW_WRAPPER}" != "${DINRUSBREW_BREW_WRAPPER}" ]]
  then
    odie <<EOS
DINRUSBREW_FORCE_BREW_WRAPPER установлен в
  ${DINRUSBREW_FORCE_BREW_WRAPPER}
but DINRUSBREW_BREW_WRAPPER установлен в
  ${DINRUSBREW_BREW_WRAPPER}
Это говорит о том, что выполняется
  ${DINRUSBREW_BREW_FILE}
непосредственно, но следовало бы выполняться:
  ${DINRUSBREW_FORCE_BREW_WRAPPER}
EOS
  fi
fi

# commands that take a single or no arguments and need to write to DINRUSBREW_PREFIX.
# DINRUSBREW_LIBRARY set by bin/brew
# shellcheck disable=SC2154
# doesn't need a default case as other arguments handled elsewhere.
# shellcheck disable=SC2249
case "$1" in
  setup-ruby)
    source "${DINRUSBREW_LIBRARY}/DinrusBrew/cmd/setup-ruby.sh"
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

  # DinrusBrew Services may need `sudo` for system-wide daemons.
  [[ "${DINRUSBREW_COMMAND}" == "services" ]] && return

  # It's fine to run this as root as it's not changing anything.
  [[ "${DINRUSBREW_COMMAND}" == "--prefix" ]] && return

  odie <<EOS
Running DinrusBrew as root is extremely dangerous and no longer supported.
As DinrusBrew does not drop privileges on installation you would be giving all
build scripts full access to your system.
EOS
}

check-prefix-is-not-tmpdir() {
  [[ -z "${DINRUSBREW_MACOS}" ]] && return

  if [[ "${DINRUSBREW_PREFIX}" == "${DINRUSBREW_TEMP}"* ]]
  then
    odie <<EOS
Your DINRUSBREW_PREFIX is in the DinrusBrew temporary directory, which DinrusBrew
uses to store downloads and builds. You can resolve this by installing DinrusBrew
to either the standard prefix for your platform or to a non-standard prefix that
is not in the DinrusBrew temporary directory.
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

# These variables are set from various DinrusBrew scripts.
# shellcheck disable=SC2154
auto-update() {
  [[ -z "${DINRUSBREW_HELP}" ]] || return
  [[ -z "${DINRUSBREW_NO_AUTO_UPDATE}" ]] || return
  [[ -z "${DINRUSBREW_AUTO_UPDATING}" ]] || return
  [[ -z "${DINRUSBREW_UPDATE_AUTO}" ]] || return
  [[ -z "${DINRUSBREW_AUTO_UPDATE_CHECKED}" ]] || return

  # If we've checked for updates, we don't need to check again.
  export DINRUSBREW_AUTO_UPDATE_CHECKED="1"

  if [[ -n "${DINRUSBREW_AUTO_UPDATE_COMMAND}" ]]
  then
    export DINRUSBREW_AUTO_UPDATING="1"

    # Look for commands that may be referring to a formula/cask in a specific
    # 3rd-party tap so they can be auto-updated more often (as they do not get
    # their data from the API).
    AUTO_UPDATE_TAP_COMMANDS=(
      install
      outdated
      upgrade
    )
    if check-array-membership "${DINRUSBREW_COMMAND}" "${AUTO_UPDATE_TAP_COMMANDS[@]}"
    then
      for arg in "$@"
      do
        if [[ "${arg}" == */*/* ]] && [[ "${arg}" != DinrusBrew/* ]] && [[ "${arg}" != homebrew/* ]]
        then

          DINRUSBREW_AUTO_UPDATE_TAP="1"
          break
        fi
      done
    fi

    if [[ -z "${DINRUSBREW_AUTO_UPDATE_SECS}" ]]
    then
      if [[ -n "${DINRUSBREW_NO_INSTALL_FROM_API}" || -n "${DINRUSBREW_AUTO_UPDATE_TAP}" ]]
      then
        # 5 minutes
        DINRUSBREW_AUTO_UPDATE_SECS="300"
      elif [[ -n "${DINRUSBREW_DEV_CMD_RUN}" ]]
      then
        # 1 hour
        DINRUSBREW_AUTO_UPDATE_SECS="3600"
      else
        # 24 hours
        DINRUSBREW_AUTO_UPDATE_SECS="86400"
      fi
    fi

    repo_fetch_heads=("${DINRUSBREW_REPOSITORY}/.git/FETCH_HEAD")
    # We might have done an auto-update recently, but not a core/cask clone auto-update.
    # So we check the core/cask clone FETCH_HEAD too.
    if [[ -n "${DINRUSBREW_AUTO_UPDATE_CORE_TAP}" && -d "${DINRUSBREW_CORE_REPOSITORY}/.git" ]]
    then
      repo_fetch_heads+=("${DINRUSBREW_CORE_REPOSITORY}/.git/FETCH_HEAD")
    fi
    if [[ -n "${DINRUSBREW_AUTO_UPDATE_CASK_TAP}" && -d "${DINRUSBREW_CASK_REPOSITORY}/.git" ]]
    then
      repo_fetch_heads+=("${DINRUSBREW_CASK_REPOSITORY}/.git/FETCH_HEAD")
    fi

    # Skip auto-update if all of the selected repositories have been checked in the
    # last $DINRUSBREW_AUTO_UPDATE_SECS.
    needs_auto_update=
    for repo_fetch_head in "${repo_fetch_heads[@]}"
    do
      if [[ ! -f "${repo_fetch_head}" ]] ||
         [[ -z "$(find "${repo_fetch_head}" -type f -newermt "-${DINRUSBREW_AUTO_UPDATE_SECS} seconds" 2>/dev/null)" ]]
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

    unset DINRUSBREW_AUTO_UPDATING
    unset DINRUSBREW_AUTO_UPDATE_TAP

    # exec a new process to set any new environment variables.
    exec "${DINRUSBREW_BREW_FILE}" "$@"
  fi

  unset AUTO_UPDATE_COMMANDS
  unset AUTO_UPDATE_CORE_TAP_COMMANDS
  unset AUTO_UPDATE_CASK_TAP_COMMANDS
  unset DINRUSBREW_AUTO_UPDATE_CORE_TAP
  unset DINRUSBREW_AUTO_UPDATE_CASK_TAP
}

#####
##### Setup output so e.g. odie looks as nice as possible.
#####

# Colorize output on GitHub Actions.
# This is set by the user environment.
# shellcheck disable=SC2154
if [[ -n "${GITHUB_ACTIONS}" ]]
then
  export DINRUSBREW_COLOR="1"
fi

# Force UTF-8 to avoid encoding issues for users with broken locale settings.
if [[ -n "${DINRUSBREW_MACOS}" ]]
then
  if [[ "$(locale charmap)" != "UTF-8" ]]
  then
    export LC_ALL="ru_RU.UTF-8"
  fi
else
  if ! command -v locale >/dev/null
  then
    export LC_ALL=C
  elif [[ "$(locale charmap)" != "UTF-8" ]]
  then
    locales="$(locale -a)"
    c_utf_regex='\bC\.(utf8|UTF-8)\b'
    en_us_regex='\bru_RU\.(utf8|UTF-8)\b'
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

if [[ "${DINRUSBREW_PREFIX}" == "/" || "${DINRUSBREW_PREFIX}" == "/usr" ]]
then
  # it may work, but I only see pain this route and don't want to support it
  odie "Cowardly refusing to continue at this prefix: ${DINRUSBREW_PREFIX}"
fi

#####
##### Now, do everything else (that may be a bit slower).
#####

# Docker image deprecation
if [[ -f "${DINRUSBREW_REPOSITORY}/.docker-deprecate" ]]
then
  read -r DOCKER_DEPRECATION_MESSAGE <"${DINRUSBREW_REPOSITORY}/.docker-deprecate"
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
# Higher depths mean this command was invoked by another DinrusBrew command.
export DINRUSBREW_COMMAND_DEPTH="$((DINRUSBREW_COMMAND_DEPTH + 1))"

setup_curl() {
  # This is set by the user environment.
  # shellcheck disable=SC2154
  DINRUSBREW_BREWED_CURL_PATH="${DINRUSBREW_PREFIX}/opt/curl/bin/curl"
  if [[ -n "${DINRUSBREW_FORCE_BREWED_CURL}" && -x "${DINRUSBREW_BREWED_CURL_PATH}" ]] &&
     "${DINRUSBREW_BREWED_CURL_PATH}" --version &>/dev/null
  then
    DINRUSBREW_CURL="${DINRUSBREW_BREWED_CURL_PATH}"
  elif [[ -n "${DINRUSBREW_CURL_PATH}" ]]
  then
    DINRUSBREW_CURL="${DINRUSBREW_CURL_PATH}"
  else
    DINRUSBREW_CURL="curl"
  fi
}

setup_git() {
  # This is set by the user environment.
  # shellcheck disable=SC2154
  if [[ -n "${DINRUSBREW_FORCE_BREWED_GIT}" && -x "${DINRUSBREW_PREFIX}/opt/git/bin/git" ]] &&
     "${DINRUSBREW_PREFIX}/opt/git/bin/git" --version &>/dev/null
  then
    DINRUSBREW_GIT="${DINRUSBREW_PREFIX}/opt/git/bin/git"
  elif [[ -n "${DINRUSBREW_GIT_PATH}" ]]
  then
    DINRUSBREW_GIT="${DINRUSBREW_GIT_PATH}"
  else
    DINRUSBREW_GIT="git"
  fi
}

setup_curl
setup_git

GIT_DESCRIBE_CACHE="${DINRUSBREW_REPOSITORY}/.git/describe-cache"
GIT_REVISION=$("${DINRUSBREW_GIT}" -C "${DINRUSBREW_REPOSITORY}" rev-parse HEAD 2>/dev/null)

# safe fallback in case git rev-parse fails e.g. if this is not considered a safe git directory
if [[ -z "${GIT_REVISION}" ]]
then
  read -r GIT_HEAD 2>/dev/null <"${DINRUSBREW_REPOSITORY}/.git/HEAD"
  if [[ "${GIT_HEAD}" == "ref: refs/heads/master" ]]
  then
    read -r GIT_REVISION 2>/dev/null <"${DINRUSBREW_REPOSITORY}/.git/refs/heads/master"
  elif [[ "${GIT_HEAD}" == "ref: refs/heads/stable" ]]
  then
    read -r GIT_REVISION 2>/dev/null <"${DINRUSBREW_REPOSITORY}/.git/refs/heads/stable"
  fi
  unset GIT_HEAD
fi

if [[ -n "${GIT_REVISION}" ]]
then
  GIT_DESCRIBE_CACHE_FILE="${GIT_DESCRIBE_CACHE}/${GIT_REVISION}"
  if [[ -r "${GIT_DESCRIBE_CACHE_FILE}" ]] && "${DINRUSBREW_GIT}" -C "${DINRUSBREW_REPOSITORY}" diff --quiet --no-ext-diff 2>/dev/null
  then
    read -r GIT_DESCRIBE_CACHE_DINRUSBREW_VERSION <"${GIT_DESCRIBE_CACHE_FILE}"
    if [[ -n "${GIT_DESCRIBE_CACHE_DINRUSBREW_VERSION}" && "${GIT_DESCRIBE_CACHE_DINRUSBREW_VERSION}" != *"-dirty" ]]
    then
      DINRUSBREW_VERSION="${GIT_DESCRIBE_CACHE_DINRUSBREW_VERSION}"
    fi
    unset GIT_DESCRIBE_CACHE_DINRUSBREW_VERSION
  fi

  if [[ -z "${DINRUSBREW_VERSION}" ]]
  then
    DINRUSBREW_VERSION="$("${DINRUSBREW_GIT}" -C "${DINRUSBREW_REPOSITORY}" describe --tags --dirty --abbrev=7 2>/dev/null)"
    # Don't output any permissions errors here. The user may not have write
    # permissions to the cache but we don't care because it's an optional
    # performance improvement.
    rm -rf "${GIT_DESCRIBE_CACHE}" 2>/dev/null
    mkdir -p "${GIT_DESCRIBE_CACHE}" 2>/dev/null
    echo "${DINRUSBREW_VERSION}" | tee "${GIT_DESCRIBE_CACHE_FILE}" &>/dev/null
  fi
  unset GIT_DESCRIBE_CACHE_FILE
else
  # Don't care about permission errors here either.
  rm -rf "${GIT_DESCRIBE_CACHE}" 2>/dev/null
fi
unset GIT_REVISION
unset GIT_DESCRIBE_CACHE

DINRUSBREW_USER_AGENT_VERSION="${DINRUSBREW_VERSION}"
if [[ -z "${DINRUSBREW_VERSION}" ]]
then
  DINRUSBREW_VERSION=">=4.3.0 (shallow or no git repository)"
  DINRUSBREW_USER_AGENT_VERSION="4.X.Y"
fi

DINRUSBREW_CORE_REPOSITORY="${DINRUSBREW_LIBRARY}/Taps/homebrew/homebrew-core"
# Used in --version.sh
# shellcheck disable=SC2034
DINRUSBREW_CASK_REPOSITORY="${DINRUSBREW_LIBRARY}/Taps/homebrew/homebrew-cask"

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
    source "${DINRUSBREW_LIBRARY}/DinrusBrew/cmd/--version.sh"
    homebrew-version
    exit 0
    ;;
esac

# TODO: bump version when new macOS is released or announced and update references in:
# - docs/Installation.md
# - https://github.com/DinrusBrew/install/blob/HEAD/install.sh
# - Library/DinrusBrew/os/mac.rb (latest_sdk_version)
# and, if needed:
# - MacOSVersion::SYMBOLS
DINRUSBREW_MACOS_NEWEST_UNSUPPORTED="16"
# TODO: bump version when new macOS is released and update references in:
# - docs/Installation.md
# - DINRUSBREW_MACOS_OLDEST_SUPPORTED in .github/workflows/pkg-installer.yml
# - `os-version min` in package/Distribution.xml
# - https://github.com/DinrusBrew/install/blob/HEAD/install.sh
DINRUSBREW_MACOS_OLDEST_SUPPORTED="13"
DINRUSBREW_MACOS_OLDEST_ALLOWED="10.11"

if [[ -n "${DINRUSBREW_MACOS}" ]]
then
  DINRUSBREW_PRODUCT="DinrusBrew"
  DINRUSBREW_SYSTEM="Macintosh"
  [[ "${DINRUSBREW_PROCESSOR}" == "x86_64" ]] && DINRUSBREW_PROCESSOR="Intel"
  # Don't change this from Mac OS X to match what macOS itself does in Safari on 10.12
  DINRUSBREW_OS_USER_AGENT_VERSION="Mac OS X ${DINRUSBREW_MACOS_VERSION}"

  if [[ "$(sysctl -n hw.optional.arm64 2>/dev/null)" == "1" ]]
  then
    # used in vendor-install.sh
    # shellcheck disable=SC2034
    DINRUSBREW_PHYSICAL_PROCESSOR="arm64"
  fi

  IFS=. read -r -a MACOS_VERSION_ARRAY <<<"${DINRUSBREW_MACOS_OLDEST_ALLOWED}"
  printf -v DINRUSBREW_MACOS_OLDEST_ALLOWED_NUMERIC "%02d%02d%02d" "${MACOS_VERSION_ARRAY[@]}"

  unset MACOS_VERSION_ARRAY

  # Don't include minor versions for Big Sur and later.
  if [[ "${DINRUSBREW_MACOS_VERSION_NUMERIC}" -gt "110000" ]]
  then
    DINRUSBREW_OS_VERSION="macOS ${DINRUSBREW_MACOS_VERSION%.*}"
  else
    DINRUSBREW_OS_VERSION="macOS ${DINRUSBREW_MACOS_VERSION}"
  fi

  # Refuse to run on pre-El Capitan
  if [[ "${DINRUSBREW_MACOS_VERSION_NUMERIC}" -lt "${DINRUSBREW_MACOS_OLDEST_ALLOWED_NUMERIC}" ]]
  then
    printf "ERROR: Your version of macOS (%s) is too old to run DinrusBrew!\\n" "${DINRUSBREW_MACOS_VERSION}" >&2
    if [[ "${DINRUSBREW_MACOS_VERSION_NUMERIC}" -lt "100700" ]]
    then
      printf "         For 10.4 - 10.6 support see: https://github.com/mistydemeo/tigerbrew\\n" >&2
    fi
    printf "\\n" >&2
  fi

  # Versions before Sierra don't handle custom cert files correctly, so need a full brewed curl.
  if [[ "${DINRUSBREW_MACOS_VERSION_NUMERIC}" -lt "101200" ]]
  then
    DINRUSBREW_SYSTEM_CURL_TOO_OLD="1"
    DINRUSBREW_FORCE_BREWED_CURL="1"
  fi

  # The system libressl has a bug before macOS 10.15.6 where it incorrectly handles expired roots.
  if [[ -z "${DINRUSBREW_SYSTEM_CURL_TOO_OLD}" && "${DINRUSBREW_MACOS_VERSION_NUMERIC}" -lt "101506" ]]
  then
    DINRUSBREW_SYSTEM_CA_CERTIFICATES_TOO_OLD="1"
    DINRUSBREW_FORCE_BREWED_CA_CERTIFICATES="1"
  fi

  # TEMP: backwards compatiblity with existing 10.11-cross image
  # Can (probably) be removed in March 2024.
  if [[ -n "${DINRUSBREW_FAKE_EL_CAPITAN}" ]]
  then
    export DINRUSBREW_FAKE_MACOS="10.11.6"
  fi

  if [[ "${DINRUSBREW_FAKE_MACOS}" =~ ^10\.11(\.|$) ]]
  then
    # We only need this to work enough to update brew and build the set portable formulae, so relax the requirement.
    DINRUSBREW_MINIMUM_GIT_VERSION="2.7.4"
  else
    # The system Git on macOS versions before Sierra is too old for some DinrusBrew functionality we rely on.
    DINRUSBREW_MINIMUM_GIT_VERSION="2.14.3"
    if [[ "${DINRUSBREW_MACOS_VERSION_NUMERIC}" -lt "101200" ]]
    then
      DINRUSBREW_FORCE_BREWED_GIT="1"
    fi
  fi
else
  DINRUSBREW_PRODUCT="${DINRUSBREW_SYSTEM}brew"
  # Don't try to follow /etc/os-release
  # shellcheck disable=SC1091,SC2154
  [[ -n "${DINRUSBREW_LINUX}" ]] && DINRUSBREW_OS_VERSION="$(source /etc/os-release && echo "${PRETTY_NAME}")"
  : "${DINRUSBREW_OS_VERSION:=$(uname -r)}"
  DINRUSBREW_OS_USER_AGENT_VERSION="${DINRUSBREW_OS_VERSION}"

  # Ensure the system Curl is a version that supports modern HTTPS certificates.
  DINRUSBREW_MINIMUM_CURL_VERSION="7.41.0"

  curl_version_output="$(${DINRUSBREW_CURL} --version 2>/dev/null)"
  curl_name_and_version="${curl_version_output%% (*}"
  if [[ "$(numeric "${curl_name_and_version##* }")" -lt "$(numeric "${DINRUSBREW_MINIMUM_CURL_VERSION}")" ]]
  then
    message="Please update your system curl or set DINRUSBREW_CURL_PATH to a newer version.
Minimum required version: ${DINRUSBREW_MINIMUM_CURL_VERSION}
Your curl version: ${curl_name_and_version##* }
Your curl executable: $(type -p "${DINRUSBREW_CURL}")"

    if [[ -z ${DINRUSBREW_CURL_PATH} ]]
    then
      DINRUSBREW_SYSTEM_CURL_TOO_OLD=1
      DINRUSBREW_FORCE_BREWED_CURL=1
      if [[ -z ${DINRUSBREW_CURL_WARNING} ]]
      then
        onoe "${message}"
        DINRUSBREW_CURL_WARNING=1
      fi
    else
      odie "${message}"
    fi
  fi

  # Ensure the system Git is at or newer than the minimum required version.
  # Git 2.7.4 is the version of git on Ubuntu 16.04 LTS (Xenial Xerus).
  DINRUSBREW_MINIMUM_GIT_VERSION="2.7.0"
  git_version_output="$(${DINRUSBREW_GIT} --version 2>/dev/null)"
  # $extra is intentionally discarded.
  # shellcheck disable=SC2034
  DINRUSBREW_FORCE_BREWED_GIT="1"

  DINRUSBREW_LINUX_MINIMUM_GLIBC_VERSION="2.13"

  DINRUSBREW_CORE_REPOSITORY_ORIGIN="$("${DINRUSBREW_GIT}" -C "${DINRUSBREW_CORE_REPOSITORY}" remote get-url origin 2>/dev/null)"
  if [[ "${DINRUSBREW_CORE_REPOSITORY_ORIGIN}" =~ (/linuxbrew|Linuxbrew/homebrew)-core(\.git)?$ ]]
  then
    # triggers migration code in update.sh
    # shellcheck disable=SC2034
    DINRUSBREW_LINUXBREW_CORE_MIGRATION=1
  fi
fi

setup_ca_certificates() {
  if [[ -n "${DINRUSBREW_FORCE_BREWED_CA_CERTIFICATES}" && -f "${DINRUSBREW_PREFIX}/etc/ca-certificates/cert.pem" ]]
  then
    export SSL_CERT_FILE="${DINRUSBREW_PREFIX}/etc/ca-certificates/cert.pem"
    export GIT_SSL_CAINFO="${DINRUSBREW_PREFIX}/etc/ca-certificates/cert.pem"
    export GIT_SSL_CAPATH="${DINRUSBREW_PREFIX}/etc/ca-certificates"
  fi
}
setup_ca_certificates

# Redetermine curl and git paths as we may have forced some options above.
setup_curl
setup_git

# A bug in the auto-update process prior to 3.1.2 means $DINRUSBREW_BOTTLE_DOMAIN
# could be passed down with the default domain.
# This is problematic as this is will be the old bottle domain.
# This workaround is necessary for many CI images starting on old version,
# and will only be unnecessary when updating from <3.1.2 is not a concern.
# That will be when macOS 12 is the minimum required version.
# DINRUSBREW_BOTTLE_DOMAIN is set from the user environment
# shellcheck disable=SC2154
if [[ -n "${DINRUSBREW_BOTTLE_DEFAULT_DOMAIN}" ]] &&
   [[ "${DINRUSBREW_BOTTLE_DOMAIN}" == "${DINRUSBREW_BOTTLE_DEFAULT_DOMAIN}" ]]
then
  unset DINRUSBREW_BOTTLE_DOMAIN
fi

DINRUSBREW_API_DEFAULT_DOMAIN="https://formulae.brew.sh/api"
DINRUSBREW_BOTTLE_DEFAULT_DOMAIN="https://ghcr.io/v2/homebrew/core"

DINRUSBREW_USER_AGENT="${DINRUSBREW_PRODUCT}/${DINRUSBREW_USER_AGENT_VERSION} (${DINRUSBREW_SYSTEM}; ${DINRUSBREW_PROCESSOR} ${DINRUSBREW_OS_USER_AGENT_VERSION})"
curl_version_output="$(curl --version 2>/dev/null)"
curl_name_and_version="${curl_version_output%% (*}"
DINRUSBREW_USER_AGENT_CURL="${DINRUSBREW_USER_AGENT} ${curl_name_and_version// //}"

# Timeout values to check for dead connections
# We don't use --max-time to support slow connections
DINRUSBREW_CURL_SPEED_LIMIT=100
DINRUSBREW_CURL_SPEED_TIME=5

export DINRUSBREW_HELP_MESSAGE
export DINRUSBREW_VERSION
export DINRUSBREW_MACOS_ARM_DEFAULT_PREFIX
export DINRUSBREW_LINUX_DEFAULT_PREFIX
export DINRUSBREW_GENERIC_DEFAULT_PREFIX
export DINRUSBREW_DEFAULT_PREFIX
export DINRUSBREW_MACOS_ARM_DEFAULT_REPOSITORY
export DINRUSBREW_LINUX_DEFAULT_REPOSITORY
export DINRUSBREW_GENERIC_DEFAULT_REPOSITORY
export DINRUSBREW_DEFAULT_REPOSITORY
export DINRUSBREW_DEFAULT_CACHE
export DINRUSBREW_CACHE
export DINRUSBREW_DEFAULT_LOGS
export DINRUSBREW_LOGS
export DINRUSBREW_DEFAULT_TEMP
export DINRUSBREW_TEMP
export DINRUSBREW_CELLAR
export DINRUSBREW_CASKROOM
export DINRUSBREW_SYSTEM
export DINRUSBREW_SYSTEM_CA_CERTIFICATES_TOO_OLD
export DINRUSBREW_CURL
export DINRUSBREW_BREWED_CURL_PATH
export DINRUSBREW_CURL_WARNING
export DINRUSBREW_SYSTEM_CURL_TOO_OLD
export DINRUSBREW_GIT
export DINRUSBREW_GIT_WARNING
export DINRUSBREW_MINIMUM_GIT_VERSION
export DINRUSBREW_LINUX_MINIMUM_GLIBC_VERSION
export DINRUSBREW_PHYSICAL_PROCESSOR
export DINRUSBREW_PROCESSOR
export DINRUSBREW_PRODUCT
export DINRUSBREW_OS_VERSION
export DINRUSBREW_MACOS_VERSION
export DINRUSBREW_MACOS_VERSION_NUMERIC
export DINRUSBREW_MACOS_NEWEST_UNSUPPORTED
export DINRUSBREW_MACOS_OLDEST_SUPPORTED
export DINRUSBREW_MACOS_OLDEST_ALLOWED
export DINRUSBREW_USER_AGENT
export DINRUSBREW_USER_AGENT_CURL
export DINRUSBREW_API_DEFAULT_DOMAIN
export DINRUSBREW_BOTTLE_DEFAULT_DOMAIN
export DINRUSBREW_CURL_SPEED_LIMIT
export DINRUSBREW_CURL_SPEED_TIME

if [[ -n "${DINRUSBREW_MACOS}" && -x "/usr/bin/xcode-select" ]]
then
  XCODE_SELECT_PATH="$('/usr/bin/xcode-select' --print-path 2>/dev/null)"
  if [[ "${XCODE_SELECT_PATH}" == "/" ]]
  then
    odie <<EOS
Your xcode-select path is currently set to '/'.
This causes the 'xcrun' tool to hang, and can render DinrusBrew unusable.
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
    export DINRUSBREW_HELP="1"
    break
  fi
done

DINRUSBREW_ARG_COUNT="$#"
DINRUSBREW_COMMAND="$1"
shift
# If you are going to change anything in below case statement,
# be sure to also update DINRUSBREW_INTERNAL_COMMAND_ALIASES hash in commands.rb
# doesn't need a default case as other arguments handled elsewhere.
# shellcheck disable=SC2249
case "${DINRUSBREW_COMMAND}" in
  ls) DINRUSBREW_COMMAND="list" ;;
  homepage) DINRUSBREW_COMMAND="home" ;;
  -S) DINRUSBREW_COMMAND="search" ;;
  up) DINRUSBREW_COMMAND="update" ;;
  ln) DINRUSBREW_COMMAND="link" ;;
  instal) DINRUSBREW_COMMAND="install" ;; # gem does the same
  uninstal) DINRUSBREW_COMMAND="uninstall" ;;
  post_install) DINRUSBREW_COMMAND="postinstall" ;;
  rm) DINRUSBREW_COMMAND="uninstall" ;;
  remove) DINRUSBREW_COMMAND="uninstall" ;;
  abv) DINRUSBREW_COMMAND="info" ;;
  dr) DINRUSBREW_COMMAND="doctor" ;;
  --repo) DINRUSBREW_COMMAND="--repository" ;;
  environment) DINRUSBREW_COMMAND="--env" ;;
  --config) DINRUSBREW_COMMAND="config" ;;
  -v) DINRUSBREW_COMMAND="--version" ;;
  lc) DINRUSBREW_COMMAND="livecheck" ;;
  tc) DINRUSBREW_COMMAND="typecheck" ;;
esac

# Set DINRUSBREW_DEV_CMD_RUN for users who have run a development command.
# This makes them behave like DINRUSBREW_DEVELOPERs for brew update.
if [[ -z "${DINRUSBREW_DEVELOPER}" ]]
then
  export DINRUSBREW_GIT_CONFIG_FILE="${DINRUSBREW_REPOSITORY}/.git/config"
  DINRUSBREW_GIT_CONFIG_DEVELOPERMODE="$(git config --file="${DINRUSBREW_GIT_CONFIG_FILE}" --get homebrew.devcmdrun 2>/dev/null)"
  if [[ "${DINRUSBREW_GIT_CONFIG_DEVELOPERMODE}" == "true" ]]
  then
    export DINRUSBREW_DEV_CMD_RUN="1"
  fi

  # Don't allow non-developers to customise Ruby warnings.
  unset DINRUSBREW_RUBY_WARNINGS
fi

unset DINRUSBREW_AUTO_UPDATE_COMMAND

# Check for commands that should call `brew update --auto-update` first.
AUTO_UPDATE_COMMANDS=(
  install
  outdated
  upgrade
  bundle
  release
)
if check-array-membership "${DINRUSBREW_COMMAND}" "${AUTO_UPDATE_COMMANDS[@]}" ||
   [[ "${DINRUSBREW_COMMAND}" == "tap" && "${DINRUSBREW_ARG_COUNT}" -gt 1 ]]
then
  export DINRUSBREW_AUTO_UPDATE_COMMAND="1"
fi

# Check for commands that should auto-update the homebrew-core tap.
AUTO_UPDATE_CORE_TAP_COMMANDS=(
  bump
  bump-formula-pr
)
if check-array-membership "${DINRUSBREW_COMMAND}" "${AUTO_UPDATE_CORE_TAP_COMMANDS[@]}"
then
  export DINRUSBREW_AUTO_UPDATE_COMMAND="1"
  export DINRUSBREW_AUTO_UPDATE_CORE_TAP="1"
elif [[ -z "${DINRUSBREW_AUTO_UPDATING}" ]]
then
  unset DINRUSBREW_AUTO_UPDATE_CORE_TAP
fi

# Check for commands that should auto-update the homebrew-cask tap.
AUTO_UPDATE_CASK_TAP_COMMANDS=(
  bump
  bump-cask-pr
  bump-unversioned-casks
)
if check-array-membership "${DINRUSBREW_COMMAND}" "${AUTO_UPDATE_CASK_TAP_COMMANDS[@]}"
then
  export DINRUSBREW_AUTO_UPDATE_COMMAND="1"
  export DINRUSBREW_AUTO_UPDATE_CASK_TAP="1"
elif [[ -z "${DINRUSBREW_AUTO_UPDATING}" ]]
then
  unset DINRUSBREW_AUTO_UPDATE_CASK_TAP
fi

if [[ -z "${DINRUSBREW_RUBY_WARNINGS}" ]]
then
  export DINRUSBREW_RUBY_WARNINGS="-W1"
fi

export DINRUSBREW_BREW_DEFAULT_GIT_REMOTE="https://github.com/DinrusBrew/brew"
if [[ -z "${DINRUSBREW_BREW_GIT_REMOTE}" ]]
then
  DINRUSBREW_BREW_GIT_REMOTE="${DINRUSBREW_BREW_DEFAULT_GIT_REMOTE}"
fi
export DINRUSBREW_BREW_GIT_REMOTE

export DINRUSBREW_CORE_DEFAULT_GIT_REMOTE="https://github.com/DinrusBrew/homebrew-core"
if [[ -z "${DINRUSBREW_CORE_GIT_REMOTE}" ]]
then
  DINRUSBREW_CORE_GIT_REMOTE="${DINRUSBREW_CORE_DEFAULT_GIT_REMOTE}"
fi
export DINRUSBREW_CORE_GIT_REMOTE

# Set DINRUSBREW_DEVELOPER_COMMAND if the command being run is a developer command
unset DINRUSBREW_DEVELOPER_COMMAND
if [[ -f "${DINRUSBREW_LIBRARY}/DinrusBrew/dev-cmd/${DINRUSBREW_COMMAND}.sh" ]] ||
   [[ -f "${DINRUSBREW_LIBRARY}/DinrusBrew/dev-cmd/${DINRUSBREW_COMMAND}.rb" ]]
then
  export DINRUSBREW_DEVELOPER_COMMAND="1"
fi

# Provide a (temporary, undocumented) way to disable Sorbet globally if needed
# to avoid reverting the above.
if [[ -n "${DINRUSBREW_NO_SORBET_RUNTIME}" ]]
then
  unset DINRUSBREW_SORBET_RUNTIME
fi

if [[ -n "${DINRUSBREW_DEVELOPER_COMMAND}" && -z "${DINRUSBREW_DEVELOPER}" ]]
then
  if [[ -z "${DINRUSBREW_DEV_CMD_RUN}" ]]
  then
    opoo <<EOS
$(bold "${DINRUSBREW_COMMAND}") is a developer command, so DinrusBrew's
developer mode has been automatically turned on.
To turn developer mode off, run:
  brew developer off

EOS
  fi

  git config --file="${DINRUSBREW_GIT_CONFIG_FILE}" --replace-all homebrew.devcmdrun true 2>/dev/null
  export DINRUSBREW_DEV_CMD_RUN="1"
fi

if [[ -n "${DINRUSBREW_DEVELOPER}" || -n "${DINRUSBREW_DEV_CMD_RUN}" ]]
then
  # Always run with Sorbet for DinrusBrew developers or when a DinrusBrew developer command has been run.
  export DINRUSBREW_SORBET_RUNTIME="1"
fi

if [[ -f "${DINRUSBREW_LIBRARY}/DinrusBrew/cmd/${DINRUSBREW_COMMAND}.sh" ]]
then
  DINRUSBREW_BASH_COMMAND="${DINRUSBREW_LIBRARY}/DinrusBrew/cmd/${DINRUSBREW_COMMAND}.sh"
elif [[ -f "${DINRUSBREW_LIBRARY}/DinrusBrew/dev-cmd/${DINRUSBREW_COMMAND}.sh" ]]
then
  DINRUSBREW_BASH_COMMAND="${DINRUSBREW_LIBRARY}/DinrusBrew/dev-cmd/${DINRUSBREW_COMMAND}.sh"
fi

check-run-command-as-root

check-prefix-is-not-tmpdir

if [[ "${DINRUSBREW_PREFIX}" == "/usr/local" ]] &&
   [[ "${DINRUSBREW_PREFIX}" != "${DINRUSBREW_REPOSITORY}" ]] &&
   [[ "${DINRUSBREW_CELLAR}" == "${DINRUSBREW_REPOSITORY}/Cellar" ]]
then
  cat >&2 <<EOS
Warning: your DINRUSBREW_PREFIX is set to /usr/local but DINRUSBREW_CELLAR is set
to ${DINRUSBREW_CELLAR}. Your current DINRUSBREW_CELLAR location will stop
you being able to use all the binary packages (bottles) DinrusBrew provides. We
recommend you move your DINRUSBREW_CELLAR to /usr/local/Cellar which will get you
access to all bottles.
EOS
fi

source "${DINRUSBREW_LIBRARY}/DinrusBrew/utils/analytics.sh"
setup-analytics

# Use this configuration file instead of ~/.ssh/config when fetching git over SSH.
if [[ -n "${DINRUSBREW_SSH_CONFIG_PATH}" ]]
then
  export GIT_SSH_COMMAND="ssh -F${DINRUSBREW_SSH_CONFIG_PATH}"
fi

if [[ -n "${DINRUSBREW_DOCKER_REGISTRY_TOKEN}" ]]
then
  export DINRUSBREW_GITHUB_PACKAGES_AUTH="Bearer ${DINRUSBREW_DOCKER_REGISTRY_TOKEN}"
elif [[ -n "${DINRUSBREW_DOCKER_REGISTRY_BASIC_AUTH_TOKEN}" ]]
then
  export DINRUSBREW_GITHUB_PACKAGES_AUTH="Basic ${DINRUSBREW_DOCKER_REGISTRY_BASIC_AUTH_TOKEN}"
else
  export DINRUSBREW_GITHUB_PACKAGES_AUTH="Bearer QQ=="
fi

if [[ -n "${DINRUSBREW_BASH_COMMAND}" ]]
then
  # source rather than executing directly to ensure the entire file is read into
  # memory before it is run. This makes running a Bash script behave more like
  # a Ruby script and avoids hard-to-debug issues if the Bash script is updated
  # at the same time as being run.
  #
  # Shellcheck can't follow this dynamic `source`.
  # shellcheck disable=SC1090
  source "${DINRUSBREW_BASH_COMMAND}"

  {
    auto-update "$@"
    "homebrew-${DINRUSBREW_COMMAND}" "$@"
    exit $?
  }

else
  source "${DINRUSBREW_LIBRARY}/DinrusBrew/utils/ruby.sh"
  setup-ruby-path

  # Unshift command back into argument list (unless argument list was empty).
  [[ "${DINRUSBREW_ARG_COUNT}" -gt 0 ]] && set -- "${DINRUSBREW_COMMAND}" "$@"
  # DINRUSBREW_RUBY_PATH set by utils/ruby.sh
  # shellcheck disable=SC2154
  {
    auto-update "$@"
    exec "${DINRUSBREW_RUBY_PATH}" "${DINRUSBREW_RUBY_WARNINGS}" "${DINRUSBREW_RUBY_DISABLE_OPTIONS}" \
      "${DINRUSBREW_LIBRARY}/DinrusBrew/brew.rb" "$@"
  }
fi
