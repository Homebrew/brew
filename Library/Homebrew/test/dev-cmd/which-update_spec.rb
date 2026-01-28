# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/which-update"

RSpec.describe Homebrew::DevCmd::WhichUpdate do
  it_behaves_like "parseable arguments"
end
