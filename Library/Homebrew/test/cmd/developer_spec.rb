# frozen_string_literal: true

require "cmd/developer"
require "cmd/shared_examples/args_parse"

RSpec.describe Homebrew::Cmd::Developer do
  it_behaves_like "parseable arguments"
end
