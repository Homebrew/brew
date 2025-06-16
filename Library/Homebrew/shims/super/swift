#!/bin/bash

# Ensure we use Swift's clang when performing Swift builds.

export CC="clang"
export CXX="clang++"

# swift_clang isn't a shim but is used to ensure the cc shim
# points to the compiler inside the swift keg
export HOMEBREW_CC="swift_clang"
export HOMEBREW_CXX="swift_clang++"

# HOMEBREW_OPT is set by extend/ENV/super.rb
# shellcheck disable=SC2154
exec "${HOMEBREW_OPT}/swift/bin/${0##*/}" "$@"
