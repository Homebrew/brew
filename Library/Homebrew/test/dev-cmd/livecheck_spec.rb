# typed: strict
# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/livecheck"

RSpec.describe Homebrew::DevCmd::LivecheckCmd do
  it_behaves_like "parseable arguments"

  it "skips a Formula and Cask with disabled livechecks", :cask, :integration_test do
    content = <<~RUBY
      desc "Some test"
      homepage "https://github.com/Homebrew/brew"
      url "https://brew.sh/test-1.0.0.tgz"

      livecheck do
        skip "integration test"
      end
    RUBY
    setup_test_formula("test", content)

    expect { brew "livecheck", "test", "latest-with-livecheck-skip" }
      .to output(/latest-with-livecheck-skip: skipped.*test: skipped - integration test/m).to_stdout
      .and not_to_output.to_stderr
      .and be_a_success
  end

  it "gives an error when no arguments are given and there's no watchlist" do
    allow(Utils::GemSetup).to receive(:install_bundler_gems!)

    with_env("HOMEBREW_LIVECHECK_WATCHLIST" => ".this_should_not_exist") do
      expect { described_class.new([]).run }
        .to raise_error(UsageError, /No formulae or casks to check/)
    end
  end

  it "uses the watchlist before all trusted packages" do
    allow(Utils::GemSetup).to receive(:install_bundler_gems!)
    expect(Formula).not_to receive(:all)
    expect(Cask::Cask).not_to receive(:all)

    mktmpdir do |dir|
      watchlist = dir/"livecheck_watchlist.txt"
      watchlist.write("# empty\n")

      with_env("HOMEBREW_LIVECHECK_WATCHLIST" => watchlist) do
        expect { described_class.new([]).run }
          .to raise_error(UsageError, /No formulae or casks to check/)
      end
    end
  end
end
