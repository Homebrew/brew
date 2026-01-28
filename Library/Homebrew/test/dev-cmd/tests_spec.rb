# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/tests"

RSpec.describe Homebrew::DevCmd::Tests do
  it_behaves_like "parseable arguments"
end
