# typed: strong
# frozen_string_literal: true

require "abstract_command"
require "shell_command"

module Homebrew
  module Cmd
    class McpServerCmd < AbstractCommand
      # This is a shell command as MCP servers need a faster startup time
      # than a normal Homebrew Ruby command allows.
      include ShellCommand

      cmd_args do
        description <<~EOS
          Starts the Homebrew MCP (Model Context Protocol) server.
        EOS
        switch "-d", "--debug", description: "Enable debug logging to stderr."
        switch "--ping", description: "Start the server, act as if receiving a ping and then exit.", hidden: true
      end
    end
  end
end
