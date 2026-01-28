# Documentation defined in Library/Homebrew/cmd/mcp-server.rb

# This is a shell command as MCP servers need a faster startup time
# than a normal Homebrew Ruby command allows.

# HOMEBREW_LIBRARY is set by brew.sh
# HOMEBREW_BREW_FILE is set by extend/ENV/super.rb
# shellcheck disable=SC2154
homebrew-mcp-server() {
  source "${HOMEBREW_LIBRARY}/Homebrew/utils/ruby.sh"
  setup-ruby-path
  export HOMEBREW_VERSION
  "${HOMEBREW_RUBY_PATH}" "-r${HOMEBREW_LIBRARY}/Homebrew/mcp_server.rb" -e "Homebrew::McpServer.new.run" "$@"
}
