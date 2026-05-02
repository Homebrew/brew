# typed: false
# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/which-entry"

RSpec.describe Homebrew::DevCmd::WhichEntry do
  it_behaves_like "parseable arguments"

  it "raises a UsageError if --output-db is not passed", :integration_test do
    expect { brew "which-entry", "wget" }
      .to output(/`--output-db` is required/).to_stderr
      .and be_a_failure
  end
end
