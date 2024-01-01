#!/bin/bash
set -euo pipefail

homebrew_pkg_user_plist="/var/tmp/.homebrew_pkg_user.plist"
if [[ -f "${homebrew_pkg_user_plist}" ]] && [[ -n $(defaults read "${homebrew_pkg_user_plist}" HOMEBREW_PKG_USER) ]]
then
  exit 0
fi

homebrew_pkg_user=$(echo "show State:/Users/ConsoleUser" | scutil | awk '/Name :/ { print $3 }')
if [[ "${homebrew_pkg_user}" =~ _mbsetupuser|loginwindow|root ]] || [[ -z "${homebrew_pkg_user}" ]]
then
  echo "No valid user for Homebrew installation. Log in before install or specify an install user."
  exit 1
else
  exit 0
fi
