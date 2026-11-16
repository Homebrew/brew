# typed: true
# frozen_string_literal: true

require_relative "shared_examples"

RSpec.describe UnpackStrategy::Dmg, :needs_macos do
  describe UnpackStrategy::Dmg::Bom do
    it "ignores Desktop DB at the volume root" do
      expect(described_class.dmg_metadata?(Pathname("./Desktop DB"))).to be true
    end

    it "ignores Desktop DF at the volume root" do
      expect(described_class.dmg_metadata?(Pathname("./Desktop DF"))).to be true
    end

    it "preserves Desktop DB inside an application" do
      expect(described_class.dmg_metadata?(Pathname("Example.app/Contents/Resources/Desktop DB"))).to be false
    end

    it "preserves Desktop DF inside an application" do
      expect(described_class.dmg_metadata?(Pathname("Example.app/Contents/Resources/Desktop DF"))).to be false
    end
  end

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

    context "when macOS cancels attachment of a problematic disk image" do
      let(:unpack_strategy) { described_class.new(path) }
      let(:stderr) do
        <<~EOS
          There may be a problem with this disk image. Are you sure you want to open it?
          hdiutil: WARNING: 'hdiutil attach -nobrowse -readonly ...' is deprecated.
          hdiutil: attach canceled
        EOS
      end
      let(:attach_error) do
        ErrorDuringExecution.new(["hdiutil", "attach", path], status: 1, output: [[:stderr, stderr]])
      end

      before do
        attach_result = instance_double(SystemCommand::Result, success?: false, stdout: "")
        allow(unpack_strategy).to receive(:system_command).and_return(attach_result)
        allow(attach_result).to receive(:assert_success!).and_raise(attach_error)
        allow(unpack_strategy).to receive(:system_command!).and_raise("Unexpected disk image conversion")
      end

      it "explains the failure and asks for a corrected image from the vendor" do
        expect { unpack_strategy.mount { nil } }.to raise_error(ErrorDuringExecution, <<~EOS)
          macOS refused to mount the disk image:
            #{path}
          Its filesystem may be damaged or inconsistent.
          Report this to the software vendor and request a corrected disk image.

          #{attach_error.message}
        EOS
      end

      it "preserves the command failure details without chaining the error" do
        error = begin
          unpack_strategy.mount { nil }
        rescue ErrorDuringExecution => e
          e
        end

        expect(error).to have_attributes(cmd: attach_error.cmd, exitstatus: 1, stderr:, cause: nil)
      end

      context "without the disk image warning" do
        let(:stderr) { "hdiutil: attach canceled\n" }

        it "preserves the original cancellation error" do
          expect { unpack_strategy.mount { nil } }.to raise_error(attach_error)
        end
      end

      context "without an attachment cancellation" do
        let(:stderr) { "There may be a problem with this disk image. Are you sure you want to open it?\n" }

        it "preserves the original failure" do
          expect { unpack_strategy.mount { nil } }.to raise_error(attach_error)
        end
      end
    end
  end
end
