# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/bump-unversioned-casks"

RSpec.describe Homebrew::DevCmd::BumpUnversionedCasks do
  it_behaves_like "parseable arguments"
end
