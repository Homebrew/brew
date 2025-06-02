# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/bump-cask-pr"

RSpec.describe DinrusBrew::DevCmd::BumpCaskPr do
  it_behaves_like "parseable arguments"
end
