# typed: true
# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/livecheck"

RSpec.describe Homebrew::DevCmd::LivecheckCmd do
  it_behaves_like "parseable arguments"

  it "reports the latest version of a Formula", :integration_test, :needs_network do
    content = <<~RUBY
      desc "Some test"
      homepage "https://github.com/Homebrew/brew"
      url "https://brew.sh/test-1.0.0.tgz"
    RUBY
    setup_test_formula("test", content)

    expect { brew "livecheck", "test" }
      .to output(/test: /).to_stdout
      .and not_to_output.to_stderr
      .and be_a_success
  end

  it "gives an error when no arguments are given and there's no watchlist" do
    allow(Homebrew).to receive(:install_bundler_gems!)

    with_env("HOMEBREW_LIVECHECK_WATCHLIST" => ".this_should_not_exist") do
      expect { described_class.new([]).run }
        .to raise_error(UsageError, /No formulae or casks to check/)
    end
  end
end
