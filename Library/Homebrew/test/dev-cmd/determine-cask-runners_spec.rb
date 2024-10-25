# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/determine-cask-runners"

RSpec.describe Homebrew::DevCmd::DetermineCaskRunners do
  ENV["GITHUB_REPOSITORY"] = "homebrew/homebrew-cask"

  it_behaves_like "parseable arguments"

  it "generates a matrix", :integration_test do
    expect do
      brew "determine-cask-runners", "test-cask",
           "GITHUB_REPOSITORY" => "homebrew/homebrew-cask"
    end.to output(%r{Error: No such file or directory @ rb_sysopen - Casks/test-cask.rb}).to_stderr
  end
end
