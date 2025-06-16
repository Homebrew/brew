#!/bin/bash

export HOMEBREW_CCCFG="O${HOMEBREW_CCCFG}"

ant=/usr/bin/ant
# HOMEBREW_BREW_FILE is set by bin/brew
# shellcheck disable=SC2154
[[ -x "${ant}" ]] || ant="$("${HOMEBREW_BREW_FILE}" --prefix ant)/bin/ant"
exec "${ant}" "$@"
