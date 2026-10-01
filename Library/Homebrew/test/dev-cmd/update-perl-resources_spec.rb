# typed: strict
# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/update-perl-resources"

RSpec.describe Homebrew::DevCmd::UpdatePerlResources do
  it_behaves_like "parseable arguments"

  it "loads a Formula's Perl resources", :integration_test do
    setup_test_formula "testball"

    expect { brew "update-perl-resources", "--print-only", "testball" }
      .to output(/"testball" has no CPAN resources to update/).to_stderr
      .and be_a_failure
  end
end
