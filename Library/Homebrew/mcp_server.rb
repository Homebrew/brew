# typed: strict
# frozen_string_literal: true

# This is a standalone Ruby script as MCP servers need a faster startup time
# than a normal Homebrew Ruby command allows.
require_relative "standalone"
require "json"
require "stringio"

module Homebrew
  # Provides a Model Context Protocol (MCP) server for Homebrew.
  # See https://modelcontextprotocol.io/introduction for more information.
  #
  # https://modelcontextprotocol.io/docs/tools/inspector is useful for testing.
  class McpServer
    HOMEBREW_BREW_FILE = T.let(ENV.fetch("HOMEBREW_BREW_FILE").freeze, String)
    HOMEBREW_VERSION = T.let(ENV.fetch("HOMEBREW_VERSION").freeze, String)
    JSON_RPC_VERSION = T.let("2.0", String)
    MCP_PROTOCOL_VERSION = T.let("2025-03-26", String)
    ERROR_CODE = T.let(-32601, Integer)

    SERVER_INFO = T.let({
      name:    "brew-mcp-server",
      version: HOMEBREW_VERSION,
    }.freeze, T::Hash[Symbol, String])

    FORMULA_OR_CASK_PROPERTIES = T.let({
      formula_or_cask: {
        type:        "string",
        description: "Formula or cask name",
      },
    }.freeze, T::Hash[Symbol, T.anything])

    # NOTE: Cursor (as of June 2025) will only query/use a maximum of 40 tools.
    TOOLS = T.let({
      search:    {
        name:        "search",
        description: "Perform a substring search of cask tokens and formula names for <text>. " \
                     "If <text> is flanked by slashes, it is interpreted as a regular expression.",
        command:     "brew search",
        inputSchema: {
          type:       "object",
          properties: {
            text_or_regex: {
              type:        "string",
              description: "Text or regex to search for",
            },
          },
        },
        required:    ["text_or_regex"],
      },
      info:      {
        name:        "info",
        description: "Display brief statistics for your Homebrew installation. " \
                     "If a <formula> or <cask> is provided, show summary of information about it.",
        command:     "brew info",
        inputSchema: { type: "object", properties: FORMULA_OR_CASK_PROPERTIES },
      },
      install:   {
        name:        "install",
        description: "Install a <formula> or <cask>.",
        command:     "brew install",
        inputSchema: { type: "object", properties: FORMULA_OR_CASK_PROPERTIES },
        required:    ["formula_or_cask"],
      },
      update:    {
        name:        "update",
        description: "Fetch the newest version of Homebrew and all formulae from GitHub using `git` and " \
                     "perform any necessary migrations.",
        command:     "brew update",
        inputSchema: { type: "object", properties: {} },
      },
      upgrade:   {
        name:        "upgrade",
        description: "Upgrade outdated casks and outdated, unpinned formulae using the same options they were " \
                     "originally installed with, plus any appended brew formula options. If <cask> or <formula> " \
                     "are specified, upgrade only the given <cask> or <formula> kegs (unless they are pinned).",
        command:     "brew upgrade",
        inputSchema: { type: "object", properties: FORMULA_OR_CASK_PROPERTIES },
      },
      uninstall: {
        name:        "uninstall",
        description: "Uninstall a <formula> or <cask>.",
        command:     "brew uninstall",
        inputSchema: { type: "object", properties: FORMULA_OR_CASK_PROPERTIES },
        required:    ["formula_or_cask"],
      },
      list:      {
        name:        "list",
        description: "List all installed formulae and casks. " \
                     "If <formula> is provided, summarise the paths within its current keg. " \
                     "If <cask> is provided, list its artifacts.",
        command:     "brew list",
        inputSchema: { type: "object", properties: FORMULA_OR_CASK_PROPERTIES },
      },
      config:    {
        name:        "config",
        description: "Show Homebrew and system configuration info useful for debugging. " \
                     "If you file a bug report, you will be required to provide this information.",
        command:     "brew config",
        inputSchema: { type: "object", properties: {} },
      },
      doctor:    {
        name:        "doctor",
        description: "Check your system for potential problems. Will exit with a non-zero status " \
                     "if any potential problems are found. " \
                     "Please note that these warnings are just used to help the Homebrew maintainers " \
                     "with debugging if you file an issue. If everything you use Homebrew for " \
                     "is working fine: please don't worry or file an issue; just ignore this.",
        command:     "brew doctor",
        inputSchema: { type: "object", properties: {} },
      },
      commands:  {
        name:        "commands",
        description: "Show lists of built-in and external commands.",
        command:     "brew commands",
        inputSchema: { type: "object", properties: {} },
      },
      help:      {
        name:        "help",
        description: "Outputs the usage instructions for `brew` <command>.",
        command:     "brew help",
        inputSchema: {
          type:       "object",
          properties: {
            command: {
              type:        "string",
              description: "Command to get help for",
            },
          },
        },
      },
    }.freeze, T::Hash[Symbol, T::Hash[Symbol, T.anything]])

    sig { params(stdin: T.any(IO, StringIO), stdout: T.any(IO, StringIO), stderr: T.any(IO, StringIO)).void }
    def initialize(stdin: $stdin, stdout: $stdout, stderr: $stderr)
      @debug_logging = T.let(ARGV.include?("--debug") || ARGV.include?("-d"), T::Boolean)
      @ping_switch = T.let(ARGV.include?("--ping"), T::Boolean)
      @stdin = T.let(stdin, T.any(IO, StringIO))
      @stdout = T.let(stdout, T.any(IO, StringIO))
      @stderr = T.let(stderr, T.any(IO, StringIO))
    end

    sig { returns(T::Boolean) }
    def debug_logging? = @debug_logging

    sig { returns(T::Boolean) }
    def ping_switch? = @ping_switch

    sig { void }
    def run
      @stderr.puts "==> Started Homebrew MCP server..."

      loop do
        input = if ping_switch?
          { jsonrpc: JSON_RPC_VERSION, id: 1, method: "ping" }.to_json
        else
          @stdin.gets
        end
        next if input.nil? || input.strip.empty?

        request = JSON.parse(input)
        debug("Request: #{JSON.pretty_generate(request)}")

        response = handle_request(request)
        if response.nil?
          debug("Response: nil")
          next
        end

        debug("Response: #{JSON.pretty_generate(response)}")
        output = JSON.dump(response).strip
        @stdout.puts(output)
        @stdout.flush

        break if ping_switch?
      end
    rescue Interrupt
      exit 0
    rescue => e
      log("Error: #{e.message}")
      exit 1
    end

    sig { params(text: String).void }
    def debug(text)
      return unless debug_logging?

      log(text)
    end

    sig { params(text: String).void }
    def log(text)
      @stderr.puts(text)
      @stderr.flush
    end

    sig { params(request: T::Hash[String, T.untyped]).returns(T.nilable(T::Hash[Symbol, T.anything])) }
    def handle_request(request)
      id = request["id"]
      return if id.nil?

      case request["method"]
      when "initialize"
        respond_result(id, {
          protocolVersion: MCP_PROTOCOL_VERSION,
          capabilities:    {
            tools:     { listChanged: false },
            prompts:   {},
            resources: {},
            logging:   {},
            roots:     {},
          },
          serverInfo:      SERVER_INFO,
        })
      when "resources/list"
        respond_result(id, { resources: [] })
      when "resources/templates/list"
        respond_result(id, { resourceTemplates: [] })
      when "prompts/list"
        respond_result(id, { prompts: [] })
      when "ping"
        respond_result(id)
      when "get_server_info"
        respond_result(id, SERVER_INFO)
      when "logging/setLevel"
        @debug_logging = request["params"]["level"] == "debug"
        respond_result(id)
      when "notifications/initialized", "notifications/cancelled"
        respond_result
      when "tools/list"
        respond_result(id, { tools: TOOLS.values })
      when "tools/call"
        if (tool = TOOLS.fetch(request["params"]["name"].to_sym, nil))
          require "shellwords"

          arguments = request["params"]["arguments"]
          argument = arguments.fetch("formula_or_cask", "")
          argument = arguments.fetch("text_or_regex", "") if argument.strip.empty?
          argument = arguments.fetch("command", "") if argument.strip.empty?
          argument = nil if argument.strip.empty?
          brew_command = T.cast(tool.fetch(:command), String)
                          .delete_prefix("brew ")
          full_command = [HOMEBREW_BREW_FILE, brew_command, argument].compact
                                                                     .map { |arg| Shellwords.escape(arg) }
                                                                     .join(" ")
          output = `#{full_command} 2>&1`.strip
          respond_result(id, { content: [{ type: "text", text: output }] })
        else
          respond_error(id, "Unknown tool")
        end
      else
        respond_error(id, "Method not found")
      end
    end

    sig {
      params(id:     T.nilable(Integer),
             result: T::Hash[Symbol, T.anything]).returns(T.nilable(T::Hash[Symbol, T.anything]))
    }
    def respond_result(id = nil, result = {})
      return if id.nil?

      { jsonrpc: JSON_RPC_VERSION, id:, result: }
    end

    sig { params(id: T.nilable(Integer), message: String).returns(T::Hash[Symbol, T.anything]) }
    def respond_error(id, message)
      { jsonrpc: JSON_RPC_VERSION, id:, error: { code: ERROR_CODE, message: } }
    end
  end
end
