#!/bin/bash

onoe() {
  echo "$*" >&2
}

odie() {
  onoe "$@"
  exit 1
}

# HOMEBREW_PREFIX is set by extend/ENV/super.rb
# shellcheck disable=SC2154
if [[ -z "${HOMEBREW_PREFIX}" ]]
then
  odie "${0##*/}: This program is internal and must be run via brew."
fi

# HOMEBREW_PREFIX is set by extend/ENV/super.rb
# shellcheck disable=SC2154
SHFMT="${HOMEBREW_PREFIX}/opt/shfmt/bin/shfmt"
if [[ ! -x "${SHFMT}" ]]
then
  odie "${0##*/}: Please install shfmt by running \`brew install shfmt\`."
fi

# HOMEBREW_PREFIX is set by extend/ENV/super.rb
# shellcheck disable=SC2154
DIFF="${HOMEBREW_PREFIX}/opt/diffutils/bin/diff"
DIFF_ARGS=("-d" "-C" "1")
if [[ ! -x "${DIFF}" ]]
then
  # HOMEBREW_PATH is set by global.rb
  # shellcheck disable=SC2154
  if [[ -x "$(PATH="${HOMEBREW_PATH}" command -v diff)" ]]
  then
    DIFF="$(PATH="${HOMEBREW_PATH}" command -v diff)" # fall back to `diff` in PATH without coloring
  elif [[ -z "${HOMEBREW_PATH}" && -x "$(command -v diff)" ]]
  then
    # HOMEBREW_PATH may unset if shfmt.sh is called by vscode
    DIFF="$(command -v diff)" # fall back to `diff` in PATH without coloring
  else
    odie "${0##*/}: Please install diff by running \`brew install diffutils\`."
  fi
else
  DIFF_ARGS+=("--color") # enable color output for GNU diff
fi

SHFMT_ARGS=()
INPLACE=''
while [[ $# -gt 0 ]]
do
  arg="$1"
  if [[ "${arg}" == "--" ]]
  then
    shift
    break
  fi
  if [[ "${arg}" == "-w" || "${arg}" == "--write" ]]
  then
    shift
    INPLACE=1
    continue
  fi
  SHFMT_ARGS+=("${arg}")
  shift
done
unset arg

FILES=()
for file in "$@"
do
  if [[ -f "${file}" ]]
  then
    if [[ -w "${file}" ]]
    then
      FILES+=("${file}")
    else
      onoe "${0##*/}: File \"${file}\" is not writable."
    fi
  else
    onoe "${0##*/}: File \"${file}\" does not exist."
    exit 1
  fi
done
unset file

STDIN=''
if [[ "${#FILES[@]}" == 0 ]]
then
  FILES=(/dev/stdin)
  STDIN=1
fi

###
### Custom shell script styling
###

# Check for specific patterns and prompt messages if detected
no_forbidden_pattern() {
  local file="$1"
  local tempfile="$2"
  local subject="$3"
  local message="$4"
  local regex_pos="$5"
  local regex_neg="${6:-}"
  local line
  local num=0
  local retcode=0

  while IFS='' read -r line
  do
    num="$((num + 1))"
    if [[ "${line}" =~ ${regex_pos} ]] &&
       [[ -z "${regex_neg}" || ! "${line}" =~ ${regex_neg} ]]
    then
      onoe "${subject} detected at \"${file}\", line ${num}."
      [[ -n "${message}" ]] && onoe "${message}"
      retcode=1
    fi
  done <"${file}"
  return "${retcode}"
}

# Check pattern:
# '^\t+'
#
# Replace tabs with 2 spaces instead
#
no_tabs() {
  local file="$1"
  local tempfile="$2"

  no_forbidden_pattern "${file}" "${tempfile}" \
    "Indent with tab" \
    'Replace tabs with 2 spaces instead.' \
    '^[[:space:]]+' \
    '^ +'
}

# Check pattern:
# for var in ... \
#            ...; do
#
# Use the followings instead (keep for statements only one line):
#   ARRAY=(
#     ...
#   )
#   for var in "${ARRAY[@]}"
#   do
#
no_multiline_for_statements() {
  local file="$1"
  local tempfile="$2"
  local regex='^ *for [_[:alnum:]]+ in .*\\$'
  local message
  message="$(
    cat <<EOMSG
Use the followings instead (keep for statements only one line):
  ARRAY=(
    ...
  )
  for var in "\${ARRAY[@]}"
  do
    ...
  done
EOMSG
  )"

  no_forbidden_pattern "${file}" "${tempfile}" \
    "Multiline for statement" \
    "${message}" \
    "${regex}"
}

# Check pattern:
# IFS=$'\n'
#
# Use the followings instead:
#   while IFS='' read -r line
#   do
#     ...
#   done < <(command)
#
no_IFS_newline() {
  local file="$1"
  local tempfile="$2"
  local regex="^[^#]*IFS=\\\$'\\\\n'"
  local message
  message="$(
    cat <<EOMSG
Use the followings instead:
  while IFS='' read -r line
  do
    ...
  done < <(command)
EOMSG
  )"

  no_forbidden_pattern "${file}" "${tempfile}" \
    "Pattern \`IFS=\$'\\n'\`" \
    "${message}" \
    "${regex}"
}

