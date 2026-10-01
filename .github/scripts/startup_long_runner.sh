#!/bin/bash
# Validates runtime context, configures the GitHub Actions long runner from RUNNER_JITCONFIG, then starts it.
set -euo pipefail

RUNNER_DIRECTORY="${HOME}/actions-runner"

if [[ "$(id -un)" != "linuxbrew" ]]
then
  echo "Startup script run as incorrect user." >&2
  exit 1
fi

if [[ -f "${RUNNER_DIRECTORY}/.runner" ]]
then
  echo "Runner already configured, starting..."
  exec "${RUNNER_DIRECTORY}/run.sh"
fi

if [[ -z "${RUNNER_JITCONFIG:-}" ]]
then
  echo "Not configuring runner: missing RUNNER_JITCONFIG." >&2
  exit 1
fi

echo "Configuring long runner..."

cd "${RUNNER_DIRECTORY}"

jitconfig_json=$(printf '%s' "${RUNNER_JITCONFIG}" | base64 -d) || {
  echo "Failed to decode RUNNER_JITCONFIG: invalid base64 data." >&2
  exit 1
}

if ! jq -e 'type == "object"' <<<"${jitconfig_json}" >/dev/null
then
  echo "Failed to parse RUNNER_JITCONFIG: expected a JSON object." >&2
  exit 1
fi

config_files=$(jq -er 'keys[]' <<<"${jitconfig_json}") || {
  echo "Failed to parse RUNNER_JITCONFIG: could not list config keys." >&2
  exit 1
}

while IFS= read -r config_file
do
  if [[ "${config_file}" != "$(basename "${config_file}")" || "${config_file:0:1}" != "." ]]
  then
    echo "Invalid file name in JIT config: ${config_file}" >&2
    continue
  fi

  jq -er --arg key "${config_file}" '.[$key]' <<<"${jitconfig_json}" | base64 -d | install -m 600 /dev/stdin "${config_file}"
done <<<"${config_files}"

echo "GITHUB_ACTIONS_HOMEBREW_SELF_HOSTED=1" >.env

echo "Runner configured."

exec ./run.sh
