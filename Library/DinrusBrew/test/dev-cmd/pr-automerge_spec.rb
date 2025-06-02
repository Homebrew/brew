# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/pr-automerge"

RSpec.describe DinrusBrew::DevCmd::PrAutomerge do
  it_behaves_like "parseable arguments"
end