# Combine all forbidden styles
no_forbidden_styles() {
  local file="$1"
  local tempfile="$2"

  no_tabs "${file}" "${tempfile}" || return 1
  no_multiline_for_statements "${file}" "${tempfile}" || return 1
  no_IFS_newline "${file}" "${tempfile}" || return 1
}

# Align multiline if condition (indent with 3 spaces or 6 spaces (start with "-"))
# before:                   after:
#   if [[ ... ]] ||           if [[ ... ]] ||
#     [[ ... ]]                  [[ ... ]]
#   then                      then
#
# before:                   after:
#   if [[ -n ... ||           if [[ -n ... ||
#     -n ... ]]                     -n ... ]]
#   then                      then
#
align_multiline_if_condition() {
  local line
  local lastline=''
  local base_indent=''       # indents before `if`
  local elif_extra_indent='' # 2 extra spaces for `elif`
  local multiline_if_then_begin_regex='^( *)(el)?if '
  local multiline_if_then_end_regex='^(.*)\; (then( *#.*)?)$'
  local within_test_regex='^( *)(((! )?-[fdLrwxeszn] )|([^\[]+ (==|!=|=~) ))'

  trim() {
    [[ "$1" =~ [^[:space:]](.*[^[:space:]])? ]]
    printf "%s" "${BASH_REMATCH[0]}"
  }

  if [[ "$1" =~ ${multiline_if_then_begin_regex} ]]
  then
    base_indent="${BASH_REMATCH[1]}"
    [[ -n "${BASH_REMATCH[2]}" ]] && elif_extra_indent='  ' # 2 extra spaces for `elif`
    echo "$1"
    shift
  fi

  while [[ "$#" -gt 0 ]]
  do
    line="$1"
    shift
    if [[ "${line}" =~ ${multiline_if_then_end_regex} ]]
    then
      line="${BASH_REMATCH[1]}"
      lastline="${base_indent}${BASH_REMATCH[2]}"
    fi
    if [[ "${line}" =~ ${within_test_regex} ]]
    then
      # Add 3 extra spaces (6 spaces in total) to multiline test conditions
      # before:                   after:
      #   if [[ -n ... ||           if [[ -n ... ||
      #     -n ... ]]                     -n ... ]]
      #   then                      then
      echo "${base_indent}${elif_extra_indent}      $(trim "${line}")"
    else
      echo "${base_indent}${elif_extra_indent}   $(trim "${line}")"
    fi
  done

  echo "${lastline}"
}

# Wrap `then` and `do` to a separated line
# before:                   after:
#   if [[ ... ]]; then        if [[ ... ]]
#                             then
#
# before:                   after:
#   if [[ ... ]] ||           if [[ ... ]] ||
#     [[ ... ]]; then            [[ ... ]]
#                             then
#
# before:                   after:
#   for var in ...; do        for var in ...
#                             do
#
wrap_then_do() {
  local file="$1"
  local tempfile="$2"

  local -a processed=()
  local -a buffer=()
  local line
  local singleline_if_then_fi_regex='^( *)if (.+)\; then (.+)\; fi( *#.*)?$'
  local singleline_if_then_regex='^( *)(el)?if (.+)\; (then( *#.*)?)$'
  local singleline_for_do_regex='^( *)(for|while) (.+)\; (do( *#.*)?)$'
  local multiline_if_then_begin_regex='^( *)(el)?if '
  local multiline_if_then_end_regex='^(.*)\; (then( *#.*)?)$'

  while IFS='' read -r line
  do
    if [[ "${#buffer[@]}" == 0 ]]
    then
      if [[ "${line}" =~ ${singleline_if_then_fi_regex} ]]
      then
        processed+=("${line}")
      elif [[ "${line}" =~ ${singleline_if_then_regex} ]]
      then
        processed+=("${BASH_REMATCH[1]}${BASH_REMATCH[2]}if ${BASH_REMATCH[3]}")
        processed+=("${BASH_REMATCH[1]}${BASH_REMATCH[4]}")
      elif [[ "${line}" =~ ${singleline_for_do_regex} ]]
      then
        processed+=("${BASH_REMATCH[1]}${BASH_REMATCH[2]} ${BASH_REMATCH[3]}")
        processed+=("${BASH_REMATCH[1]}${BASH_REMATCH[4]}")
      elif [[ "${line}" =~ ${multiline_if_then_begin_regex} ]]
      then
        buffer=("${line}")
      else
        processed+=("${line}")
      fi
    else
      buffer+=("${line}")
      if [[ "${line}" =~ ${multiline_if_then_end_regex} ]]
      then
        while IFS='' read -r line
        do
          processed+=("${line}")
        done < <(align_multiline_if_condition "${buffer[@]}")
        buffer=()
      fi
    fi
  done <"${tempfile}"

  printf "%s\n" "${processed[@]}" >"${tempfile}"
}

