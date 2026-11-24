# Shared executable selection. Cache data is read, never sourced as shell code.

# The caller supplies the environment and uses the selection results.
# shellcheck disable=SC2034,SC2154

install_tool() {
  local tool="$1" minimum="$2"
  # The installer must get through startup without recursively installing tools.
  [[ -z "${HOMEBREW_INSTALLING_TOOL}" ]] || return 0

  if [[ -d "${HOMEBREW_CORE_REPOSITORY}" || -z "${HOMEBREW_NO_INSTALL_FROM_API}" ]]
  then
    HOMEBREW_INSTALLING_TOOL=1 HOMEBREW_NO_AUTO_UPDATE=1 brew install "${tool}" || true
  fi
  # An installation can fail partway through or succeed without fixing the tool.
  # Keep the cache location in sync with Utils::Tool.invalidate_cache in utils/tool.rb.
  if [[ -n "${HOMEBREW_CACHE}" ]]
  then
    rm -f "${HOMEBREW_CACHE}/tool-selection/${tool}" 2>/dev/null || true
  fi
  report_probe_errors=1 "setup_${tool}"
  [[ -n "${HOMEBREW_SELECTED_TOOL}" ]] && return 0

  odie "Unable to automatically install a working ${tool/git/Git}.
Minimum required version: ${minimum}${HOMEBREW_TOOL_DIAGNOSTICS}"
}

select_tool() {
  local tool="$1" minimum="$2" brewed="$3" system="$4" suggested="$5" force="$6"
  local cache_dir="${HOMEBREW_CACHE}/tool-selection" cache_file key cached_key cached_path cached_version
  local cached_system_usable
  local candidate output version version_number best_version=0 temporary_file i minimum_number label="${tool/git/Git}"
  local version_regex="^${tool}(,? version)? ([0-9]+\.[0-9]+(\.[0-9]+)?)"
  minimum_number="$(numeric "${minimum}")"
  HOMEBREW_SELECTED_TOOL=""
  HOMEBREW_SELECTED_TOOL_VERSION=""
  HOMEBREW_SYSTEM_TOOL_USABLE=0
  HOMEBREW_TOOL_DIAGNOSTICS=""

  if [[ -n "${suggested}" && "${suggested}" != */* ]]
  then
    suggested="$(PATH="${HOMEBREW_PATH:-${PATH}}" type -P "${suggested}")"
  fi
  local candidates=("${brewed}" "${system}" "${suggested}")
  cache_file="${cache_dir}/${tool}"
  key="$(
    printf '%s\n' "${minimum}" "${force}" "${candidates[@]}"
    # Follow opt symlinks. Device/inode detect replacements; precise modification
    # and change times detect in-place edits and permission changes. Include this
    # helper so policy changes also expire the cache. BSD and GNU stat differ.
    if [[ "${OSTYPE}" == darwin* ]]
    then
      /usr/bin/stat -L -f '%d:%i:%Fm:%Fc' "${candidates[@]}" "${BASH_SOURCE[0]}" 2>/dev/null
    else
      /usr/bin/stat -L -c '%d:%i:%y:%z' "${candidates[@]}" "${BASH_SOURCE[0]}" 2>/dev/null
    fi
  )"
  # Read four NUL-delimited fields as data, preserving spaces and newlines.
  # Only reuse our own complete cache with matching inputs and an executable
  # candidate whose cached version still meets the minimum.
  if [[ -n "${HOMEBREW_CACHE}" && ! -L "${cache_dir}" && ! -L "${cache_file}" &&
        -f "${cache_file}" && -r "${cache_file}" && -O "${cache_file}" ]] &&
     {
     IFS= read -r -d '' cached_key &&
     IFS= read -r -d '' cached_path &&
     IFS= read -r -d '' cached_version &&
     IFS= read -r -d '' cached_system_usable
     } <"${cache_file}" &&
     [[ "${key}" == "${cached_key}" && -x "${cached_path}" && "${cached_version}" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] &&
     [[ "${cached_path}" == "${brewed}" || "${cached_path}" == "${system}" || "${cached_path}" == "${suggested}" ]] &&
     [[ "${cached_system_usable}" == 0 || "${cached_system_usable}" == 1 ]] &&
     [[ "$(numeric "${cached_version}")" -ge "${minimum_number}" ]]
  then
    HOMEBREW_SELECTED_TOOL="${cached_path}"
    HOMEBREW_SELECTED_TOOL_VERSION="${cached_version}"
    HOMEBREW_SYSTEM_TOOL_USABLE="${cached_system_usable}"
    return 0
  fi

  for ((i = 0; i < ${#candidates[@]}; i++))
  do
    # Compare both installed defaults before considering the final suggestion.
    [[ ${i} -eq 2 && -n "${HOMEBREW_SELECTED_TOOL}" ]] && break
    candidate="${candidates[i]}"
    [[ -n "${candidate}" ]] || continue
    version="unavailable"
    version_number=0
    # Never probe our own shim or trust version output from a failed command.
    if [[ -f "${candidate}" && -x "${candidate}" &&
       ! "${candidate}" -ef "${HOMEBREW_LIBRARY}/Homebrew/shims/shared/${tool}" ]]
    then
      if output="$("${candidate}" --version 2>/dev/null)" && [[ "${output}" =~ ${version_regex} ]]
      then
        version="${BASH_REMATCH[2]}"
        version_number="$(numeric "${version}")"
      elif [[ -n "${report_probe_errors}" ]]
      then
        # Keep stderr separate from the version we parse on stdout.
        output="$("${candidate}" --version 2>&1 >/dev/null)" || true
        version+="${output:+ (${output})}"
      fi
    fi
    printf -v HOMEBREW_TOOL_DIAGNOSTICS '%s\n%24s: %s\n%24s: %s' "${HOMEBREW_TOOL_DIAGNOSTICS}" \
      "Your ${label} version" "${version}" "Your ${label} executable" "${candidate}"
    [[ "${version_number}" -ge "${minimum_number}" ]] || continue
    [[ "${candidate}" == "${system}" ]] && HOMEBREW_SYSTEM_TOOL_USABLE=1
    # Record system suitability even when FORCE already selected Homebrew.
    [[ -n "${force}" && "${HOMEBREW_SELECTED_TOOL}" == "${brewed}" ]] && continue
    [[ "${version_number}" -gt "${best_version}" ]] || continue
    HOMEBREW_SELECTED_TOOL="${candidate}"
    HOMEBREW_SELECTED_TOOL_VERSION="${version}"
    best_version="${version_number}"
  done
  [[ -n "${HOMEBREW_SELECTED_TOOL}" ]] || return 1

  # An unwritable cache must not prevent bootstrapping or sandboxed commands.
  if [[ -n "${HOMEBREW_CACHE}" && ! -L "${cache_dir}" && ! -d "${cache_file}" ]] && mkdir -p "${cache_dir}" 2>/dev/null &&
     temporary_file="$(mktemp "${cache_file}.XXXXXX" 2>/dev/null)"
  then
    printf '%s\0' "${key}" "${HOMEBREW_SELECTED_TOOL}" "${HOMEBREW_SELECTED_TOOL_VERSION}" \
      "${HOMEBREW_SYSTEM_TOOL_USABLE}" >"${temporary_file}"
    mv -f "${temporary_file}" "${cache_file}" 2>/dev/null || rm -f "${temporary_file}" 2>/dev/null
  fi
  return 0
}
