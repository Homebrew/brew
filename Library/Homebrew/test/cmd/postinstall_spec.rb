# frozen_string_literal: true

require "cmd/postinstall"
require "cmd/shared_examples/args_parse"

RSpec.describe Homebrew::Cmd::Postinstall do
  it_behaves_like "parseable arguments"
end
