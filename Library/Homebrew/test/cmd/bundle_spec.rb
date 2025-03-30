# frozen_string_literal: true

require "cmd/bundle"
require "cmd/shared_examples/args_parse"

RSpec.describe Homebrew::Cmd::Bundle do
  it_behaves_like "parseable arguments"

  it "checks if a Brewfile's dependencies are satisfied", :integration_test do
    HOMEBREW_REPOSITORY.cd do
      system "git", "init"
      system "git", "commit", "--allow-empty", "-m", "This is a test commit"
    end

    mktmpdir do |path|
      FileUtils.touch "#{path}/Brewfile"
      path.cd do
        expect { brew "bundle", "check" }
          .to output("The Brewfile's dependencies are satisfied.\n").to_stdout
          .and not_to_output.to_stderr
          .and be_a_success
      end
    end
  end
end
