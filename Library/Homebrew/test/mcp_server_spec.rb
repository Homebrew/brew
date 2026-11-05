# typed: true
# frozen_string_literal: true

require "mcp_server"
require "stringio"
require "timeout"

RSpec.describe Homebrew::McpServer do
  let(:stdin) { StringIO.new }
  let(:stdout) { StringIO.new }
  let(:stderr) { StringIO.new }
  let(:server) { described_class.new(stdin:, stdout:, stderr:) }
  let(:jsonrpc) { Homebrew::McpServer::JSON_RPC_VERSION }
  let(:id) { Random.rand(1000) }
  let(:command_status) { instance_double(Process::Status, success?: true) }
  let(:command_waiter) { instance_double(Thread, value: command_status) }

  describe "#initialize" do
    it "sets debug_logging to false by default" do
      expect(server.debug_logging?).to be(false)
    end

    it "sets debug_logging to true if --debug is in ARGV" do
      stub_const("ARGV", ["--debug"])
      expect(server.debug_logging?).to be(true)
    end

    it "sets debug_logging to true if -d is in ARGV" do
      stub_const("ARGV", ["-d"])
      expect(server.debug_logging?).to be(true)
    end
  end

  describe "#debug and #log" do
    it "logs debug output when debug_logging is true" do
      stub_const("ARGV", ["--debug"])
      server.debug("foo")
      expect(stderr.string).to include("foo")
    end

    it "does not log debug output when debug_logging is false" do
      server.debug("foo")
      expect(stderr.string).to eq("")
    end

    it "logs to stderr" do
      server.log("bar")
      expect(stderr.string).to include("bar")
    end
  end

  describe "#handle_request" do
    it "responds to initialize method" do
      request = { "id" => id, "method" => "initialize" }
      result = server.handle_request(request)
      expect(result).to eq({
        jsonrpc:,
        id:,
        result:  {
          protocolVersion: Homebrew::McpServer::MCP_PROTOCOL_VERSION,
          capabilities:    {
            tools:     { listChanged: false },
            prompts:   {},
            resources: {},
            logging:   {},
          },
          serverInfo:      Homebrew::McpServer::SERVER_INFO,
        },
      })
    end

    it "echoes a supported protocol version requested by the client" do
      request = { "id" => id, "method" => "initialize", "params" => { "protocolVersion" => "2025-03-26" } }
      result = server.handle_request(request)
      expect(result.dig(:result, :protocolVersion)).to eq("2025-03-26")
    end

    it "answers an unsupported protocol version with its own" do
      request = { "id" => id, "method" => "initialize", "params" => { "protocolVersion" => "1999-01-01" } }
      result = server.handle_request(request)
      expect(result.dig(:result, :protocolVersion)).to eq(Homebrew::McpServer::MCP_PROTOCOL_VERSION)
    end

    it "responds to resources/list" do
      request = { "id" => id, "method" => "resources/list" }
      result = server.handle_request(request)
      expect(result).to eq({ jsonrpc:, id:, result: { resources: [] } })
    end

    it "responds to resources/templates/list" do
      request = { "id" => id, "method" => "resources/templates/list" }
      result = server.handle_request(request)
      expect(result).to eq({ jsonrpc:, id:, result: { resourceTemplates: [] } })
    end

    it "responds to prompts/list" do
      request = { "id" => id, "method" => "prompts/list" }
      result = server.handle_request(request)
      expect(result).to eq({ jsonrpc:, id:, result: { prompts: [] } })
    end

    it "responds to ping" do
      request = { "id" => id, "method" => "ping" }
      result = server.handle_request(request)
      expect(result).to eq({ jsonrpc:, id:, result: {} })
    end

    it "responds to ping with a string id" do
      request = { "id" => "abc", "method" => "ping" }
      result = server.handle_request(request)
      expect(result).to eq({ jsonrpc:, id: "abc", result: {} })
    end

    it "responds to ping with a non-integer numeric id" do
      request = { "id" => 1.5, "method" => "ping" }
      result = server.handle_request(request)
      expect(result).to eq({ jsonrpc:, id: 1.5, result: {} })
    end

    it "rejects a request whose id is neither a number nor a string" do
      request = { "id" => true, "method" => "ping" }
      result = server.handle_request(request)
      expect(result).to eq({
        jsonrpc:,
        id:      nil,
        error:   { message: "Invalid request", code: Homebrew::McpServer::INVALID_REQUEST_CODE },
      })
    end

    it "responds to logging/setLevel with debug" do
      request = { "id" => id, "method" => "logging/setLevel", "params" => { "level" => "debug" } }
      result = server.handle_request(request)
      expect(server.debug_logging?).to be(true)
      expect(result).to eq({ jsonrpc:, id:, result: {} })
    end

    it "responds to logging/setLevel with non-debug" do
      request = { "id" => id, "method" => "logging/setLevel", "params" => { "level" => "info" } }
      result = server.handle_request(request)
      expect(server.debug_logging?).to be(false)
      expect(result).to eq({ jsonrpc:, id:, result: {} })
    end

    it "responds to notifications/initialized" do
      request = { "id" => id, "method" => "notifications/initialized" }
      expect(server.handle_request(request)).to be_nil
    end

    it "responds to notifications/cancelled" do
      request = { "id" => id, "method" => "notifications/cancelled" }
      expect(server.handle_request(request)).to be_nil
    end

    it "responds to tools/list" do
      request = { "id" => id, "method" => "tools/list" }
      result = server.handle_request(request)
      expect(result[:result][:tools]).to match_array(Homebrew::McpServer::TOOLS.values)
    end

    it "advertises required arguments inside each tool's inputSchema" do
      request = { "id" => id, "method" => "tools/list" }
      tools = server.handle_request(request).dig(:result, :tools)
      required = tools.to_h { |tool| [tool[:name], tool.dig(:inputSchema, :required)] }
      expect(required).to include("search"    => ["text_or_regex"],
                                  "install"   => ["formula_or_cask"],
                                  "uninstall" => ["formula_or_cask"])
    end

    it "advertises only MCP tool fields" do
      request = { "id" => id, "method" => "tools/list" }
      tools = server.handle_request(request).dig(:result, :tools)
      expect(tools.map(&:keys).uniq).to eq([[:name, :title, :description, :inputSchema, :annotations]])
    end

    test_each_hash(Homebrew::McpServer::TOOLS) do |tool_name, tool_definition|
      it "responds to tools/call for #{tool_name}" do
        allow(Open3).to receive(:popen2e)
          .and_yield(StringIO.new, StringIO.new("output for #{tool_name}"), command_waiter)
        arguments = {}
        input_schema = tool_definition.fetch(:inputSchema)
        required_keys = case input_schema
        when Hash then Array(input_schema[:required])
        else []
        end
        required_keys.each do |required_key|
          arguments[required_key] = "dummy"
        end
        request = {
          "id"     => id,
          "method" => "tools/call",
          "params" => {
            "name"      => tool_name.to_s,
            "arguments" => arguments,
          },
        }
        result = server.handle_request(request)
        expect(result).to eq({
          jsonrpc: jsonrpc,
          id:      id,
          result:  { content: [{ type: "text", text: "output for #{tool_name}" }], isError: false },
        })
      end
    end

    it "rejects non-object tool arguments without spawning brew" do
      expect(Open3).not_to receive(:popen2e)
      request = {
        "id"     => id,
        "method" => "tools/call",
        "params" => { "name" => "upgrade", "arguments" => false },
      }
      result = server.handle_request(request)
      expect(result.dig(:error, :code)).to eq(Homebrew::McpServer::INVALID_PARAMS_CODE)
    end

    it "rejects an empty name without spawning brew" do
      expect(Open3).not_to receive(:popen2e)
      request = {
        "id"     => id,
        "method" => "tools/call",
        "params" => { "name" => "upgrade", "arguments" => { "formula_or_cask" => "" } },
      }
      result = server.handle_request(request)
      expect(result.dig(:result, :isError)).to be(true)
    end

    it "treats null tool arguments as an empty object" do
      allow(Open3).to receive(:popen2e)
        .and_yield(StringIO.new, StringIO.new("commands output"), command_waiter)
      request = {
        "id"     => id,
        "method" => "tools/call",
        "params" => { "name" => "commands", "arguments" => nil },
      }

      expect(server.handle_request(request)).to include(
        result: a_hash_including(content: [{ type: "text", text: "commands output" }]),
      )
    end

    it "passes tool arguments as argv when spawning brew" do
      expect(Open3).to receive(:popen2e)
        .with(Homebrew::McpServer::HOMEBREW_BREW_FILE, "search", "--", "visual studio;beta")
        .and_yield(StringIO.new, StringIO.new("output"), command_waiter)
      request = {
        "id"     => id,
        "method" => "tools/call",
        "params" => {
          "name"      => "search",
          "arguments" => { "text_or_regex" => "visual studio;beta" },
        },
      }

      server.handle_request(request)
    end

    it "passes package_type as a flag before the name separator" do
      expect(Open3).to receive(:popen2e)
        .with(Homebrew::McpServer::HOMEBREW_BREW_FILE, "info", "--cask", "--", "docker")
        .and_yield(StringIO.new, StringIO.new("output"), command_waiter)
      request = {
        "id"     => id,
        "method" => "tools/call",
        "params" => {
          "name"      => "info",
          "arguments" => { "formula_or_cask" => "docker", "package_type" => "cask" },
        },
      }

      server.handle_request(request)
    end

    test_each([nil, "", "install", "typecheck", "--prefix",
               *Commands::HOMEBREW_INTERNAL_COMMAND_ALIASES.keys]) do |command|
      it "passes the built-in help topic #{command.inspect} through without a separator" do
        expect(Open3).to receive(:popen2e)
          .with(Homebrew::McpServer::HOMEBREW_BREW_FILE, "help", *[command].reject { |name| name.to_s.empty? })
          .and_yield(StringIO.new, StringIO.new("output"), command_waiter)
        request = {
          "id"     => id,
          "method" => "tools/call",
          "params" => { "name" => "help", "arguments" => { "command" => command } },
        }

        server.handle_request(request)
      end
    end

    test_each(["external-command", "../brew", "/tmp/brew-command", "--", "--debug", "install --debug",
               "\0"]) do |command|
      it "rejects the help topic #{command.inspect} without spawning brew" do
        allow(Open3).to receive(:popen2e).and_raise("Spawning brew is not permitted")
        request = {
          "id"     => id,
          "method" => "tools/call",
          "params" => { "name" => "help", "arguments" => { "command" => command } },
        }

        expect(server.handle_request(request)).to eq({
          jsonrpc:,
          id:,
          result:  {
            content: [{ type: "text", text: "Invalid command argument: expected a built-in command" }],
            isError: true,
          },
        })
      end
    end

    it "ignores search text passed to a formula tool" do
      expect(Open3).to receive(:popen2e)
        .with(Homebrew::McpServer::HOMEBREW_BREW_FILE, "info")
        .and_yield(StringIO.new, StringIO.new("output"), command_waiter)
      request = {
        "id"     => id,
        "method" => "tools/call",
        "params" => { "name" => "info", "arguments" => { "text_or_regex" => "wget" } },
      }

      server.handle_request(request)
    end

    it "reports a failed command as a tool error and preserves its output" do
      allow(command_status).to receive(:success?).and_return(false)
      allow(Open3).to receive(:popen2e)
        .and_yield(StringIO.new, StringIO.new("command failed"), command_waiter)
      request = {
        "id"     => id,
        "method" => "tools/call",
        "params" => { "name" => "help", "arguments" => { "command" => "install" } },
      }

      expect(server.handle_request(request)).to eq({
        jsonrpc:,
        id:,
        result:  { content: [{ type: "text", text: "command failed" }], isError: true },
      })
    end

    it "rejects an inline cask definition argument without spawning brew" do
      expect(Open3).not_to receive(:popen2e)
      request = {
        "id"     => id,
        "method" => "tools/call",
        "params" => {
          "name"      => "info",
          "arguments" => { "formula_or_cask" => %Q(cask "evil" do\n  url "https://example.com"\nend) },
        },
      }
      result = server.handle_request(request)
      expect(result).to eq({
        jsonrpc:,
        id:,
        result:  { content: [{ type: "text", text: "Invalid formula or cask argument" }], isError: true },
      })
    end

    it "rejects an inline cask definition passed as search text" do
      expect(Open3).not_to receive(:popen2e)
      request = {
        "id"     => id,
        "method" => "tools/call",
        "params" => { "name" => "search", "arguments" => { "text_or_regex" => %Q(cask "evil" do\nend) } },
      }
      expect(server.handle_request(request).dig(:result, :isError)).to be(true)
    end

    it "rejects an invalid package_type without spawning brew" do
      expect(Open3).not_to receive(:popen2e)
      request = {
        "id"     => id,
        "method" => "tools/call",
        "params" => { "name" => "info", "arguments" => { "formula_or_cask" => "wget", "package_type" => "tap" } },
      }
      result = server.handle_request(request)
      expect(result.dig(:result, :isError)).to be(true)
    end

    it "responds to tools/call for unknown tool" do
      request = { "id" => id, "method" => "tools/call", "params" => { "name" => "not_a_tool", "arguments" => {} } }
      result = server.handle_request(request)
      expect(result).to eq({
        jsonrpc:,
        id:,
        error:   { message: "Unknown tool", code: Homebrew::McpServer::INVALID_PARAMS_CODE },
      })
    end

    it "responds to tools/call without params as an unknown tool" do
      request = { "id" => id, "method" => "tools/call" }
      result = server.handle_request(request)
      expect(result.dig(:error, :code)).to eq(Homebrew::McpServer::INVALID_PARAMS_CODE)
    end

    it "responds with error for unknown method" do
      request = { "id" => id, "method" => "not_a_method" }
      result = server.handle_request(request)
      expect(result).to eq({
        jsonrpc:,
        id:,
        error:   { message: "Method not found", code: Homebrew::McpServer::METHOD_NOT_FOUND_CODE },
      })
    end

    it "returns nil if id is nil" do
      request = { "method" => "initialize" }
      expect(server.handle_request(request)).to be_nil
    end
  end

  describe "#respond_result" do
    it "returns nil if id is nil" do
      expect(server.respond_result(nil, {})).to be_nil
    end

    it "returns a result hash if id is present" do
      result = server.respond_result(id, { foo: "bar" })
      expect(result).to eq({ jsonrpc:, id:, result: { foo: "bar" } })
    end
  end

  describe "#respond_error" do
    it "returns an error hash" do
      result = server.respond_error(id, Homebrew::McpServer::INVALID_PARAMS_CODE, "fail")
      expect(result).to eq({
        jsonrpc:,
        id:,
        error:   { message: "fail", code: Homebrew::McpServer::INVALID_PARAMS_CODE },
      })
    end
  end

  describe "#tool_command_arguments" do
    it "preserves search text as a single raw argv argument" do
      arguments = { "text_or_regex" => "visual studio;beta" }

      expect(server.tool_command_arguments(:search, arguments)).to eq(["--", "visual studio;beta"])
    end

    it "keeps style flags before the file separator" do
      arguments = { "fix" => true, "files" => "formula.rb --changed" }

      expect(server.tool_command_arguments(:style, arguments)).to eq(["--fix", "--", "formula.rb", "--changed"])
    end
  end

  describe "#run" do
    let(:sleep_time) { 0.001 }

    it "handles a tool call without arguments before a ping" do
      allow(Open3).to receive(:popen2e)
        .and_yield(StringIO.new, StringIO.new("commands output"), command_waiter)
      stdin.puts({ jsonrpc:, id:, method: "tools/call", params: { name: "commands" } }.to_json)
      stdin.puts({ jsonrpc:, id: id + 1, method: "ping" }.to_json)
      stdin.rewind

      server.run

      expect(stdout.string.lines.map { |line| JSON.parse(line) }).to match([
        a_hash_including(
          "id"     => id,
          "result" => a_hash_including("content" => [{ "type" => "text", "text" => "commands output" }]),
        ),
        { "jsonrpc" => jsonrpc, "id" => id + 1, "result" => {} },
      ])
    end

    it "answers malformed JSON with a parse error and keeps serving" do
      stdin.puts("not json")
      stdin.puts({ jsonrpc:, id:, method: "ping" }.to_json)
      stdin.rewind

      server.run

      expect(stdout.string.lines.map { |line| JSON.parse(line) }).to eq([
        {
          "jsonrpc" => jsonrpc,
          "id"      => nil,
          "error"   => { "code" => Homebrew::McpServer::PARSE_ERROR_CODE, "message" => "Parse error" },
        },
        { "jsonrpc" => jsonrpc, "id" => id, "result" => {} },
      ])
    end

    it "answers a non-object request with an invalid request error" do
      stdin.puts("[]")
      stdin.rewind

      server.run

      expect(JSON.parse(stdout.string)).to eq({
        "jsonrpc" => jsonrpc,
        "id"      => nil,
        "error"   => { "code" => Homebrew::McpServer::INVALID_REQUEST_CODE, "message" => "Invalid request" },
      })
    end

    it "answers non-object params with a protocol error and keeps serving" do
      stdin.puts({ jsonrpc:, id:, method: "initialize", params: [] }.to_json)
      stdin.puts({ jsonrpc:, id: id + 1, method: "ping" }.to_json)
      stdin.rewind

      server.run

      expect(stdout.string.lines.map { |line| JSON.parse(line) }).to eq([
        {
          "jsonrpc" => jsonrpc,
          "id"      => id,
          "error"   => { "code" => Homebrew::McpServer::INVALID_PARAMS_CODE, "message" => "Invalid params" },
        },
        { "jsonrpc" => jsonrpc, "id" => id + 1, "result" => {} },
      ])
    end

    it "runs the loop and exits cleanly on interrupt" do
      stub_const("ARGV", ["--debug"])
      stdin.puts({ id:, method: "ping" }.to_json)
      stdin.rewind
      server_thread = Thread.new do
        server.run
      rescue SystemExit
        # expected, do nothing
      end

      response_hash_string = "Response: {"
      sleep(sleep_time)
      server_thread.raise(Interrupt)
      server_thread.join

      expect(stderr.string).to include(response_hash_string)
    end

    it "runs the loop and logs 'Response: nil' when handle_request returns nil" do
      stub_const("ARGV", ["--debug"])
      stdin.puts({ id:, method: "notifications/initialized" }.to_json)
      stdin.rewind
      server_thread = Thread.new do
        server.run
      rescue SystemExit
        # expected, do nothing
      end

      response_nil_string = "Response: nil"
      sleep(sleep_time)
      server_thread.raise(Interrupt)
      server_thread.join

      expect(stderr.string).to include(response_nil_string)
    end

    it "exits on Interrupt" do
      stdin.puts
      stdin.rewind
      allow(stdin).to receive(:gets).and_raise(Interrupt)
      expect do
        server.run
      rescue
        SystemExit
      end.to raise_error(SystemExit)
    end

    it "exits on error" do
      stdin.puts
      stdin.rewind
      allow(stdin).to receive(:gets).and_raise(StandardError, "fail")
      expect do
        server.run
      rescue
        SystemExit
      end.to raise_error(SystemExit)
      expect(stderr.string).to include("Error: fail")
    end
  end
end
