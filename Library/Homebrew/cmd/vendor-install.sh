# Documentation defined in Library/Homebrew/cmd/vendor-install.rb

# HOMEBREW_ARTIFACT_DOMAIN, HOMEBREW_ARTIFACT_DOMAIN_NO_FALLBACK, HOMEBREW_BOTTLE_DOMAIN, HOMEBREW_CACHE,
# HOMEBREW_CURLRC, HOMEBREW_DEVELOPER, HOMEBREW_DEBUG, HOMEBREW_VERBOSE are from the user environment
# HOMEBREW_PORTABLE_RUBY_VERSION is set by utils/ruby.sh
# HOMEBREW_LIBRARY, HOMEBREW_PREFIX are set by bin/brew
# HOMEBREW_CURL, HOMEBREW_GITHUB_PACKAGES_AUTH, HOMEBREW_LINUX, HOMEBREW_LINUX_MINIMUM_GLIBC_VERSION, HOMEBREW_MACOS,
# HOMEBREW_PHYSICAL_PROCESSOR, HOMEBREW_PROCESSOR, HOMEBREW_USER_AGENT_CURL are set by brew.sh
# shellcheck disable=SC2154
source "${HOMEBREW_LIBRARY}/Homebrew/utils/lock.sh"
source "${HOMEBREW_LIBRARY}/Homebrew/utils/ruby.sh"

VENDOR_DIR="${HOMEBREW_LIBRARY}/Homebrew/vendor"

# Built from https://github.com/Homebrew/homebrew-portable-ruby.
set_ruby_variables() {
  # Handle the case where /usr/local/bin/brew is run under arm64.
  # It's a x86_64 installation there (we refuse to install arm64 binaries) so
  # use a x86_64 Portable Ruby.
  if [[ -n "${HOMEBREW_MACOS}" && "${VENDOR_PHYSICAL_PROCESSOR}" == "arm64" && "${HOMEBREW_PREFIX}" == "/usr/local" ]]
  then
    ruby_PROCESSOR="x86_64"
    ruby_OS="darwin"
  else
    ruby_PROCESSOR="${VENDOR_PHYSICAL_PROCESSOR}"
    if [[ -n "${HOMEBREW_MACOS}" ]]
    then
      ruby_OS="darwin"
    elif [[ -n "${HOMEBREW_LINUX}" ]]
    then
      ruby_OS="linux"
    fi
  fi

  ruby_PLATFORMINFO="${HOMEBREW_LIBRARY}/Homebrew/vendor/portable-ruby-${ruby_PROCESSOR}-${ruby_OS}"
  if [[ -f "${ruby_PLATFORMINFO}" && -r "${ruby_PLATFORMINFO}" ]]
  then
    # ruby_TAG and ruby_SHA will be set via the sourced file if it exists
    # shellcheck disable=SC1090
    source "${ruby_PLATFORMINFO}"
  fi

  # Dynamic variables can't be detected by shellcheck
  # shellcheck disable=SC2034
  if [[ -n "${ruby_TAG}" && -n "${ruby_SHA}" ]]
  then
    ruby_FILENAME="portable-ruby-${HOMEBREW_PORTABLE_RUBY_VERSION}.${ruby_TAG}.bottle.tar.gz"
    ruby_URLs=()
    if [[ -n "${HOMEBREW_ARTIFACT_DOMAIN}" ]]
    then
      ruby_URLs+=("${HOMEBREW_ARTIFACT_DOMAIN}/v2/homebrew/portable-ruby/portable-ruby/blobs/sha256:${ruby_SHA}")
      if [[ -n "${HOMEBREW_ARTIFACT_DOMAIN_NO_FALLBACK}" ]]
      then
        ruby_URL="${ruby_URLs[0]}"
        return
      fi
    fi
    if [[ -n "${HOMEBREW_BOTTLE_DOMAIN}" ]]
    then
      ruby_URLs+=("${HOMEBREW_BOTTLE_DOMAIN}/bottles-portable-ruby/${ruby_FILENAME}")
    fi
    ruby_URLs+=(
      "https://ghcr.io/v2/homebrew/portable-ruby/portable-ruby/blobs/sha256:${ruby_SHA}"
      "https://github.com/Homebrew/homebrew-portable-ruby/releases/download/${HOMEBREW_PORTABLE_RUBY_VERSION}/${ruby_FILENAME}"
    )
    ruby_URL="${ruby_URLs[0]}"
  fi
}

check_linux_glibc_version() {
  if [[ -z "${HOMEBREW_LINUX}" || -z "${HOMEBREW_LINUX_MINIMUM_GLIBC_VERSION}" ]]
  then
    return 0
  fi

  local glibc_version
  local glibc_version_major
  local glibc_version_minor

  local minimum_required_major="${HOMEBREW_LINUX_MINIMUM_GLIBC_VERSION%.*}"
  local minimum_required_minor="${HOMEBREW_LINUX_MINIMUM_GLIBC_VERSION#*.}"

  if [[ "$(/usr/bin/ldd --version)" =~ \ [0-9]\.[0-9]+ ]]
  then
    glibc_version="${BASH_REMATCH[0]// /}"
    glibc_version_major="${glibc_version%.*}"
    glibc_version_minor="${glibc_version#*.}"
    if ((glibc_version_major < minimum_required_major || glibc_version_minor < minimum_required_minor))
    then
      odie "Vendored tools require system Glibc ${HOMEBREW_LINUX_MINIMUM_GLIBC_VERSION} or later (yours is ${glibc_version})."
    fi
  else
    odie "Failed to detect system Glibc version."
  fi
}

