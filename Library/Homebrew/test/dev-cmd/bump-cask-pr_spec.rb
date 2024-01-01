# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/bump-cask-pr"

describe "brew bump-cask-pr" do
  it_behaves_like "parseable arguments"
end
