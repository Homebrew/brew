# typed: strict
# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/update-test"

RSpec.describe Homebrew::DevCmd::UpdateTest do
  it_behaves_like "parseable arguments"
  it_behaves_like "a documented command", "update-test"
end
