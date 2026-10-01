# typed: strict
# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/unbottled"

RSpec.describe Homebrew::DevCmd::Unbottled do
  it_behaves_like "parseable arguments"

  it "prints that an unbottled formula with no dependencies is ready to bottle", :integration_test do
    setup_test_formula "testball"

    expect { brew "unbottled", "testball" }
      .to output(/testball: ready to bottle/).to_stdout
      .and not_to_output.to_stderr
      .and be_a_success
  end
end
