# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/pr-publish"

RSpec.describe Homebrew::DevCmd::PrPublish do
  it_behaves_like "parseable arguments"
end
