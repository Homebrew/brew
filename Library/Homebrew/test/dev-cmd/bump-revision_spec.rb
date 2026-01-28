# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/bump-revision"

RSpec.describe Homebrew::DevCmd::BumpRevision do
  it_behaves_like "parseable arguments"
end
