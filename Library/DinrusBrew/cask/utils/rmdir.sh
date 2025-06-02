#!/bin/bash

set -euo pipefail

# Try removing as many empty directories as possible with a single
# `rmdir` call to avoid or at least speed up the loop below.
if /bin/rmdir -- "${@}" &>/dev/null
then
  exit
fi

for path in "${@}"
do
  symlink=true
  [[ -L "${path}" ]] || symlink=false

  directory=false
  if [[ -d "${path}" ]]
  then
    directory=true

    if [[ -e "${path}/.DS_Store" ]]
    then
      /bin/rm -- "${path}/.DS_Store"
    fi

    # Some packages leave broken symlinks around; we clean them out before
    # attempting to `rmdir` to prevent extra cruft from accumulating.
    /usr/bin/find -f "${path}" -- -mindepth 1 -maxdepth 1 -type l ! -exec /bin/test -e {} \; -delete
  elif ! ${symlink} && [[ ! -e "${path}" ]]
  then
    # Skip paths that don't exists and aren't a broken symlink.
    continue
  fi

  if ${symlink}
  then
    # Delete directory symlink.
    /bin/rm -- "${path}"
  elif ${directory}
  then
    # Delete directory if empty.
    /usr/bin/find -f "${path}" -- -maxdepth 0 -type d -empty -exec /bin/rmdir -- {} \;
  else
    # Try `rmdir` anyways to show a proper error.
    /bin/rmdir -- "${path}"
  fi
done
