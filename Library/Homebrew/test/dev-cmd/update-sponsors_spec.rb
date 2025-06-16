# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/update-sponsors"

RSpec.describe Homebrew::DevCmd::UpdateSponsors do
  it_behaves_like "parseable arguments"
end
