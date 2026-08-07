#####
##### First do the essential, fast things to ensure commands like `brew --prefix` and others that we want
##### to be able to `source` in shell configurations run quickly.
#####

# HOMEBREW_LIBRARY is set by bin/brew
# shellcheck disable=SC2154
source "${HOMEBREW_LIBRARY}/Homebrew/utils/os.sh"

realpath() {
  (cd "$1" &>/dev/null && pwd -P)
}

# Support systems where HOMEBREW_PREFIX is the default,
# but a parent directory is a symlink.
# Example: Fedora Silverblue symlinks /home -> /var/home
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

# Support systems where HOMEBREW_CELLAR's parent directory is a symlink.
# Example: Fedora Silverblue symlinks /home -> /var/home
HOMEBREW_CELLAR_DEFAULT_PREFIX="${HOMEBREW_DEFAULT_PREFIX}/Cellar"
if [[ "${HOMEBREW_CELLAR}" != "${HOMEBREW_CELLAR_DEFAULT_PREFIX}" && "$(realpath "${HOMEBREW_CELLAR_DEFAULT_PREFIX}")" == "${HOMEBREW_CELLAR}" ]]
then
  HOMEBREW_CELLAR="${HOMEBREW_CELLAR_DEFAULT_PREFIX}"
fi

HOMEBREW_CASKROOM="${HOMEBREW_PREFIX}/Caskroom"

HOMEBREW_CACHE="${HOMEBREW_CACHE:-${HOMEBREW_DEFAULT_CACHE}}"
HOMEBREW_LOGS="${HOMEBREW_LOGS:-${HOMEBREW_DEFAULT_LOGS}}"
HOMEBREW_TEMP="${HOMEBREW_TEMP:-${HOMEBREW_DEFAULT_TEMP}}"
if [[ ! -w "${HOMEBREW_TEMP}" ]]
then
  HOMEBREW_TEMP="${HOMEBREW_DEFAULT_TEMP}"
fi

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
  --taps)
    source "${HOMEBREW_LIBRARY}/Homebrew/cmd/--taps.sh"
    homebrew---taps "$@" && exit 0
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

# Check `HOMEBREW_FORCE_BREW_WRAPPER` for all non-trivial commands
# (i.e. not defined above this line e.g. formulae or --cellar).
if [[ -n "${HOMEBREW_FORCE_BREW_WRAPPER:-}" ]]
then
  source "${HOMEBREW_LIBRARY}/Homebrew/utils/wrapper.sh"
  check-brew-wrapper "$1"
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

source "${HOMEBREW_LIBRARY}/Homebrew/utils.sh"

check-run-command-as-root() {
  [[ "${EUID}" == 0 || "${UID}" == 0 ]] || return

  # Allow Azure Pipelines/GitHub Actions/Docker/Podman/Concourse/Kubernetes to do everything as root (as it's normal there)
  [[ -f /.dockerenv ]] && return
  [[ -f /run/.containerenv ]] && return
  [[ -f /proc/1/cgroup ]] && grep -E "azpl_job|actions_job|docker|garden|kubepods" -q /proc/1/cgroup && return

  # `brew as-console-user` is run by root-owned MDM/Munki/Jamf workflows so it
  # can immediately dispatch the requested Homebrew command as the console user.
  [[ "${HOMEBREW_COMMAND}" == "as-console-user" ]] && return

  # `brew setup-sandbox` is intended to be run with `sudo` to prepare the
  # Homebrew sandbox.
  [[ "${HOMEBREW_COMMAND}" == "setup-sandbox" ]] && return

  # `brew services` may need `sudo` for system-wide daemons.
  if [[ "${HOMEBREW_COMMAND}" == "services" ]]
  then
    # Need to disable Bootsnap when running as root to avoid permission errors:
    # https://github.com/Homebrew/brew/issues/19904
    export HOMEBREW_NO_BOOTSNAP="1"

    return
  fi

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

source "${HOMEBREW_LIBRARY}/Homebrew/utils/auto-update.sh"

# Only `brew update-if-needed` should be handled here.
# We want it as fast as possible but it needs auto-update() defined above.
# HOMEBREW_LIBRARY set by bin/brew
# shellcheck disable=SC2154
# doesn't need a default case as other arguments handled elsewhere.
# shellcheck disable=SC2249
# Don't need to pass through any arguments.
# shellcheck disable=SC2119
case "$@" in
  update-if-needed)
    source "${HOMEBREW_LIBRARY}/Homebrew/cmd/update-if-needed.sh"
    homebrew-update-if-needed
    exit 0
    ;;
