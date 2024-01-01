# frozen_string_literal: true

require "cmd/shared_examples/args_parse"

describe "brew generate-cask-api" do
  it_behaves_like "parseable arguments"
end
