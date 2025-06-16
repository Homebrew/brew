# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/formula-analytics"

RSpec.describe Homebrew::DevCmd::FormulaAnalytics do
  it_behaves_like "parseable arguments"
end
