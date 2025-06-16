# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/style"

RSpec.describe Homebrew::DevCmd::StyleCmd do
  it_behaves_like "parseable arguments"
end
