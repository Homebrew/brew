# frozen_string_literal: true

require "cmd/pyenv-sync"
require "cmd/shared_examples/args_parse"

RSpec.describe Homebrew::Cmd::PyenvSync do
  it_behaves_like "parseable arguments"
end
