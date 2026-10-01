#!/bin/bash
# This file is synced from the `.github` repository, do not modify it directly.

set -euo pipefail

if [[ ! -f .github/denied-licenses.txt ]]
then
  echo "::error::.github/denied-licenses.txt is required."
  exit 1
fi
denied="$(sed -E \
  '/^[[:space:]]*(#|$)/d; s/^[[:space:]]*//; s/[[:space:]]*$//' \
  .github/denied-licenses.txt | paste -sd, -)"
if [[ -z "${denied}" ]]
then
  echo "::error::.github/denied-licenses.txt must contain at least one licence."
  exit 1
fi
echo "Denied licences: ${denied}"

export GIT_PKGS_DB="${RUNNER_TEMP:?}/git-pkgs/metadata.db"
output="${RUNNER_TEMP}/licenses.json"
stderr="${RUNNER_TEMP}/licenses.stderr"
check_licenses() {
  local label="$1" status=0 violations count
  shift
  "$@" --format=json --deny="${denied}" \
    >"${output}" 2>"${stderr}" || status="$?"
  if ! jq -e 'type == "array"' "${output}" &>/dev/null
  then
    echo "git pkgs licenses failed:"
    cat "${stderr}"
    cat "${output}"
    if ((status == 0))
    then
      exit 1
    fi
    exit "${status}"
  fi

  violations="$(jq -r \
    '.[] | select(.flagged) | . as $dep |
    "\($dep.name) (\($dep.ecosystem)) \($dep.version // "?"): \($dep.licenses | join(", ")) - \($dep.flag_reason)"' \
    "${output}")"
  if [[ -n "${violations}" ]]
  then
    echo "Dependencies with denied licences:"
    echo "${violations}"
    exit 1
  fi
  if ((status != 0))
  then
    cat "${stderr}"
    exit "${status}"
  fi
  count="$(jq length "${output}")"
  echo "${label}: No denied licences found in ${count} dependencies."
}

check_licenses Non-Swift git \
  -c pkgs.ecosystems=cargo \
  -c pkgs.ecosystems=docker \
  -c pkgs.ecosystems=rubygems \
  -c pkgs.ecosystems=github-actions \
  -c pkgs.ecosystems=npm \
  -c pkgs.ecosystems=pypi \
  pkgs licenses

# Keep Swift's filtered snapshots separate from the other ecosystems.
# Include transitive dependencies and Xcode lockfiles without a Package.swift.
GIT_PKGS_DB="${RUNNER_TEMP}/git-pkgs/swift.db" \
  check_licenses Swift git -c pkgs.ecosystems=swift pkgs licenses --dependencies=all
