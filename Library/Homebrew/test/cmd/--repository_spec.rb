# frozen_string_literal: true

require "cmd/shared_examples/args_parse"

describe "brew --repository" do
  it_behaves_like "parseable arguments"

  it "prints Homebrew's repository", :integration_test do
    expect { brew_sh "--repository" }
      .to output("#{ENV.fetch("HOMEBREW_REPOSITORY")}\n").to_stdout
      .and not_to_output.to_stderr
      .and be_a_success
  end

  it "prints a Tap's repository", :integration_test do
    expect { brew "--repository", "foo/bar" }
      .to output("#{HOMEBREW_LIBRARY}/Taps/foo/homebrew-bar\n").to_stdout
      .and not_to_output.to_stderr
      .and be_a_success
  end
end
