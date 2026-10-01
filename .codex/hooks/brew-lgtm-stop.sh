#!/bin/bash

cd "$(dirname "$0")/../.." || {
  printf '%s\n' '{"decision":"block","reason":"Failed to cd to the repository root before running ./bin/brew lgtm."}'
  exit 0
}

if ./bin/brew lgtm >&2
then
  printf '%s\n' '{"continue":true}'
else
  printf '%s\n' '{"decision":"block","reason":"./bin/brew lgtm failed; review the output above and fix it before stopping."}'
fi
