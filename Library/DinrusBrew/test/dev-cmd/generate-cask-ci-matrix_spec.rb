# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/generate-cask-ci-matrix"

RSpec.describe DinrusBrew::DevCmd::GenerateCaskCiMatrix do
  it_behaves_like "parseable arguments"
end
