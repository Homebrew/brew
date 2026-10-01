# typed: strict
# frozen_string_literal: true

require "test_bot"
require "dev-cmd/test-bot"

RSpec.describe Homebrew::TestBot::BottlesFetch do
  describe "#run!" do
    it "rejects a merge that drops existing transition coverage" do
      current = formula("transition-test") do
        T.bind(self, T.class_of(Formula))
        url "https://brew.sh/transition-test-2.0.tar.gz"
        bottle do
          sha256 arm64_tahoe: ("a" * 64).to_s
        end
      end
      allow(Formula).to receive(:[]).with(current.name).and_return(current)
      allow_any_instance_of(BottleTransition).to receive(:required?).and_return(true)
      fetch = described_class.new(tap: nil, git: nil, dry_run: true, fail_fast: false, verbose: false)
      fetch.testing_formulae = [current.name]

      expect do
        fetch.run!(args: instance_double(Homebrew::Cmd::TestBotCmd::Args))
      end.to raise_error(UsageError, /before publishing or merging/)
    end

    it "accepts Utils::Bottles::Tag objects from the bottle collector" do
      # Regression test: bottle_specification.collector.tags returns Utils::Bottles::Tag objects,
      # not Symbols. The fetch_bottles! signature must accept Tag, not Symbol.
      fetch = described_class.new(tap: nil, git: nil, dry_run: true, fail_fast: false, verbose: false)
      fetch.testing_formulae = ["some-formula"]
      tag = Utils::Bottles::Tag.new(system: :sequoia, arch: :arm64)
      allow(fetch).to receive(:formulae_by_tag).and_return({ tag => Set["some-formula"] })
      allow(fetch).to receive(:cleanup_during!)

      fetch.run!(args: instance_double(Homebrew::Cmd::TestBotCmd::Args))

      last_step = fetch.steps.fetch(-1)
      expect(last_step).to be_passed
      expect(last_step.command).to include("--bottle-tag=#{tag}")
    end
  end
end
