# typed: true
# frozen_string_literal: true

require_relative "shared_examples"

RSpec.describe UnpackStrategy::Dmg, :needs_macos do
  describe "#mount" do
    let(:path) { TEST_FIXTURE_DIR/"cask/container.dmg" }

    include_examples "UnpackStrategy::detect"

    specify "#extract" do
      Dir.mktmpdir do |dir|
        unpack_dir = Pathname(dir)
        # `Mount` is a private constant on the strategy under test.
        # rubocop:disable Sorbet/ConstantsFromStrings
        mount = instance_double(described_class.const_get(:Mount, false))
        # rubocop:enable Sorbet/ConstantsFromStrings
        unpack_strategy = described_class.new(path)

        allow(unpack_strategy).to receive(:mount).with(verbose: false).and_yield([mount])
        allow(mount).to receive(:extract).with(to: unpack_dir, verbose: false) do
          (unpack_dir/"container").mkpath
        end

        unpack_strategy.extract(to: unpack_dir)
        expect(unpack_dir.children(false).map(&:to_s)).to contain_exactly("container")
      end
    end
  end
end
