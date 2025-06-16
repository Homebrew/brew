# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/generate-formula-api"

RSpec.describe Homebrew::DevCmd::GenerateFormulaApi do
  it_behaves_like "parseable arguments"
end
