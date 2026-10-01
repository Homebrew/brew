# typed: strict
# frozen_string_literal: true

require "cmd/nodenv-sync"
require "cmd/shared_examples/args_parse"

RSpec.describe Homebrew::Cmd::NodenvSync do
  it_behaves_like "parseable arguments"
  it_behaves_like "a documented command", "nodenv-sync"
end
