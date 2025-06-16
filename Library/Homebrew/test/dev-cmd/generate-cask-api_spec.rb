# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/generate-cask-api"

RSpec.describe Homebrew::DevCmd::GenerateCaskApi do
  it_behaves_like "parseable arguments"
end
