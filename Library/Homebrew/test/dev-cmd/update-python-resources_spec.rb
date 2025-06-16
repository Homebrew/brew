# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/update-python-resources"

RSpec.describe Homebrew::DevCmd::UpdatePythonResources do
  it_behaves_like "parseable arguments"
end
