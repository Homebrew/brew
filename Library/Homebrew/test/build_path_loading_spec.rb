# typed: strict
# frozen_string_literal: true

require "formula"
require "cmd/install"
require "cli/named_args"

RSpec.describe Formulary, :no_api do
  it "parses source-build options using only the parent-selected formula" do
    path = mktmpdir/"path-loading.rb"
    path.write <<~RUBY
      class PathLoading < Formula
        url "https://example.com/path-loading-1.0.tar.gz"
        option "with-feature", "Build with feature"
      end
    RUBY

    expect(Homebrew::Cmd::InstallCmd.new(
      [path.to_s, "--with-feature"], formula: described_class.from_path(path)
    ).args.flags_only).to include("--with-feature")
  end

  context "when installing a local bottle" do
    sig { returns(Pathname) }
    let(:bottle_path) do
      TEST_FIXTURE_DIR/"bottles/testball_bottle-0.1.#{Utils::Bottles.tag}.bottle.tar.gz"
    end

    before do
      allow(Utils::Bottles).to receive(:formula_contents).and_return <<~RUBY
        class TestballBottle < Formula
          url "https://example.com/testball_bottle-0.1.tar.gz"
          option "with-feature", "Build with feature"
        end
      RUBY
    end

    it "loads the bottle without looking up a cask" do
      expect(Homebrew::CLI::NamedArgs.new(bottle_path.to_s)
        .to_formulae_and_casks(method: :bottle).first).to have_attributes(local_bottle_path: bottle_path.realpath)
    end

    test_each([[], ["--only-dependencies"], ["--formula"]]) do |flags|
      it "parses bottle formula options with #{flags.inspect}" do
        expect(Homebrew::Cmd::InstallCmd.new([bottle_path.to_s, "--with-feature", *flags])
          .args.named.to_formulae_and_casks(method: :bottle).first)
          .to have_attributes(local_bottle_path: bottle_path.realpath)
      end
    end
  end
end
