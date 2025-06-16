# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/bump"

RSpec.describe Homebrew::DevCmd::Bump do
  it_behaves_like "parseable arguments"

  describe "formula", :integration_test, :needs_homebrew_curl, :needs_network do
    it "returns no data and prints a message for HEAD-only formulae" do
      content = <<~RUBY
        desc "HEAD-only test formula"
        homepage "https://brew.sh"
        head "https://github.com/Homebrew/brew.git"
      RUBY
      setup_test_formula("headonly", content)

      expect { brew "bump", "headonly" }
        .to output(/Formula is HEAD-only./).to_stdout
        .and not_to_output.to_stderr
        .and be_a_success
    end
  end

  it "gives an error for `--tap` with official taps", :integration_test do
    expect { brew "bump", "--tap", "Homebrew/core" }
      .to output(/Invalid usage/).to_stderr
      .and not_to_output.to_stdout
      .and be_a_failure
  end
end
