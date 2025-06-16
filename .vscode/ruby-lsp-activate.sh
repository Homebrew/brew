#!/bin/bash
if [[ -n "${BASH_SOURCE[0]}" ]]; then
    SCRIPT_PATH="${BASH_SOURCE[0]}"
elif [[ -n "${ZSH_VERSION}" ]]; then
    SCRIPT_PATH="${(%):-%x}"
else
    SCRIPT_PATH="$0"
fi
HOMEBREW_PREFIX="$(cd "$(dirname "${SCRIPT_PATH}")"/../ && pwd)"

"${HOMEBREW_PREFIX}/bin/brew" install-bundler-gems --add-groups=style,typecheck,vscode >/dev/null 2>&1

export PATH="${HOMEBREW_PREFIX}/Library/Homebrew/vendor/portable-ruby/current/bin:${PATH}"
export BUNDLE_WITH="style:typecheck:vscode"
