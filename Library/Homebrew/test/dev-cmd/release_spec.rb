# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/release"

RSpec.describe Homebrew::DevCmd::Release do
  it_behaves_like "parseable arguments"
end
