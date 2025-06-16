# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/contributions"

RSpec.describe Homebrew::DevCmd::Contributions do
  it_behaves_like "parseable arguments"
end
