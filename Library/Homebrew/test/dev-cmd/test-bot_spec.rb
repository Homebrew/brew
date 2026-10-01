# typed: strict
# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/test-bot"

RSpec.describe Homebrew::Cmd::TestBotCmd do
  it_behaves_like "parseable arguments"
  it_behaves_like "a documented command", "test-bot"

  it "prints the padded prefix for the current bottle tag" do
    tag = Utils::Bottles::Tag.from_symbol(:arm64_tahoe)
    allow(Utils::Bottles).to receive(:tag).and_return(tag)

    expect { described_class.new(["--print-padded-prefix"]).run }
      .to output("#{tag.padded_prefix}\n").to_stdout
  end

  it "fails when the current bottle tag has no padded prefix" do
    tag = Utils::Bottles::Tag.from_symbol(:tahoe)
    allow(Utils::Bottles).to receive(:tag).and_return(tag)

    expect { described_class.new(["--print-padded-prefix"]).run }
      .to raise_error(SystemExit)
      .and output(/No padded bottle prefix is available for #{tag}/).to_stderr
  end
end
