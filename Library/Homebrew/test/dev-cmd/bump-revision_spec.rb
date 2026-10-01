# typed: strict
# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/bump-revision"

RSpec.describe Homebrew::DevCmd::BumpRevision do
  it_behaves_like "parseable arguments"

  it "previews a Formula revision bump", :integration_test do
    setup_test_formula "testball"

    expect { brew "bump-revision", "--dry-run", "testball" }
      .to output(/add "revision 1"/).to_stdout
      .and not_to_output.to_stderr
      .and be_a_success
  end
end
