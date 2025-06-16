# frozen_string_literal: true

require "dev-cmd/audit"
require "cmd/shared_examples/args_parse"

RSpec.describe Homebrew::DevCmd::Audit do
  it_behaves_like "parseable arguments"
end
