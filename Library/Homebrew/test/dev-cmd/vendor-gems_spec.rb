# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/vendor-gems"

RSpec.describe Homebrew::DevCmd::VendorGems do
  it_behaves_like "parseable arguments"
end
