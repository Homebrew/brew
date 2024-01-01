# frozen_string_literal: true

require "cmd/shared_examples/args_parse"

describe "brew livecheck" do
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

  it "gives an error when no arguments are given and there's no watchlist", :integration_test do
    expect { brew "livecheck", "HOMEBREW_LIVECHECK_WATCHLIST" => ".this_should_not_exist" }
      .to output(/Invalid usage: A watchlist file is required when no arguments are given\./).to_stderr
      .and not_to_output.to_stdout
      .and be_a_failure
  end
end
