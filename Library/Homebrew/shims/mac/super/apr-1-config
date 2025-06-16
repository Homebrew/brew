#!/bin/bash

# HOMEBREW_CCCFG and HOMEBREW_SDKROOT are set by extend/ENV/super.rb
# shellcheck disable=SC2154
if [[ "${HOMEBREW_CCCFG}" = *a* ]]
then
  case "$1" in
    --cc) echo "cc" ;;
    --cpp) echo "cpp" ;;
    --includedir) echo "${HOMEBREW_SDKROOT}/usr/include/apr-1" ;;
    --includes) echo "-isystem${HOMEBREW_SDKROOT}/usr/include/apr-1" ;;
    --apr-libtool) echo "glibtool" ;;
    *)
      exec xcrun apr-1-config "$@"
      ;;
  esac
else
  exec /usr/bin/apr-1-config "$@"
fi
