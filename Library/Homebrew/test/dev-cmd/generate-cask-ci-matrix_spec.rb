# typed: strict
# rubocop:disable RSpec/NoExpectationExample
# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/generate-cask-ci-matrix"

RSpec.describe Homebrew::DevCmd::GenerateCaskCiMatrix do
  it_behaves_like "parseable arguments"

  describe "#architectures" do
    let(:cmd) { described_class.new }
    let(:linux_arch_cask) { Cask::CaskLoader.load(TEST_FIXTURE_DIR/"cask/Casks/on-linux-arch.rb") }
    let(:standard_cask) { Cask::CaskLoader.load(TEST_FIXTURE_DIR/"cask/Casks/basic-cask.rb") }

    it "returns only [:intel] for Casks with an on_linux arch dependency" do
      T.unsafe(self).expect(cmd.architectures(cask: linux_arch_cask)).to T.unsafe(self).eq([:intel])
    end

    it "returns all runners for standard Casks" do
      # Assuming standard behavior is to return all archs from RUNNERS
      expected_archs = Homebrew::DevCmd::GenerateCaskCiMatrix::RUNNERS.keys.map do |r|
        r.fetch(:arch).to_sym
      end.uniq.sort
      T.unsafe(self).expect(cmd.architectures(cask: standard_cask)).to T.unsafe(self).eq(expected_archs)
    end
  end
end

# rubocop:enable RSpec/NoExpectationExample