# TODO: It's hard to align multiline switch cases
align_multiline_switch_cases() {
  true
}

# Return codes:
#   0: success, good styles
#   1: file system permission errors
#   2: shfmt failed
#   3: forbidden styles detected
#   4: bad styles but can be auto-fixed
format() {
  local file="$1"
  local tempfile

  if [[ -n "${STDIN}" ]]
  then
    tempfile="$(mktemp)"
  else
    if [[ ! -f "${file}" || ! -r "${file}" ]]
    then
      onoe "File \"${file}\" is not readable."
      return 1
    fi

    tempfile="$(dirname "${file}")/.${file##*/}.formatted~"
    cp -af "${file}" "${tempfile}"
  fi
  trap 'rm -f "${tempfile}" 2>/dev/null' RETURN

  # Format with `shfmt` first
  if [[ -z "${STDIN}" ]]
  then
    if [[ ! -f "${tempfile}" || ! -w "${tempfile}" ]]
    then
      onoe "File \"${tempfile}\" is not writable."
      return 1
    fi
    if ! "${SHFMT}" -w "${SHFMT_ARGS[@]}" "${tempfile}"
    then
      onoe "Failed to run \`shfmt\` for file \"${file}\"."
      return 2
    fi
  else
    if ! "${SHFMT}" "${SHFMT_ARGS[@]}" >"${tempfile}"
    then
      onoe "Failed to run \`shfmt\` for file \"${file}\"."
      return 2
    fi
  fi

  # Fail fast when forbidden styles detected
  no_forbidden_styles "${file}" "${tempfile}" || return 3

  # Tweak it with custom shell script styles
  wrap_then_do "${file}" "${tempfile}"
  align_multiline_switch_cases "${file}" "${tempfile}"

  if [[ -n "${STDIN}" ]]
  then
    cat "${tempfile}"
    return 0
  fi

  if ! "${DIFF}" -q "${file}" "${tempfile}" &>/dev/null
  then
    if [[ -n "${INPLACE}" ]]
    then
      cp -af "${tempfile}" "${file}"
    else
      # Show a linebreak between outputs
      [[ "${RETCODE}" != 0 ]] && onoe
      # Show differences
      "${DIFF}" "${DIFF_ARGS[@]}" "${file}" "${tempfile}" 1>&2
    fi
    return 4
  else
    # File is identical between code formations (good styling)
    return 0
  fi
}

RETCODE=0
for file in "${FILES[@]}"
do
  retcode=''
  if [[ -n "${INPLACE}" ]]
  then
    INPLACE=1 format "${file}"
    retcode="$?"
    if [[ "${retcode}" == 4 ]]
    then
      onoe "${0##*/}: Bad styles detected in file \"${file}\", fixing..."
      retcode=''
    fi
  fi
  if [[ -z "${retcode}" ]]
  then
    INPLACE='' format "${file}"
    retcode="$?"
  fi
  if [[ "${retcode}" != 0 ]]
  then
    case "${retcode}" in
      1) onoe "${0##*/}: Failed to format file \"${file}\". Formatter exited with code 1 (permission error)." ;;
      2) onoe "${0##*/}: Failed to format file \"${file}\". Formatter exited with code 2 (\`shfmt\` failed)." ;;
      3) onoe "${0##*/}: Failed to format file \"${file}\". Formatter exited with code 3 (forbidden styles detected)." ;;
      4) onoe "${0##*/}: Fixable bad styles detected in file \"${file}\", run \`brew style --fix\` to apply. Formatter exited with code 4." ;;
      *) onoe "${0##*/}: Failed to format file \"${file}\". Formatter exited with code ${retcode}." ;;
    esac
    RETCODE=1
  fi
done

exit "${RETCODE}"
