# frozen_string_literal: true

require "cmd/shared_examples/args_parse"

describe "brew command" do
  it_behaves_like "parseable arguments"

  it "returns the file for a given command", :integration_test do
    expect { brew "command", "info" }
      .to output(%r{#{Regexp.escape(HOMEBREW_LIBRARY_PATH)}/cmd/info.rb}o).to_stdout
      .and be_a_success
  end
end
