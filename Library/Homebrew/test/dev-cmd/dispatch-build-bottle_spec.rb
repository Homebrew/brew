# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/dispatch-build-bottle"

RSpec.describe Homebrew::DevCmd::DispatchBuildBottle do
  it_behaves_like "parseable arguments"
end
