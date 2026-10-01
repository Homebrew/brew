# typed: strict
# frozen_string_literal: true

require "test_bot"

RSpec.describe Homebrew::TestBot::FormulaeDetect do
  describe "::DEFAULT_TEST_FORMULAE" do
    it "uses GitHub-hosted, dependency-free formulae for default formula testing" do
      expect(Homebrew::TestBot::FormulaeDetect::DEFAULT_TEST_FORMULAE).to eq(%w[termbox bats-core])
    end
  end
end
