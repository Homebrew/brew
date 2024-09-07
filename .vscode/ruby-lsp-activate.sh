#!/bin/bash
HOMEBREW_PREFIX="$(cd "$(dirname "$0")"/../ && pwd)"

"${HOMEBREW_PREFIX}/bin/brew" install-bundler-gems --add-groups=style,typecheck,vscode >/dev/null 2>&1

export PATH="${HOMEBREW_PREFIX}/Library/Homebrew/vendor/portable-ruby/current/bin:${PATH}"
export BUNDLE_WITH="style:typecheck:vscode"
