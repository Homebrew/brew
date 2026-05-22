# typed: true
# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/test-portable-ruby"

RSpec.describe Homebrew::DevCmd::TestPortableRuby do
  it_behaves_like "parseable arguments"
end
