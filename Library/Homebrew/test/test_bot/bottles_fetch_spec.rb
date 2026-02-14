# frozen_string_literal: true

require "test_bot"
require "dev-cmd/test-bot"

RSpec.describe Homebrew::TestBot::BottlesFetch do
  describe "#run!" do
    it "accepts Utils::Bottles::Tag objects from the bottle collector" do
      # Regression test: bottle_specification.collector.tags returns Utils::Bottles::Tag objects,
      # not Symbols. The fetch_bottles! signature must accept Tag, not Symbol.
      fetch = described_class.new(tap: nil, git: nil, dry_run: true, fail_fast: false, verbose: false)
      fetch.testing_formulae = ["some-formula"]
      tag = Utils::Bottles::Tag.new(system: :sequoia, arch: :arm64)
      allow(fetch).to receive(:formulae_by_tag).and_return({ tag => Set["some-formula"] })
      allow(fetch).to receive(:cleanup_during!)

      fetch.run!(args: instance_double(Homebrew::Cmd::TestBotCmd::Args))

      expect(fetch.steps.last).to be_passed
      expect(fetch.steps.last.command).to include("--bottle-tag=#{tag}")
    end
  end
end
