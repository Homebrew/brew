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
      typecheck: {
        name:        "typecheck",
        description: "Check for typechecking errors using Sorbet.",
        command:     "brew typecheck",
        inputSchema: { type: "object", properties: {} },
      },
      style:     {
        name:        "style",
        description: "Check formulae or files for conformance to Homebrew style guidelines.",
        command:     "brew style",
        inputSchema: {
          type:       "object",
          properties: {
            fix:     {
              type:        "boolean",
              description: "Fix style violations automatically using RuboCop's auto-correct feature",
            },
            files:   {
              type:        "string",
              description: "Specific files to check (space-separated)",
            },
            changed: {
              type:        "boolean",
              description: "Only check files that were changed from the `main` branch",
            },
          },
        },
      },
      tests:     {
        name:        "tests",
        description: "Run Homebrew's unit and integration tests.",
        command:     "brew tests",
        inputSchema: {
          type:       "object",
          properties: {
            only:      {
              type:        "string",
              description: "Specific tests to run (comma-seperated) e.g. for `<file>_spec.rb` pass `<file>`. " \
                           "Appending `:<line_number>` will start at a specific line",
            },
            fail_fast: {
              type:        "boolean",
              description: "Exit early on the first failing test",
            },
            changed:   {
              type:        "boolean",
              description: "Only runs tests on files that were changed from the `main` branch",
            },
            online:    {
              type:        "boolean",
              description: "Run online tests",
            },
          },
        },
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
          break if @stdin.eof?

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
        respond_to_tools_call(id, request)
      else
        respond_error(id, "Method not found")
      end
    end

    sig { params(id: Integer, request: T::Hash[String, T.untyped]).returns(T.nilable(T::Hash[Symbol, T.anything])) }
    def respond_to_tools_call(id, request)
      tool_name = request["params"]["name"].to_sym
      tool = TOOLS.fetch tool_name do
        return respond_error(id, "Unknown tool")
      end

      require "open3"

      command_args = tool_command_arguments(tool_name, request["params"]["arguments"])
      progress_token = request["params"]["_meta"]&.fetch("progressToken", nil)
      brew_command = T.cast(tool.fetch(:command), String)
                      .delete_prefix("brew ")
      buffer_size = 4096 # 4KB
      progress = T.let(0, Integer)
      done = T.let(false, T::Boolean)
      new_output = T.let(false, T::Boolean)
      output = +""

      text = Open3.popen2e(HOMEBREW_BREW_FILE, brew_command, *command_args) do |stdin, io, _wait|
        stdin.close

        reader = Thread.new do
          loop do
            output << io.readpartial(buffer_size)
            progress += 1
            new_output = true
          end
        rescue EOFError
          nil
        ensure
          done = true
        end

        until done
          break unless progress_token

          sleep 1
          next unless new_output

          response = {
            jsonrpc: JSON_RPC_VERSION,
            method:  "notifications/progress",
            params:  { progressToken: progress_token, progress: },
          }
          progress_output = JSON.dump(response).strip
          @stdout.puts(progress_output)
          @stdout.flush

          new_output = false
        end

        reader.join

        output
      end

      respond_result(id, { content: [{ type: "text", text: }] })
    end

    sig { params(tool_name: Symbol, arguments: T::Hash[String, T.untyped]).returns(T::Array[String]) }
    def tool_command_arguments(tool_name, arguments)
      require "shellwords"

      case tool_name
      when :style
        style_args = []
        style_args << "--fix" if arguments["fix"]
        style_args << "--changed" if arguments["changed"]
        file_arguments = arguments.fetch("files", "").strip.split
        style_args.concat(file_arguments) unless file_arguments.empty?
        style_args
      when :tests
        tests_args = []
        only_arguments = arguments.fetch("only", "").strip
        tests_args << "--only=#{only_arguments}" unless only_arguments.empty?
        tests_args << "--fail-fast" if arguments["fail_fast"]
        tests_args << "--changed" if arguments["changed"]
        tests_args << "--online" if arguments["online"]
        tests_args
      when :search
        [arguments["text_or_regex"]]
      when :help
        [arguments["command"]]
      else
        [arguments["formula_or_cask"]]
      end.compact
        .reject(&:empty?)
        .map { |arg| Shellwords.escape(arg) }
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
