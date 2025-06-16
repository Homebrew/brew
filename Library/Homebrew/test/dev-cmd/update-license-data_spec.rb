# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/update-license-data"

RSpec.describe Homebrew::DevCmd::UpdateLicenseData do
  it_behaves_like "parseable arguments"
end
