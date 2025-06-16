# frozen_string_literal: true

require "cmd/analytics"
require "cmd/shared_examples/args_parse"

RSpec.describe Homebrew::Cmd::Analytics do
  it_behaves_like "parseable arguments"

  it "when HOMEBREW_NO_ANALYTICS is unset is disabled after running `brew analytics off`", :integration_test do
    HOMEBREW_REPOSITORY.cd do
      system "git", "init"
    end

    brew "analytics", "off"
    expect { brew "analytics", "HOMEBREW_NO_ANALYTICS" => nil }
      .to output(/analytics are disabled/i).to_stdout
      .and not_to_output.to_stderr
      .and be_a_success
  end
end
