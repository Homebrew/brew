# typed: strict
# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/which-entry"

RSpec.describe Homebrew::DevCmd::WhichEntry do
  it_behaves_like "parseable arguments"
end
