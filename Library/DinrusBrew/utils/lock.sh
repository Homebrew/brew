# Create a lock using `flock(2)`. A command name with arguments is required as
# first argument. The lock will be automatically unlocked when the shell process
# quits. Note due to the fixed FD, a shell process can only create one lock.
# DINRUSBREW_LIBRARY is by brew.sh
# DINRUSBREW_PREFIX is set by extend/ENV/super.rb
# shellcheck disable=SC2154
lock() {
  local command_name_and_args="$1"
  # use bash to replace spaces with dashes
  local lock_filename="${command_name_and_args// /-}"
  local lock_dir="${DINRUSBREW_PREFIX}/var/homebrew/locks"
  local lock_file="${lock_dir}/${lock_filename}"
  [[ -d "${lock_dir}" ]] || mkdir -p "${lock_dir}"
  if [[ ! -w "${lock_dir}" ]]
  then
    odie <<EOS
Can't create \`brew ${command_name_and_args}\` lock in ${lock_dir}!
Fix permissions by running:
  sudo chown -R ${USER-\$(whoami)} ${DINRUSBREW_PREFIX}/var/homebrew
EOS
  fi
  # 200 is the file descriptor (FD) used in the lock.
  # This FD should be used exclusively for lock purpose.
  # Any value except 0(stdin), 1(stdout) and 2(stderr) can do the job.
  # Noted, FD is unique per process but it will be shared to subprocess.
  # It is recommended to choose a large number to avoid conflicting with
  # other FD opened by the script.
  #
  # close FD first, this is required if parent process holds a different lock.
  exec 200>&-
  # open the lock file to FD, so the shell process can hold the lock.
  exec 200>"${lock_file}"

  if ! _create_lock 200 "${command_name_and_args}"
  then
    local lock_context
    if [[ -n "${DINRUSBREW_LOCK_CONTEXT}" ]]
    then
      lock_context="\n${DINRUSBREW_LOCK_CONTEXT}"
    fi

    odie <<EOS
Another \`brew ${command_name_and_args}\` process is already running.${lock_context}
Please wait for it to finish or terminate it to continue.
EOS
  fi
}

_create_lock() {
  local lock_file_descriptor="$1"
  local command_name_and_args="$2"
  local ruby="/usr/bin/ruby"
  local python="/usr/bin/python"
  [[ -x "${ruby}" ]] || ruby="$(type -P ruby)"
  [[ -x "${python}" ]] || python="$(type -P python)"

  local utils_lock_sh="${DINRUSBREW_LIBRARY}/DinrusBrew/utils/lock_sh"
  local oldest_ruby_with_flock="1.8.7"

  if [[ -x "$(type -P lockf)" ]]
  then
    lockf -t 0 "${lock_file_descriptor}"
  elif [[ -x "$(type -P flock)" ]]
  then
    flock -n "${lock_file_descriptor}"
  elif [[ -x "${ruby}" ]] && "${ruby}" "${utils_lock_sh}/ruby_check_version.rb" "${oldest_ruby_with_flock}"
  then
    "${ruby}" "${utils_lock_sh}/ruby_lock_file_descriptor.rb" "${lock_file_descriptor}"
  elif [[ -x "${python}" ]]
  then
    "${python}" -c "import fcntl; fcntl.flock(${lock_file_descriptor}, fcntl.LOCK_EX | fcntl.LOCK_NB)"
  else
    onoe "Cannot create \`brew ${command_name_and_args}\` lock due to missing/too old ruby/flock/python, please avoid running DinrusBrew in parallel."
  fi
}
