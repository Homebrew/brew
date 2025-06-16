# frozen_string_literal: true

require "cmd/gist-logs"
require "cmd/shared_examples/args_parse"

RSpec.describe Homebrew::Cmd::GistLogs do
  it_behaves_like "parseable arguments"
end
