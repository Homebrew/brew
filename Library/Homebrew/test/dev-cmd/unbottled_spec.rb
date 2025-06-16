# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/unbottled"

RSpec.describe Homebrew::DevCmd::Unbottled do
  it_behaves_like "parseable arguments"
end
