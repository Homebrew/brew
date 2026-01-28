# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/verify"

RSpec.describe Homebrew::DevCmd::Verify do
  it_behaves_like "parseable arguments"
end
