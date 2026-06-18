# Documentation defined in Library/Homebrew/cmd/exec.rb

# shellcheck disable=SC2154
source "${HOMEBREW_LIBRARY}/Homebrew/utils/cmd.sh"
source "${HOMEBREW_LIBRARY}/Homebrew/utils/executables.sh"

exec-formula-name() {
  local formula="$1"
  echo "${formula##*/}"
}

exec-latest-keg() {
  local formula_name
  formula_name="$(exec-formula-name "$1")"

  # `opt/<formula>` is Homebrew's active-version pointer. Prefer it over
  # sorting Cellar directories; plain lexicographic sorting gets versions like
  # `2.10` and `2.9` wrong.
  local opt_prefix
  opt_prefix="${HOMEBREW_PREFIX}/opt/${formula_name}"
  if [[ -d "${opt_prefix}" ]]
  then
    local opt_keg
    opt_keg="$(cd "${opt_prefix}" &>/dev/null && pwd -P)" || return 1
    echo "${opt_keg}"
    return
  fi

  local cellar="${HOMEBREW_CELLAR}/${formula_name}"
  [[ -d "${cellar}" ]] || return 1

  local keg
  local -a installed_kegs=()
  for keg in "${cellar}"/*
  do
    [[ -d "${keg}" ]] && installed_kegs+=("${keg}")
  done

  [[ "${#installed_kegs[@]}" -eq 1 ]] || return 1

  echo "${installed_kegs[0]}"
}

exec-formula-installed() {
  exec-latest-keg "$1" &>/dev/null
}

exec-add-path() {
  # Bash arrays cannot be de-duplicated directly, so keep the PATH fragments
  # ordered and skip entries we have already seen.
  local path="$1"
  [[ -d "${path}" ]] || return

  local entry
  for entry in "${exec_path_entries[@]}"
  do
    [[ "${entry}" == "${path}" ]] && return
  done

  exec_path_entries+=("${path}")
}

exec-add-formula-paths() {
  # `exec_path_entries` is declared local in `homebrew-exec`. Bash uses dynamic
  # scoping for `local`, so this helper can append to that caller-local array.
  local formula="$1"
  local formula_name keg
  formula_name="$(exec-formula-name "${formula}")"

  exec-add-path "${HOMEBREW_PREFIX}/opt/${formula_name}/bin"
  exec-add-path "${HOMEBREW_PREFIX}/opt/${formula_name}/sbin"

  if keg="$(exec-latest-keg "${formula}")"
  then
    exec-add-path "${keg}/bin"
    exec-add-path "${keg}/sbin"
  fi
}

homebrew-exec() {
  local formulae=()
  local formulae_arg=""
  local formulae_seen=0
  local sandbox_path=""
  local sandbox_seen=0
  local deny_network=0

  while [[ "$#" -gt 0 ]]
  do
    if homebrew-command-help exec "$1"
    then
      return $?
    fi
    if homebrew-command-common-option "$1"
    then
      shift
      continue
    fi

    case "$1" in
      --formulae=*)
        formulae_arg="${1#--formulae=}"
        formulae_seen=1
        shift
        ;;
      --formulae)
        shift
        [[ "$#" -gt 0 && "$1" != -* ]] || odie "\`--formulae\` requires a comma-separated formula list."
        formulae_arg="$1"
        formulae_seen=1
        shift
        ;;
      --sandbox=*)
        sandbox_path="${1#--sandbox=}"
        sandbox_seen=1
        shift
        ;;
      --sandbox)
        shift
        [[ "$#" -gt 0 && "$1" != -* ]] || odie "\`--sandbox\` requires a writable path."
        sandbox_path="$1"
        sandbox_seen=1
        shift
        ;;
      --deny-network)
        deny_network=1
        shift
        ;;
      --)
        shift
        break
        ;;
      --*)
        echo "Unknown option: $1" >&2
        "${HOMEBREW_BREW_FILE}" help exec
        return 1
        ;;
      *)
        break
        ;;
    esac
  done

  [[ "${sandbox_seen}" -eq 0 || -n "${sandbox_path}" ]] || odie "\`--sandbox\` requires a writable path."
  [[ "${sandbox_seen}" -eq 1 || "${deny_network}" -eq 0 ]] || odie "\`--deny-network\` requires \`--sandbox\`."

  homebrew-command-enable-debug

  if [[ "${formulae_seen}" -eq 1 ]]
  then
    [[ -n "${formulae_arg}" ]] || odie "\`--formulae\` requires a comma-separated formula list."
    IFS=',' read -r -a formulae <<<"${formulae_arg}"
    local formula formula_index
    for formula_index in "${!formulae[@]}"
    do
      formula="${formulae[formula_index]}"
      formula="${formula#"${formula%%[![:space:]]*}"}"
      formula="${formula%"${formula##*[![:space:]]}"}"
      [[ -n "${formula}" ]] || odie "\`--formulae\` entries must not be empty."
      formulae[formula_index]="${formula}"
    done
  fi

  local executable="${1:-}"
  if [[ -z "${executable}" ]]
  then
    "${HOMEBREW_BREW_FILE}" help exec
    return 1
  fi
  shift

  local provider_lookup=0
  if [[ "${#formulae[@]}" -eq 0 ]]
  then
    [[ "${executable}" != */* ]] || odie "Executable name must not contain path separators without \`--formulae\`."

    provider_lookup=1
    ensure_executables_file >&2

    local -a matching_formulae=()
    local selected_formula formula
    selected_formula=""
    # Some executables are provided by multiple formulae. Prefer an already
    # installed provider to avoid unnecessary installs; otherwise use the first
    # provider listed by the database.
    while read -r formula
    do
      matching_formulae+=("${formula}")

      if [[ -z "${selected_formula}" ]] && exec-formula-installed "${formula}"
      then
        selected_formula="${formula}"
      fi
    done < <(formulae_containing_executable "${executable}")

    [[ "${#matching_formulae[@]}" -gt 0 ]] || odie "No Homebrew formula found for \`${executable}\`."

    if [[ -n "${selected_formula}" ]]
    then
      formulae=("${selected_formula}")
    else
      formulae=("${matching_formulae[0]}")
    fi
  fi

  local formula
  for formula in "${formulae[@]}"
  do
    if ! exec-formula-installed "${formula}"
    then
      if [[ "${provider_lookup}" -eq 1 ]]
      then
        ohai "Installing \`${formula}\` because it provides \`${executable}\`." >&2
      else
        ohai "Installing \`${formula}\`." >&2
      fi
      "${HOMEBREW_BREW_FILE}" install --formula "${formula}" >&2 || return
    fi
  done

  local executable_path="${executable}"
  if [[ "${provider_lookup}" -eq 1 ]]
  then
    local candidate formula_name keg
    executable_path=""
    for formula in "${formulae[@]}"
    do
      formula_name="$(exec-formula-name "${formula}")"
      local -a executable_candidate_paths=(
        "${HOMEBREW_PREFIX}/opt/${formula_name}/bin/${executable}"
        "${HOMEBREW_PREFIX}/opt/${formula_name}/sbin/${executable}"
      )

      # Do not use `HOMEBREW_PREFIX`/bin or sbin here. A different provider may
      # be linked there with the same executable name.
      # `break 2` leaves both this candidate loop and the surrounding formula
      # loop as soon as a path has been narrowed down.
      for candidate in "${executable_candidate_paths[@]}"
      do
        if [[ -f "${candidate}" && -x "${candidate}" ]]
        then
          executable_path="${candidate}"
          break 2
        fi
      done

      if keg="$(exec-latest-keg "${formula}")"
      then
        for candidate in "${keg}/bin/${executable}" "${keg}/sbin/${executable}"
        do
          if [[ -f "${candidate}" && -x "${candidate}" ]]
          then
            executable_path="${candidate}"
            break 2
          fi
        done
      fi
    done

    [[ -n "${executable_path}" ]] || odie "\`${executable}\` was not found in formulae: ${formulae[*]}."
  fi

  local -a exec_path_entries=()
  local dependency exec_path path_index
  for formula in "${formulae[@]}"
  do
    exec-add-formula-paths "${formula}"
  done

  for formula in "${formulae[@]}"
  do
    # Process substitution keeps the `while` loop in this shell process.
    # A pipeline would run the loop in a subshell on Bash, losing array changes.
    while read -r dependency
    do
      [[ -n "${dependency}" ]] && exec-add-formula-paths "${dependency}"
    done < <("${HOMEBREW_BREW_FILE}" deps --topological --formula "${formula}" 2>/dev/null)
  done

  exec_path="${HOMEBREW_PATH:-${PATH}}"
  # Entries are collected in PATH priority order. Prepend them in reverse so the
  # first collected directory remains first in the final PATH.
  for ((path_index = ${#exec_path_entries[@]} - 1; path_index >= 0; path_index--))
  do
    exec_path="${exec_path_entries[path_index]}:${exec_path}"
  done

  PATH="${exec_path}"
  export PATH
  # Replace the shell with the target command so signals and exit status behave
  # as if the executable had been run directly.
  if [[ -n "${sandbox_path}" ]]
  then
    local -a sandbox_args=("sandbox-exec")
    [[ "${deny_network}" -eq 1 ]] && sandbox_args+=("--deny-network")
    sandbox_args+=("${sandbox_path}" "--" "${executable_path}" "$@")
    exec "${HOMEBREW_BREW_FILE}" "${sandbox_args[@]}"
  fi

  exec "${executable_path}" "$@"
}
