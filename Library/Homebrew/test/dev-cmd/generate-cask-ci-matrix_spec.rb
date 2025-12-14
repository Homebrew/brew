# typed: strict
# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/generate-cask-ci-matrix"

RSpec.describe Homebrew::DevCmd::GenerateCaskCiMatrix do
  it_behaves_like "parseable arguments"

  describe "#architectures" do
    let(:cmd) { described_class.new }
    let(:appimage_cask) { Cask::CaskLoader.load(TEST_FIXTURE_DIR/"cask/Casks/with-appimage.rb") }
    let(:standard_cask) { Cask::CaskLoader.load(TEST_FIXTURE_DIR/"cask/Casks/basic-cask.rb") }

    it "returns only [:intel] for Casks with an AppImage" do
      expect(cmd.architectures(cask: appimage_cask)).to eq([:intel])
    end

    it "returns all runners for standard Casks" do
      # Assuming standard behavior is to return all archs from RUNNERS
      expected_archs = Homebrew::DevCmd::GenerateCaskCiMatrix::RUNNERS.keys.map do |r|
        r.fetch(:arch).to_sym
      end.uniq.sort
      expect(cmd.architectures(cask: standard_cask)).to eq(expected_archs)
    end
  end
end
