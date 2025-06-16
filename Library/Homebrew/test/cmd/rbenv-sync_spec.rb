# frozen_string_literal: true

require "cmd/rbenv-sync"
require "cmd/shared_examples/args_parse"

RSpec.describe Homebrew::Cmd::RbenvSync do
  it_behaves_like "parseable arguments"
end
