# Documentation defined in Library/Homebrew/cmd/as-console-user.rb

# HOMEBREW_LIBRARY is set by brew.sh.
# shellcheck disable=SC1091,SC2154
source "${HOMEBREW_LIBRARY}/Homebrew/utils/as_user.sh"

homebrew-as-console-user() {
  homebrew-as-user as-console-user "$@"
}
