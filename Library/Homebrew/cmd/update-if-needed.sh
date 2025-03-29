# Documentation defined in Library/Homebrew/cmd/update-if-needed.rb

homebrew-update-if-needed() {
  export HOMEBREW_AUTO_UPDATE_COMMAND="1"
  auto-update "$@"
}
