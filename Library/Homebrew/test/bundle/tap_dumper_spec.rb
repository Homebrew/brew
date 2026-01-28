# frozen_string_literal: true

require "bundle"
require "bundle/skipper"
require "bundle/tap_dumper"

RSpec.describe Homebrew::Bundle::TapDumper do
  subject(:dumper) { described_class }

  context "when there is no tap" do
    before do
      described_class.reset!
      allow(Tap).to receive(:select).and_return []
    end

    it "returns empty list" do
      expect(dumper.tap_names).to be_empty
    end

    it "dumps as empty string" do # rubocop:todo RSpec/AggregateExamples
      expect(dumper.dump).to eql("")
    end
  end

  context "with taps" do
    before do
      described_class.reset!

      bar = instance_double(Tap, name: "bitbucket/bar", custom_remote?: true,
                            remote: "https://bitbucket.org/bitbucket/bar.git")
      baz = instance_double(Tap, name: "homebrew/baz", custom_remote?: false)
      foo = instance_double(Tap, name: "homebrew/foo", custom_remote?: false)

      ENV["HOMEBREW_GITHUB_API_TOKEN_BEFORE"] = ENV.fetch("HOMEBREW_GITHUB_API_TOKEN", nil)
      ENV["HOMEBREW_GITHUB_API_TOKEN"] = "some-token"
      private_tap = instance_double(Tap, name: "privatebrew/private", custom_remote?: true,
        remote: "https://#{ENV.fetch("HOMEBREW_GITHUB_API_TOKEN")}@github.com/privatebrew/homebrew-private")

      allow(Tap).to receive(:select).and_return [bar, baz, foo, private_tap]
    end

    after do
      ENV["HOMEBREW_GITHUB_API_TOKEN"] = ENV.fetch("HOMEBREW_GITHUB_API_TOKEN_BEFORE", nil)
      ENV.delete("HOMEBREW_GITHUB_API_TOKEN_BEFORE")
    end

    it "returns list of information" do
      expect(dumper.tap_names).not_to be_empty
    end

    it "dumps output" do
      expected_output = <<~EOS
        tap "bitbucket/bar", "https://bitbucket.org/bitbucket/bar.git"
        tap "homebrew/baz"
        tap "homebrew/foo"
        tap "privatebrew/private", "https://\#{ENV.fetch("HOMEBREW_GITHUB_API_TOKEN")}@github.com/privatebrew/homebrew-private"
      EOS
      expect(dumper.dump).to eql(expected_output.chomp)
    end
  end
end
