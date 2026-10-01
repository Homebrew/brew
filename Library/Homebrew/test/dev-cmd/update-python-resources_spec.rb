# typed: strict
# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/update-python-resources"

RSpec.describe Homebrew::DevCmd::UpdatePythonResources do
  it_behaves_like "parseable arguments"

  it "loads a Formula's Python resources", :integration_test do
    setup_test_formula "testball"

    expect do
      brew "update-python-resources", "--print-only", "--version=0.2",
           "--ignore-non-pypi-packages", "testball"
    end
      .to not_to_output.to_stderr
      .and be_a_success
  end
end
