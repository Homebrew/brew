# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/lgtm"

RSpec.describe Homebrew::DevCmd::Lgtm do
  it_behaves_like "parseable arguments"
end
