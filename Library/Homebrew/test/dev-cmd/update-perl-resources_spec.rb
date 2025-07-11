# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/update-perl-resources"

RSpec.describe Homebrew::DevCmd::UpdatePerlResources do
  it_behaves_like "parseable arguments"
end
