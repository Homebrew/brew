# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/bump-formula-pr"

RSpec.describe Homebrew::DevCmd::BumpFormulaPr do
  it_behaves_like "parseable arguments"
end