esac

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

setup-locale

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
if [[ -f "${HOMEBREW_REPOSITORY}/.docker-deprecate" && -z "${HOMEBREW_TESTS}" ]]
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

source "${HOMEBREW_LIBRARY}/Homebrew/utils/curl.sh"
source "${HOMEBREW_LIBRARY}/Homebrew/utils/git.sh"

setup_git
read-homebrew-git-config
set-homebrew-version-from-git

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
  mcp-server)
    source "${HOMEBREW_LIBRARY}/Homebrew/cmd/mcp-server.sh"
    homebrew-mcp-server "$@"
    exit 0
    ;;
esac

setup_curl

HOMEBREW_API_DEFAULT_DOMAIN="https://formulae.brew.sh/api"
HOMEBREW_BOTTLE_DEFAULT_DOMAIN="https://ghcr.io/v2/homebrew/core"

# TODO: bump version when new macOS is released or announced and update references in:
# - docs/Installation.md
# - https://github.com/Homebrew/install/blob/HEAD/install.sh
# - Library/Homebrew/os/mac.rb (latest_sdk_version)
# - Library/Homebrew/os/mac/xcode.rb (latest_version), (minimum_version)
# and, if needed:
# - MacOSVersion::SYMBOLS
HOMEBREW_MACOS_NEWEST_UNSUPPORTED="27"
# TODO: bump version when new macOS is released
HOMEBREW_MACOS_NEWEST_SUPPORTED="26"
# TODO: bump version when new macOS is released and update references in:
# - docs/Installation.md
# - HOMEBREW_MACOS_OLDEST_SUPPORTED in .github/workflows/release.yml
# - `os-version min` in package/Distribution.xml
# - https://github.com/Homebrew/install/blob/HEAD/install.sh
HOMEBREW_MACOS_OLDEST_SUPPORTED="14"
HOMEBREW_MACOS_OLDEST_ALLOWED="10.15"

setup-os-details
check-curl-version
check-git-version

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

setup-user-agents

export HOMEBREW_HELP_MESSAGE
export HOMEBREW_VERSION
export HOMEBREW_MACOS_ARM_DEFAULT_PREFIX
export HOMEBREW_LINUX_DEFAULT_PREFIX
export HOMEBREW_GENERIC_DEFAULT_PREFIX
export HOMEBREW_DEFAULT_PREFIX
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
export HOMEBREW_OS_VERSION
export HOMEBREW_MACOS_VERSION
export HOMEBREW_MACOS_VERSION_NUMERIC
export HOMEBREW_MACOS_NEWEST_UNSUPPORTED
export HOMEBREW_MACOS_NEWEST_SUPPORTED
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
    XCRUN_OUTPUT="$(/usr/bin/xcrun --find clang 2>&1)"
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
  x) HOMEBREW_COMMAND="exec" ;;
esac
# `update.sh` assumes normal repositories, so fail before it mutates a worktree.
if [[ "${HOMEBREW_COMMAND}" == "update" && -z "${HOMEBREW_HELP}" && -f "${HOMEBREW_REPOSITORY}/.git" ]]
then
  for arg in "$@"
  do
    [[ "${arg}" == "--auto-update" ]] && exit 0
  done
  odie "Cannot \`brew update\` in a Homebrew/brew Git worktree."
fi
if [[ ("${HOMEBREW_COMMAND}" == "audit" || "${HOMEBREW_COMMAND}" == "lgtm" ||
      "${HOMEBREW_COMMAND}" == "style" || "${HOMEBREW_COMMAND}" == "tests") &&
      "${HOMEBREW_CACHE}" != "${HOMEBREW_REPOSITORY}/tmp/cache" ]]
then
  if [[ -d "${HOMEBREW_CACHE}" && ! -w "${HOMEBREW_CACHE}" ]] ||
     [[ ! -d "${HOMEBREW_CACHE}" && ! -w "${HOMEBREW_CACHE%/*}" ]]
  then
    original_cache="${HOMEBREW_CACHE}"
    HOMEBREW_CACHE="${HOMEBREW_REPOSITORY}/tmp/cache"
    printf 'Warning: HOMEBREW_CACHE is not writable at %s; using %s for Homebrew cache files instead.\n' \
      "${original_cache}" "${HOMEBREW_CACHE}" >&2
    mkdir -p "${HOMEBREW_CACHE}/api"
    if [[ -d "${original_cache}/api" ]]
    then
      cp -R "${original_cache}/api/." "${HOMEBREW_CACHE}/api/" &>/dev/null || true
    fi
    export HOMEBREW_CACHE
  fi