fetch() {
  local -a curl_args
  local url
  local sha
  local first_try=1
  local vendor_locations
  local temporary_path

  curl_args=()

  # do not load .curlrc unless requested (must be the first argument)
  # HOMEBREW_CURLRC isn't misspelt here
  # shellcheck disable=SC2153
  if [[ -z "${HOMEBREW_CURLRC}" ]]
  then
    curl_args[${#curl_args[*]}]="-q"
  elif [[ "${HOMEBREW_CURLRC}" == /* ]]
  then
    curl_args+=("-q" "--config" "${HOMEBREW_CURLRC}")
  fi

  # Authorization is needed for GitHub Packages but harmless on GitHub Releases
  curl_args+=(
    --fail
    --remote-time
    --location
    --user-agent "${HOMEBREW_USER_AGENT_CURL}"
    --header "Authorization: ${HOMEBREW_GITHUB_PACKAGES_AUTH}"
  )

  if [[ -n "${HOMEBREW_QUIET}" ]]
  then
    curl_args[${#curl_args[*]}]="--silent"
  elif [[ -z "${HOMEBREW_VERBOSE}" ]]
  then
    curl_args[${#curl_args[*]}]="--progress-bar"
  fi

  temporary_path="${CACHED_LOCATION}.incomplete"

  mkdir -p "${HOMEBREW_CACHE}"
  [[ -n "${HOMEBREW_QUIET}" ]] || ohai "Downloading ${VENDOR_URL}" >&2
  if [[ -f "${CACHED_LOCATION}" ]]
  then
    [[ -n "${HOMEBREW_QUIET}" ]] || echo "Already downloaded: ${CACHED_LOCATION}" >&2
  else
    for url in "${VENDOR_URLs[@]}"
    do
      [[ -n "${HOMEBREW_QUIET}" || -n "${first_try}" ]] || ohai "Downloading ${url}" >&2
      first_try=''
      if [[ -f "${temporary_path}" ]]
      then
        # HOMEBREW_CURL is set by brew.sh (and isn't misspelt here)
        # shellcheck disable=SC2153
        "${HOMEBREW_CURL}" "${curl_args[@]}" -C - "${url}" -o "${temporary_path}"
        if [[ $? -eq 33 ]]
        then
          [[ -n "${HOMEBREW_QUIET}" ]] || echo "Trying a full download" >&2
          rm -f "${temporary_path}"
          "${HOMEBREW_CURL}" "${curl_args[@]}" "${url}" -o "${temporary_path}"
        fi
      else
        "${HOMEBREW_CURL}" "${curl_args[@]}" "${url}" -o "${temporary_path}"
      fi

      [[ -f "${temporary_path}" ]] && break
    done

    if [[ ! -f "${temporary_path}" ]]
    then
      vendor_locations="$(printf "  - %s\n" "${VENDOR_URLs[@]}")"
      odie <<EOS
Failed to download ${VENDOR_NAME} from the following locations:
${vendor_locations}

Do not file an issue on GitHub about this; you will need to figure out for
yourself what issue with your internet connection restricts your access to
GitHub (used for Homebrew updates and binary packages).
EOS
    fi

    trap '' SIGINT
    mv "${temporary_path}" "${CACHED_LOCATION}"
    trap - SIGINT
  fi

  if [[ -x "/usr/bin/shasum" ]]
  then
    sha="$(/usr/bin/shasum -a 256 "${CACHED_LOCATION}" | cut -d' ' -f1)"
  fi

  if [[ -z "${sha}" && -x "$(type -P sha256sum)" ]]
  then
    sha="$(sha256sum "${CACHED_LOCATION}" | cut -d' ' -f1)"
  fi

  if [[ -z "${sha}" ]]
  then
    if [[ -x "$(type -P ruby)" ]]
    then
      sha="$(
        ruby <<EOSCRIPT
require 'digest/sha2'
digest = Digest::SHA256.new
File.open('${CACHED_LOCATION}', 'rb') { |f| digest.update(f.read) }
puts digest.hexdigest
EOSCRIPT
      )"
    else
      odie "Cannot verify checksum ('shasum', 'sha256sum' and 'ruby' not found)!"
    fi
  fi

  if [[ -z "${sha}" ]]
  then
    odie "Could not get checksum ('shasum', 'sha256sum' and 'ruby' produced no output)!"
  fi

  if [[ "${sha}" != "${VENDOR_SHA}" ]]
  then
    odie <<EOS
Checksum mismatch.
Expected: ${VENDOR_SHA}
  Actual: ${sha}
 Archive: ${CACHED_LOCATION}
To retry an incomplete download, remove the file above.
EOS
  fi
}

install() {
  local tar_args

  if [[ -n "${HOMEBREW_VERBOSE}" ]]
  then
    tar_args="xvzf"
  else
    tar_args="xzf"
  fi

  mkdir -p "${VENDOR_DIR}/portable-${VENDOR_NAME}"
  safe_cd "${VENDOR_DIR}/portable-${VENDOR_NAME}"

  trap '' SIGINT

  if [[ -d "${VENDOR_VERSION}" ]]
  then
    mv "${VENDOR_VERSION}" "${VENDOR_VERSION}.reinstall"
  fi

  safe_cd "${VENDOR_DIR}"
  [[ -n "${HOMEBREW_QUIET}" ]] || ohai "Pouring ${VENDOR_FILENAME}" >&2
  tar "${tar_args}" "${CACHED_LOCATION}"

  if [[ "${VENDOR_PROCESSOR}" != "${HOMEBREW_PROCESSOR}" ]] ||
     [[ "${VENDOR_PHYSICAL_PROCESSOR}" != "${HOMEBREW_PHYSICAL_PROCESSOR}" ]]
  then
    return 0
  fi

  safe_cd "${VENDOR_DIR}/portable-${VENDOR_NAME}"

  if "./${VENDOR_VERSION}/bin/${VENDOR_NAME}" --version >/dev/null
  then
    ln -sfn "${VENDOR_VERSION}" current
    if [[ -d "${VENDOR_VERSION}.reinstall" ]]
    then
      rm -rf "${VENDOR_VERSION}.reinstall"
    fi
  else
    rm -rf "${VENDOR_VERSION}"
    if [[ -d "${VENDOR_VERSION}.reinstall" ]]
    then
      mv "${VENDOR_VERSION}.reinstall" "${VENDOR_VERSION}"
    fi
    odie "Failed to install ${VENDOR_NAME} ${VENDOR_VERSION}!"
  fi

  trap - SIGINT
}

homebrew-vendor-install() {
  local option
  local url_var
  local sha_var

  unset VENDOR_PHYSICAL_PROCESSOR
  unset VENDOR_PROCESSOR

  for option in "$@"
  do
    case "${option}" in
      -\? | -h | --help | --usage)
        brew help vendor-install
        exit $?
        ;;
      --verbose) HOMEBREW_VERBOSE=1 ;;
      --quiet) HOMEBREW_QUIET=1 ;;
      --debug) HOMEBREW_DEBUG=1 ;;
      --*) ;;
      -*)
        [[ "${option}" == *v* ]] && HOMEBREW_VERBOSE=1
        [[ "${option}" == *q* ]] && HOMEBREW_QUIET=1
        [[ "${option}" == *d* ]] && HOMEBREW_DEBUG=1
        ;;
      *)
        if [[ -n "${VENDOR_NAME}" ]]
        then
          if [[ -n "${HOMEBREW_DEVELOPER}" ]]
          then
            if [[ -n "${PROCESSOR_TARGET}" ]]
            then
              odie "This command does not take more than vendor and processor targets!"
            else
              VENDOR_PHYSICAL_PROCESSOR="${option}"
              VENDOR_PROCESSOR="${option}"
            fi
          else
            odie "This command does not take multiple vendor targets!"
          fi
        else
          VENDOR_NAME="${option}"
        fi
        ;;
    esac
  done

  [[ -z "${VENDOR_NAME}" ]] && odie "This command requires a vendor target!"
  [[ -n "${HOMEBREW_DEBUG}" ]] && set -x

  if [[ -z "${VENDOR_PHYSICAL_PROCESSOR}" ]]
  then
    VENDOR_PHYSICAL_PROCESSOR="${HOMEBREW_PHYSICAL_PROCESSOR}"
  fi

  if [[ -z "${VENDOR_PROCESSOR}" ]]
  then
    VENDOR_PROCESSOR="${HOMEBREW_PROCESSOR}"
  fi

  set_ruby_variables
  check_linux_glibc_version

  filename_var="${VENDOR_NAME}_FILENAME"
  sha_var="${VENDOR_NAME}_SHA"
  url_var="${VENDOR_NAME}_URL"
  VENDOR_FILENAME="${!filename_var}"
  VENDOR_SHA="${!sha_var}"
  VENDOR_URL="${!url_var}"
  VENDOR_VERSION="$(cat "${VENDOR_DIR}/portable-${VENDOR_NAME}-version")"

  if [[ -z "${VENDOR_URL}" || -z "${VENDOR_SHA}" ]]
  then
    odie "No Homebrew ${VENDOR_NAME} ${VENDOR_VERSION} available for ${HOMEBREW_PROCESSOR} processors!"
  fi

  # Expand the name to an array of variables
  # The array name must be "${VENDOR_NAME}_URLs"! Otherwise substitution errors will occur!
  # shellcheck disable=SC2086
  read -r -a VENDOR_URLs <<<"$(eval "echo "\$\{${url_var}s[@]\}"")"

  CACHED_LOCATION="${HOMEBREW_CACHE}/${VENDOR_FILENAME}"

  lock "vendor-install ${VENDOR_NAME}"
  fetch
  install
}
