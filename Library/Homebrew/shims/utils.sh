set +o posix

quiet_safe_cd() {
  cd "$1" &>/dev/null || {
    echo "Error: failed to cd to $1" >&2
    exit 1
  }
}

absdir() {
  quiet_safe_cd "${1%/*}/" && pwd -P
}

dirbasepath() {
  local dir="$1"
  local base="${2##*/}"
  echo "${dir}/${base}"
}

realpath() {
  local path="$1"
  local dir
  local dest

  dir="$(absdir "${path}")"
  path="$(dirbasepath "${dir}" "${path}")"

  while [[ -L "${path}" ]]
  do
    dest="$(readlink "${path}")"
    if [[ "${dest}" == "/"* ]]
    then
      path="${dest}"
    else
      path="${dir}/${dest}"
    fi
    dir="$(absdir "${path}")"
    path="$(dirbasepath "${dir}" "${path}")"
  done

  echo "${path}"
}

executable() {
  local file="$1"
  [[ -f "${file}" && -x "${file}" ]]
}

lowercase() {
  echo "$1" | tr "[:upper:]" "[:lower:]"
}

safe_exec() {
  local arg0="$1"
  if ! executable "${arg0}"
  then
    return
  fi
  # prevent fork-bombs and exec loops between this shim and the same shared
  # shim in another Homebrew checkout (found on PATH or by a stale xcrun cache)
  local arg0_real
  arg0_real="$(realpath "${arg0}")"
  if [[ "$(lowercase "${arg0}")" == "${SHIM_FILE}" || "${arg0_real}" == "${SHIM_REAL}" ||
        "${arg0_real}" == */shims/shared/"${SHIM_REAL##*/}" ]]
  then
    return
  fi
  if [[ "${HOMEBREW}" == "print-path" ]]
  then
    local dir
    dir="$(quiet_safe_cd "${arg0%/*}/" && pwd)"
    local path
    path="$(dirbasepath "${dir}" "${arg0}")"
    echo "${path}"
    exit
  fi
  exec "$@"
}

try_exec_non_system() {
  local file="$1"
  shift

  local path
  while read -r path
  do
    if [[ "${path}" != "/usr/bin/${file}" ]]
    then
      safe_exec "${path}" "$@"
    fi
  done < <(type -aP "${file}")
}

SHIM_FILE="${0##*/}"
SHIM_REAL="$(realpath "$0")"

if [[ "$1" == "--homebrew="* ]]
then
  HOMEBREW="${1:11}"
  shift
fi
