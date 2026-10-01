# typed: strict
# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "cmd/command-not-found-init"

RSpec.describe Homebrew::Cmd::CommandNotFoundInit do
  it_behaves_like "parseable arguments"
  it_behaves_like "a documented command", "command-not-found-init"
end
