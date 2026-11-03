# typed: strict
# frozen_string_literal: true

# This is a standalone Ruby script as MCP servers need a faster startup time
# than a normal Homebrew Ruby command allows. Only Ruby's standard library is
# loaded here, so ActiveSupport extensions such as `exclude?` and `blank?`
# are unavailable.
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
    JSON_RPC_VERSION = "2.0"
    MCP_PROTOCOL_VERSION = "2025-06-18"
    # Earlier revisions a client may request; the tools below are valid for all of them.
    SUPPORTED_PROTOCOL_VERSIONS = T.let([MCP_PROTOCOL_VERSION, "2025-03-26"].freeze, T::Array[String])
    PARSE_ERROR_CODE = -32700
    INVALID_REQUEST_CODE = -32600
    METHOD_NOT_FOUND_CODE = -32601
    INVALID_PARAMS_CODE = -32602
    PACKAGE_TYPES = %w[formula cask].freeze

    # Reject inline `cask ... do`/`cask(...) {}` blocks the cask loader would eval as Ruby.
    INLINE_CASK_DSL_REGEX = /\A\s*cask\s*['"(]/

    SERVER_INFO = T.let({
      name:    "brew-mcp-server",
      version: HOMEBREW_VERSION,
    }.freeze, T::Hash[Symbol, String])

    PACKAGE_TYPE_PROPERTY = T.let({
      type:        "string",
      enum:        PACKAGE_TYPES,
      description: "Only consider formulae or only casks",
    }.freeze, T::Hash[Symbol, T.anything])

    FORMULA_OR_CASK_PROPERTIES = T.let({
      formula_or_cask: {
        type:        "string",
        description: "Formula or cask name",
      },
      package_type:    PACKAGE_TYPE_PROPERTY,
    }.freeze, T::Hash[Symbol, T.anything])

    # Hints for clients about what a tool does, see
    # https://modelcontextprotocol.io/specification/2025-06-18/server/tools#tool-annotations
    READ_ONLY_ANNOTATIONS = T.let({
      readOnlyHint:    true,
      destructiveHint: false,
      idempotentHint:  true,
      openWorldHint:   false,
    }.freeze, T::Hash[Symbol, T::Boolean])

    # Read-only tools that may also reach the network, e.g. to refresh the API cache.
    READ_ONLY_ONLINE_ANNOTATIONS = T.let(READ_ONLY_ANNOTATIONS.merge(openWorldHint: true).freeze,
                                         T::Hash[Symbol, T::Boolean])

    # NOTE: Cursor (as of June 2025) will only query/use a maximum of 40 tools.
    TOOLS = T.let({
      search:    {
        name:        "search",
        title:       "Search formulae and casks",
        description: "Perform a substring search of cask tokens and formula names for <text>. " \
                     "If <text> is flanked by slashes, it is interpreted as a regular expression.",
        inputSchema: {
          type:       "object",
          properties: {
            text_or_regex: {
              type:        "string",
              description: "Text or regex to search for",
            },
            package_type:  PACKAGE_TYPE_PROPERTY,
          },
          required:   ["text_or_regex"],
        },
        annotations: READ_ONLY_ONLINE_ANNOTATIONS,
      },
      info:      {
        name:        "info",
        title:       "Formula or cask information",
        description: "Display brief statistics for your Homebrew installation. " \
                     "If a <formula> or <cask> is provided, show summary of information about it.",
        inputSchema: { type: "object", properties: FORMULA_OR_CASK_PROPERTIES },
        annotations: READ_ONLY_ONLINE_ANNOTATIONS,
      },
      install:   {
        name:        "install",
        title:       "Install a formula or cask",
        description: "Install a <formula> or <cask>.",
        inputSchema: { type: "object", properties: FORMULA_OR_CASK_PROPERTIES, required: ["formula_or_cask"] },
        annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: true, openWorldHint: true },
      },
      update:    {
        name:        "update",
        title:       "Update Homebrew",
        description: "Fetch the newest version of Homebrew and all formulae from GitHub using `git` and " \
                     "perform any necessary migrations.",
        inputSchema: { type: "object", properties: {} },
        annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: true, openWorldHint: true },
      },
      upgrade:   {
        name:        "upgrade",
        title:       "Upgrade outdated packages",
        description: "Upgrade outdated, unpinned packages using the same options they were originally " \
                     "installed with, plus any appended brew formula options. If <cask> or <formula> " \
                     "are specified, upgrade only the given <cask> or <formula> (unless they are pinned).",
        inputSchema: { type: "object", properties: FORMULA_OR_CASK_PROPERTIES },
        annotations: { readOnlyHint: false, destructiveHint: true, idempotentHint: true, openWorldHint: true },
      },
      uninstall: {
        name:        "uninstall",
        title:       "Uninstall a formula or cask",
        description: "Uninstall a <formula> or <cask>.",
        inputSchema: { type: "object", properties: FORMULA_OR_CASK_PROPERTIES, required: ["formula_or_cask"] },
        annotations: { readOnlyHint: false, destructiveHint: true, idempotentHint: true, openWorldHint: false },
      },
      list:      {
        name:        "list",
        title:       "List installed packages",
        description: "List all installed formulae and casks. " \
                     "If <formula> is provided, summarise the paths within its current keg. " \
                     "If <cask> is provided, list its artifacts.",
        inputSchema: { type: "object", properties: FORMULA_OR_CASK_PROPERTIES },
        annotations: READ_ONLY_ANNOTATIONS,
      },
      config:    {
        name:        "config",
        title:       "Homebrew configuration",
        description: "Show Homebrew and system configuration info useful for debugging. " \
                     "If you file a bug report, you will be required to provide this information.",
        inputSchema: { type: "object", properties: {} },
        annotations: READ_ONLY_ANNOTATIONS,
      },
      doctor:    {
        name:        "doctor",
        title:       "Check for problems",
        description: "Check your system for potential problems. Will exit with a non-zero status " \
                     "if any potential problems are found. " \
                     "Please note that these warnings are just used to help the Homebrew maintainers " \
                     "with debugging if you file an issue. If everything you use Homebrew for " \
                     "is working fine: please don't worry or file an issue; just ignore this.",
        inputSchema: { type: "object", properties: {} },
        annotations: READ_ONLY_ANNOTATIONS,
      },
      typecheck: {
        name:        "typecheck",
        title:       "Typecheck Homebrew's code",
        description: "Check for typechecking errors using Sorbet.",
        inputSchema: { type: "object", properties: {} },
        annotations: READ_ONLY_ANNOTATIONS,
      },
      style:     {
        name:        "style",
        title:       "Check or fix code style",
        description: "Check formulae or files for conformance to Homebrew style guidelines.",
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
        annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: true, openWorldHint: false },
      },
      tests:     {
        name:        "tests",
        title:       "Run Homebrew's tests",
        description: "Run Homebrew's unit and integration tests.",
        inputSchema: {
          type:       "object",
          properties: {
            only:      {
              type:        "string",
              description: "Specific tests to run (comma-separated) e.g. for `<file>_spec.rb` pass `<file>`. " \
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
        annotations: READ_ONLY_ONLINE_ANNOTATIONS,
      },
      commands:  {
        name:        "commands",
        title:       "List brew commands",
        description: "Show lists of built-in and external commands.",
        inputSchema: { type: "object", properties: {} },
        annotations: READ_ONLY_ANNOTATIONS,
      },
      help:      {
        name:        "help",
        title:       "Show command usage",
        description: "Outputs the usage instructions for `brew` <command>.",
        inputSchema: {
          type:       "object",
          properties: {
            command: {
              type:        "string",
              description: "Command to get help for",
            },
          },
        },
        annotations: READ_ONLY_ANNOTATIONS,
      },
    }.freeze, T::Hash[Symbol, T::Hash[Symbol, T.anything]])

    sig { params(stdin: T.any(IO, StringIO), stdout: T.any(IO, StringIO), stderr: T.any(IO, StringIO)).void }
    def initialize(stdin: $stdin, stdout: $stdout, stderr: $stderr)
      @debug_logging = T.let(ARGV.include?("--debug") || ARGV.include?("-d"), T::Boolean)
      @ping_switch = T.let(ARGV.include?("--ping"), T::Boolean)
      @stdin = stdin
      @stdout = stdout
      @stderr = stderr
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

        response = begin
          request = JSON.parse(input)
          debug("Request: #{JSON.pretty_generate(request)}")

          if request.is_a?(Hash)
            handle_request(request)
          else
            respond_error(nil, INVALID_REQUEST_CODE, "Invalid request")
          end
        rescue JSON::ParserError
          respond_error(nil, PARSE_ERROR_CODE, "Parse error")
        end
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
      return respond_error(nil, INVALID_REQUEST_CODE, "Invalid request") if !id.is_a?(Numeric) && !id.is_a?(String)

      params = request["params"] || {}
      return respond_error(id, INVALID_PARAMS_CODE, "Invalid params") unless params.is_a?(Hash)

      case request["method"]
      when "initialize"
        requested_version = params["protocolVersion"]
        protocol_version = if SUPPORTED_PROTOCOL_VERSIONS.include?(requested_version)
          requested_version
        else
          MCP_PROTOCOL_VERSION
        end
        respond_result(id, {
          protocolVersion: protocol_version,
          capabilities:    {
            tools:     { listChanged: false },
            prompts:   {},
            resources: {},
            logging:   {},
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
      when "logging/setLevel"
        @debug_logging = params["level"] == "debug"
        respond_result(id)
      when "notifications/initialized", "notifications/cancelled"
        respond_result
      when "tools/list"
        respond_result(id, { tools: TOOLS.values })
      when "tools/call"
        respond_to_tools_call(id, params)
      else
        respond_error(id, METHOD_NOT_FOUND_CODE, "Method not found")
      end
    end

    sig {
      params(id:     T.any(Numeric, String),
             params: T::Hash[String, T.untyped]).returns(T.nilable(T::Hash[Symbol, T.anything]))
    }
    def respond_to_tools_call(id, params)
      tool_name = params["name"].to_s.to_sym
      return respond_error(id, INVALID_PARAMS_CODE, "Unknown tool") unless TOOLS.key?(tool_name)

      arguments = params["arguments"]
      arguments = {} if arguments.nil?
      return respond_error(id, INVALID_PARAMS_CODE, "Invalid tool arguments") unless arguments.is_a?(Hash)

      # Invalid arguments are tool errors rather than protocol errors so that
      # the client's model can correct them.
      # An empty name is a mistake rather than a request for every package:
      # `upgrade` without a name upgrades everything.
      if arguments.values_at("formula_or_cask", "text_or_regex").any? { |name| !name.nil? && name.to_s.strip.empty? }
        return respond_result(id, tool_result("Empty formula, cask or search argument", error: true))
      end

      package_type = arguments["package_type"]
      if package_type && PACKAGE_TYPES.none?(package_type)
        return respond_result(id, tool_result("Invalid package_type argument: expected formula or cask", error: true))
      end

      command_args = tool_command_arguments(tool_name, arguments)
      if command_args.any? { |argument| INLINE_CASK_DSL_REGEX.match?(argument) }
        return respond_result(id, tool_result("Invalid formula or cask argument", error: true))
      end

      require "open3"

      meta = params["_meta"]
      progress_token = meta["progressToken"] if meta.is_a?(Hash)
      buffer_size = 4096 # 4KB
      progress = T.let(0, Integer)
      done = T.let(false, T::Boolean)
      new_output = T.let(false, T::Boolean)
      output = +""

      Open3.popen2e(HOMEBREW_BREW_FILE, tool_name.to_s, *command_args) do |stdin, io, wait|
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

        respond_result(id, tool_result(output, error: !wait.value.success?))
      end
    end

    sig { params(tool_name: Symbol, arguments: T::Hash[String, T.untyped]).returns(T::Array[String]) }
    def tool_command_arguments(tool_name, arguments)
      flags = []
      names = []
      case tool_name
      when :style
        flags << "--fix" if arguments["fix"]
        flags << "--changed" if arguments["changed"]
        names = arguments["files"].to_s.split
      when :tests
        only_arguments = arguments["only"].to_s.strip
        flags << "--only=#{only_arguments}" unless only_arguments.empty?
        flags << "--fail-fast" if arguments["fail_fast"]
        flags << "--changed" if arguments["changed"]
        flags << "--online" if arguments["online"]
      when :search, :info, :install, :upgrade, :uninstall, :list
        package_type = arguments["package_type"]
        flags << "--#{package_type}" if package_type
        name_argument = (tool_name == :search) ? "text_or_regex" : "formula_or_cask"
        names = [arguments[name_argument]]
      when :help
        # `brew help` takes command names such as `--prefix` and does not
        # understand `--`, so its argument is passed through unchanged.
        return [arguments["command"].to_s].reject(&:empty?)
      end

      names = names.map(&:to_s).reject(&:empty?)
      return flags if names.empty?

      # `--` stops names such as `--HEAD` or `--zap` being parsed as options.
      [*flags, "--", *names]
    end

    sig {
      params(id:     T.nilable(T.any(Numeric, String)),
             result: T::Hash[Symbol, T.anything]).returns(T.nilable(T::Hash[Symbol, T.anything]))
    }
    def respond_result(id = nil, result = {})
      return if id.nil?

      { jsonrpc: JSON_RPC_VERSION, id:, result: }
    end

    sig { params(text: String, error: T::Boolean).returns(T::Hash[Symbol, T.anything]) }
    def tool_result(text, error:)
      { content: [{ type: "text", text: }], isError: error }
    end

    sig {
      params(id:      T.nilable(T.any(Numeric, String)),
             code:    Integer,
             message: String).returns(T::Hash[Symbol, T.anything])
    }
    def respond_error(id, code, message)
      { jsonrpc: JSON_RPC_VERSION, id:, error: { code:, message: } }
    end
  end
end