fi

# Set HOMEBREW_DEV_CMD_RUN for users who have run a development command.
# This makes them behave like HOMEBREW_DEVELOPERs for brew update.
if [[ -z "${HOMEBREW_DEVELOPER}" ]]
then
  export HOMEBREW_GIT_CONFIG_FILE
  if [[ "${HOMEBREW_GIT_CONFIG_DEVCMDRUN}" == "true" ]]
  then
    export HOMEBREW_DEV_CMD_RUN="1"
  fi

  # Don't allow non-developers to customise Ruby warnings.
  unset HOMEBREW_RUBY_WARNINGS
fi

setup-auto-update

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

if [[ -n "${HOMEBREW_DEVELOPER_COMMAND}" && -z "${HOMEBREW_DEVELOPER}" && -z "${HOMEBREW_DEV_CMD_RUN}" ]]
then
  opoo <<EOS
$(bold "${HOMEBREW_COMMAND}") is a developer command, so Homebrew's
developer mode has been automatically turned on.
To turn developer mode off, run:
  brew developer off

EOS

  git config --file="${HOMEBREW_GIT_CONFIG_FILE}" --replace-all homebrew.devcmdrun true 2>/dev/null
  export HOMEBREW_DEV_CMD_RUN="1"
fi

# Enable features for developers and CI before they become the default for everyone.
if [[ -n "${HOMEBREW_DEVELOPER}" ]]
then
  :
fi

# Enable features for users who have run a devcmd before they become the default for everyone.
if [[ -n "${HOMEBREW_DEVELOPER}" || -n "${HOMEBREW_DEV_CMD_RUN}" ]]
then
  :
fi

# Keep in sync with `Homebrew::DevCmd::Tests#setup_environment!`.
if [[ -n "${HOMEBREW_TESTS_NO_SORBET_RUNTIME}" ]]
then
  unset HOMEBREW_SORBET_RUNTIME HOMEBREW_SORBET_RECURSIVE
# Only enable runtime typechecking for commands where correctness matters more
# than performance.
elif [[ "${HOMEBREW_COMMAND}" == "test" || "${HOMEBREW_COMMAND}" == "test-bot" ||
        "${HOMEBREW_COMMAND}" == "tests" ]]
then
  export HOMEBREW_SORBET_RUNTIME="1"
fi

if [[ -z "${HOMEBREW_FORCE_RUBY_COMMAND:-}" && -f "${HOMEBREW_LIBRARY}/Homebrew/cmd/${HOMEBREW_COMMAND}.sh" ]]
then
  HOMEBREW_BASH_COMMAND="${HOMEBREW_LIBRARY}/Homebrew/cmd/${HOMEBREW_COMMAND}.sh"
elif [[ -z "${HOMEBREW_FORCE_RUBY_COMMAND:-}" && -f "${HOMEBREW_LIBRARY}/Homebrew/dev-cmd/${HOMEBREW_COMMAND}.sh" ]]
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
  # If the token is to the special value "none", unset any existing auth to use anonymous access.
  if [[ "${HOMEBREW_DOCKER_REGISTRY_BASIC_AUTH_TOKEN}" == "none" ]]
  then
    unset HOMEBREW_GITHUB_PACKAGES_AUTH
  else
    export HOMEBREW_GITHUB_PACKAGES_AUTH="Basic ${HOMEBREW_DOCKER_REGISTRY_BASIC_AUTH_TOKEN}"
  fi
else
  export HOMEBREW_GITHUB_PACKAGES_AUTH="Bearer QQ=="
fi

# Avoid picking up any random `sudo` in `PATH`.
if [[ -x /usr/bin/sudo ]]
then
  SUDO=/usr/bin/sudo
else
  # Do this after ensuring we're using default Bash builtins.
  SUDO="$(command -v sudo 2>/dev/null)"
fi

# Reset sudo timestamp to avoid running unauthorized sudo commands
if [[ -n "${SUDO}" ]]
then
  "${SUDO}" --reset-timestamp 2>/dev/null || true
fi
unset SUDO

# Remove internal variables
unset HOMEBREW_INTERNAL_ALLOW_PACKAGES_FROM_PATHS

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
