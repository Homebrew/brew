# frozen_string_literal: true

require "cmd/shared_examples/args_parse"

describe "brew update-python-resources" do
  it_behaves_like "parseable arguments"
end
