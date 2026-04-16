# typed: false
# frozen_string_literal: true

require "bundle"
require "bundle/skipper"
require "bundle/tap"

RSpec.describe Homebrew::Bundle::Tap do
  describe "dumping" do
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

  describe "installing" do
    describe ".installed_taps" do
      before do
        described_class.reset!
      end

      it "calls Homebrew" do
        expect { described_class.installed_taps }.not_to raise_error
      end
    end

    context "when tap is installed" do
      before do
        allow(described_class).to receive(:installed_taps).and_return(["homebrew/cask"])
      end

      it "skips" do
        expect(Homebrew::Bundle).not_to receive(:system)
        expect(described_class.preinstall!("homebrew/cask")).to be(false)
      end
    end

    context "when tap is not installed" do
      before do
        allow(described_class).to receive(:installed_taps).and_return([])
      end

      it "taps" do
        expect(Homebrew::Bundle).to receive(:system).with(HOMEBREW_BREW_FILE, "tap", "homebrew/cask",
                                                          verbose: false).and_return(true)
        expect(described_class.preinstall!("homebrew/cask")).to be(true)
        expect(described_class.install!("homebrew/cask")).to be(true)
      end

      context "with clone target" do
        it "taps" do
          expect(Homebrew::Bundle).to \
            receive(:system).with(HOMEBREW_BREW_FILE, "tap", "homebrew/cask", "clone_target_path",
                                  verbose: false).and_return(true)
          expect(described_class.preinstall!("homebrew/cask", clone_target: "clone_target_path")).to be(true)
          expect(described_class.install!("homebrew/cask", clone_target: "clone_target_path")).to be(true)
        end

        it "fails" do
          expect(Homebrew::Bundle).to \
            receive(:system).with(HOMEBREW_BREW_FILE, "tap", "homebrew/cask", "clone_target_path",
                                  verbose: false).and_return(false)
          expect(described_class.preinstall!("homebrew/cask", clone_target: "clone_target_path")).to be(true)
          expect(described_class.install!("homebrew/cask", clone_target: "clone_target_path")).to be(false)
        end
      end
    end
  end
end
