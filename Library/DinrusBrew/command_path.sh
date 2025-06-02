# does the quickest output of brew command possible for the basic cases of an
# official Bash or Ruby normal or dev-cmd command.
# DINRUSBREW_LIBRARY is set by brew.sh
# shellcheck disable=SC2154
homebrew-command-path() {
  case "$1" in
    # check we actually have command and not e.g. commandsomething
    command) ;;
    command*) return 1 ;;
    *) ;;
  esac

  local first_command found_command
  for arg in "$@"
  do
    if [[ -z "${first_command}" && "${arg}" == "command" ]]
    then
      first_command=1
      continue
    elif [[ -f "${DINRUSBREW_LIBRARY}/DinrusBrew/cmd/${arg}.sh" ]]
    then
      echo "${DINRUSBREW_LIBRARY}/DinrusBrew/cmd/${arg}.sh"
      found_command=1
    elif [[ -f "${DINRUSBREW_LIBRARY}/DinrusBrew/dev-cmd/${arg}.sh" ]]
    then
      echo "${DINRUSBREW_LIBRARY}/DinrusBrew/dev-cmd/${arg}.sh"
      found_command=1
    elif [[ -f "${DINRUSBREW_LIBRARY}/DinrusBrew/cmd/${arg}.rb" ]]
    then
      echo "${DINRUSBREW_LIBRARY}/DinrusBrew/cmd/${arg}.rb"
      found_command=1
    elif [[ -f "${DINRUSBREW_LIBRARY}/DinrusBrew/dev-cmd/${arg}.rb" ]]
    then
      echo "${DINRUSBREW_LIBRARY}/DinrusBrew/dev-cmd/${arg}.rb"
      found_command=1
    else
      return 1
    fi
  done

  if [[ -n "${found_command}" ]]
  then
    return 0
  else
    return 1
  fi
}
