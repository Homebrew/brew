# typed: true
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

      specify do
        expect(dumper.tap_names).to be_empty
        expect(dumper.dump).to eql("")
      end
    end

    context "with taps" do
      before do
        described_class.reset!

        bar = instance_double(Tap, name: "bitbucket/bar", custom_remote?: true,
                              remote: "https://bitbucket.org/bitbucket/bar.git",
                              default_remote: "https://github.com/bitbucket/homebrew-bar")
        baz = instance_double(Tap, name: "homebrew/baz", custom_remote?: false, remote: nil)
        foo = instance_double(Tap, name: "homebrew/foo", custom_remote?: false, remote: nil)

        ENV["HOMEBREW_GITHUB_API_TOKEN_BEFORE"] = ENV.fetch("HOMEBREW_GITHUB_API_TOKEN", nil)
        ENV["HOMEBREW_GITHUB_API_TOKEN"] = "some-token"
        private_tap = instance_double(Tap, name: "privatebrew/private", custom_remote?: true,
          remote: "https://#{ENV.fetch("HOMEBREW_GITHUB_API_TOKEN")}@github.com/privatebrew/homebrew-private",
          default_remote: "https://github.com/privatebrew/homebrew-private")

        [bar, baz, foo, private_tap].each do |tap|
          allow(tap).to receive(:matches_reference?) { |reference| reference == tap.remote }
        end

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
        expected_output = <<~RUBY
          tap "bitbucket/bar", "https://bitbucket.org/bitbucket/bar.git"
          tap "homebrew/baz"
          tap "homebrew/foo"
          tap "privatebrew/private", "https://\#{ENV.fetch("HOMEBREW_GITHUB_API_TOKEN")}@github.com/privatebrew/homebrew-private"
        RUBY
        expect(dumper.dump).to eql(expected_output.chomp)
      end

      it "dumps trusted taps with trusted true" do
        allow(Homebrew::Trust).to receive(:trusted_entries).with(:tap)
                                                           .and_return(["https://bitbucket.org/bitbucket/bar.git"])

        expect(dumper.dump).to include(
          "tap \"bitbucket/bar\", \"https://bitbucket.org/bitbucket/bar.git\", trusted: true",
        )
      end

      it "dumps GitHub clone targets matching a tap's default repository" do
        described_class.reset!
        tap = instance_double(Tap, name: "alternatert/tap", custom_remote?: false,
          remote: "git@github.com:AlternateRT/homebrew-tap.git",
          default_remote: "https://github.com/alternatert/homebrew-tap")

        allow(tap).to receive(:matches_reference?) { |reference| reference == tap.remote }
        allow(Tap).to receive(:select).and_return [tap]

        expect(dumper.dump).to eql(
          "tap \"alternatert/tap\", \"git@github.com:AlternateRT/homebrew-tap.git\"",
        )
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

      it "clears cached tap contents after tapping" do
        tap = Tap.fetch("bundle-test/rootformula")
        FileUtils.rm_rf(tap.path)
        tap.clear_cache

        expect(tap.formula_dir).to eq(tap.path/"Formula")

        expect(Homebrew::Bundle).to receive(:system).with(HOMEBREW_BREW_FILE, "tap", tap.name,
                                                          verbose: false) do
          tap.path.mkpath
          FileUtils.touch tap.path/"foo.rb"
          true
        end

        expect(described_class.install!(tap.name)).to be(true)
        expect(tap.formula_dir).to eq(tap.path)
        expect(tap.formula_files_by_name).to include("foo" => tap.path/"foo.rb")
      ensure
        if tap
          FileUtils.rm_rf(tap.path)
          tap.path.parent.rmdir_if_possible
        end
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
