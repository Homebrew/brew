# typed: true
# frozen_string_literal: true

require_relative "shared_examples"

RSpec.describe UnpackStrategy::Dmg, :needs_macos do
  describe "#mount" do
    subject(:path) { TEST_FIXTURE_DIR/"cask/container.dmg" }

    include_examples "UnpackStrategy::detect"

    specify "#extract" do
      allow(Sandbox).to receive(:isolate_operation?).and_return(true)
      allow(Sandbox).to receive(:operation)

      Dir.mktmpdir do |dir|
        unpack_dir = Pathname(dir)
        mount = instance_double(UnpackStrategy::Dmg::Mount)
        unpack_strategy = described_class.new(path)

        allow(unpack_strategy).to receive(:mount).with(verbose: false).and_yield([mount])
        allow(mount).to receive(:extract).with(to: unpack_dir, verbose: false) do
          (unpack_dir/"container").mkpath
        end

        unpack_strategy.extract(to: unpack_dir)
        expect(unpack_dir.children(false).map(&:to_s)).to contain_exactly("container")
      end
    end

    it "does not treat an unrelated attach failure as a license agreement" do
      unpack_strategy = described_class.new(path)
      attach_result = instance_double(SystemCommand::Result, success?: false, stdout: "")
      attach_error = ErrorDuringExecution.new(["hdiutil", "attach"], status: 1)

      allow(unpack_strategy).to receive(:system_command).and_return(attach_result)
      expect(attach_result).to receive(:assert_success!).and_raise(attach_error)
      expect(unpack_strategy).not_to receive(:system_command!)

      expect { unpack_strategy.mount { nil } }.to raise_error(attach_error)
    end
  end
end
