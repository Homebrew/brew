#!/bin/bash

export HOMEBREW_RDBG="1"

HOMEBREW_PORTABLE_RUBY_BIN="$(cd "$(dirname "$0")"/../../ && pwd)/vendor/portable-ruby/current/bin/"
exec "${HOMEBREW_PORTABLE_RUBY_BIN}"rdbg "$@"
