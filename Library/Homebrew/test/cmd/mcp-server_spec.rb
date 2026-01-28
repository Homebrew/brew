# frozen_string_literal: true

RSpec.describe "brew mcp-server", type: :system do
  it "starts the MCP server", :integration_test do
    # This is the easiest way to handle a newline here.
    # rubocop:disable Style/StringConcatenation
    expect { brew_sh "mcp-server", "--ping" }
      .to output("==> Started Homebrew MCP server...\n").to_stderr
      .and output('{"jsonrpc":"2.0","id":1,"result":{}}' + "\n").to_stdout
      .and be_a_success
    # rubocop:enable Style/StringConcatenation
  end
end
