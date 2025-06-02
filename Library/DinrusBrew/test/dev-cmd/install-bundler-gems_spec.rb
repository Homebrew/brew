# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/install-bundler-gems"

RSpec.describe DinrusBrew::DevCmd::InstallBundlerGems do
  it_behaves_like "parseable arguments"
end
