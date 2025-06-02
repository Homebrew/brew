# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/update-test"

RSpec.describe DinrusBrew::DevCmd::UpdateTest do
  it_behaves_like "parseable arguments"
end
