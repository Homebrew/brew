# typed: true
# frozen_string_literal: true

require "mcp_server"
require "cask/cask_loader"
require "stringio"
require "timeout"

RSpec.describe Homebrew::McpServer do
  let(:stdin) { StringIO.new }
  let(:stdout) { StringIO.new }
  let(:stderr) { StringIO.new }
  let(:server) { described_class.new(stdin:, stdout:, stderr:) }
  let(:jsonrpc) { Homebrew::McpServer::JSON_RPC_VERSION }
  let(:id) { Random.rand(1000) }
  let(:code) { Homebrew::McpServer::ERROR_CODE }

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
            roots:     {},
          },
          serverInfo:      Homebrew::McpServer::SERVER_INFO,
        },
      })
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

    it "responds to get_server_info" do
      request = { "id" => id, "method" => "get_server_info" }
      result = server.handle_request(request)
      expect(result).to eq({ jsonrpc:, id:, result: Homebrew::McpServer::SERVER_INFO })
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

    test_each(Homebrew::McpServer::TOOLS) do |(tool_name, tool_definition)|
      it "responds to tools/call for #{tool_name}" do
        allow(Open3).to receive(:popen2e).and_return("output for #{tool_name}")
        arguments = {}
        Array(tool_definition[:required]).each do |required_key|
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
          result:  { content: [{ type: "text", text: "output for #{tool_name}" }] },
        })
      end
    end

    it "passes tool arguments as argv when spawning brew" do
      expect(Open3).to receive(:popen2e)
        .with(Homebrew::McpServer::HOMEBREW_BREW_FILE, "search", "visual studio;beta")
        .and_return("output")
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
      expect(result).to eq({ jsonrpc:, id:, error: { message: "Invalid formula or cask argument", code: } })
    end

    # `Cask::CaskLoader::FromContentLoader#load` runs its content through
    # `instance_eval`, so whatever `try_new` accepts is what the cask loader will
    # execute as Ruby. This server forwards `formula_or_cask` to `brew` verbatim
    # and relies on `INLINE_CASK_DSL_REGEX` to reject that set before spawning
    # anything.
    #
    # The two patterns live in different files, so nothing stops one from being
    # widened on its own. These examples lock the relationship down: widen the
    # loader without widening the guard and they fail, rather than silently
    # restoring arbitrary code execution through tools documented as read-only.
    it "rejects every inline cask definition the cask loader would evaluate" do
      [
        %Q(cask "token" do\n  version "1.0"\nend),
        %Q(cask 'token' do\n  version "1.0"\nend),
        'cask "token" do; version "1.0"; end',
        'cask("token") { version "1.0" }',
        %Q(\n\n  cask "token" do\n  version "1.0"\nend\n),
      ].each do |content|
        expect(Cask::CaskLoader::FromContentLoader.try_new(content)).not_to be_nil
        expect(Homebrew::McpServer::INLINE_CASK_DSL_REGEX.match?(content)).to be(true), content.inspect
      end
    end

    it "does not reject a plain cask token" do
      token = "token"

      expect(Cask::CaskLoader::FromContentLoader.try_new(token)).to be_nil
      expect(Homebrew::McpServer::INLINE_CASK_DSL_REGEX.match?(token)).to be(false)
    end

    # The other half of the same invariant, and the half with teeth. A leading
    # comment stops `INLINE_CASK_DSL_REGEX` from matching, so this content
    # reaches `brew` — which is only safe for as long as the cask loader refuses
    # to evaluate it.
    #
    # `brew bump --open-pr` used to fail on casks whose file starts with a
    # comment for exactly this reason (Homebrew/discussions#7043), and the
    # tempting fix is to let `try_new` accept one. Doing that without widening
    # the guard in the same commit restores arbitrary code execution through the
    # MCP server, so this example fails first.
    it "keeps the cask loader from evaluating content the guard lets through" do
      content = %Q(# a comment\ncask "token" do\n  version "1.0"\nend)

      expect(Homebrew::McpServer::INLINE_CASK_DSL_REGEX.match?(content)).to be(false)
      expect(Cask::CaskLoader::FromContentLoader.try_new(content)).to be_nil
    end

    it "responds to tools/call for unknown tool" do
      request = { "id" => id, "method" => "tools/call", "params" => { "name" => "not_a_tool", "arguments" => {} } }
      result = server.handle_request(request)
      expect(result).to eq({ jsonrpc:, id:, error: { message: "Unknown tool", code: } })
    end

    it "responds with error for unknown method" do
      request = { "id" => id, "method" => "not_a_method" }
      result = server.handle_request(request)
      expect(result).to eq({ jsonrpc:, id:, error: { message: "Method not found", code: } })
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
      result = server.respond_error(id, "fail")
      expect(result).to eq({ jsonrpc:, id:, error: { message: "fail", code: } })
    end
  end

  describe "#tool_command_arguments" do
    it "preserves search text as a single raw argv argument" do
      arguments = { "text_or_regex" => "visual studio;beta" }

      expect(server.tool_command_arguments(:search, arguments)).to eq(["visual studio;beta"])
    end
  end

  describe "#run" do
    let(:sleep_time) { 0.001 }

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
