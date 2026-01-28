# frozen_string_literal: true

require "cmd/nodenv-sync"
require "cmd/shared_examples/args_parse"

RSpec.describe Homebrew::Cmd::NodenvSync do
  it_behaves_like "parseable arguments"
end
