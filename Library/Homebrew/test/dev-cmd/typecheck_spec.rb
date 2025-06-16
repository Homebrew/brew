# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/typecheck"

RSpec.describe Homebrew::DevCmd::Typecheck do
  it_behaves_like "parseable arguments"
end
