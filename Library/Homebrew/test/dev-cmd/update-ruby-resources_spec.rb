# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/update-ruby-resources"

RSpec.describe Homebrew::DevCmd::UpdateRubyResources do
  it_behaves_like "parseable arguments"
end
