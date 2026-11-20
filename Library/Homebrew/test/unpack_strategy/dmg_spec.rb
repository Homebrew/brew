# typed: true
# frozen_string_literal: true

require_relative "shared_examples"

RSpec.describe UnpackStrategy::Dmg do
  describe UnpackStrategy::Dmg::Bom, :needs_macos do
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

  describe "#mount", :needs_macos do
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
      allow(described_class).to receive(:diskutil_image?).and_return(false)
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

  describe "::diskutil_image?", :needs_macos do
    it "is true on macOS 27.2" do
      allow(MacOS).to receive(:full_version).and_return(MacOSVersion.new("27.2"))
      expect(described_class.diskutil_image?).to be true
    end

    it "is false before macOS 27.2" do
      allow(MacOS).to receive(:full_version).and_return(MacOSVersion.new("27.0"))
      expect(described_class.diskutil_image?).to be false
    end
  end

  describe "#mount with diskutil" do
    let(:path) { TEST_FIXTURE_DIR/"cask/container.dmg" }
    let(:license_plist) do
      <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict><key>resource-fork</key><dict>
        <key>LPic</key><array><dict><key>Data</key><data>AAAAAQAAAAAAAAAA</data></dict></array>
        </dict></dict></plist>
      XML
    end

    before { allow(described_class).to receive(:diskutil_image?).and_return(true) }

    def udif_image(name, xml)
      trailer = "koly".b.ljust(512, "\0")
      trailer[216, 16] = [0, xml.bytesize].pack("Q>Q>")
      (mktmpdir/name).tap { |image| image.binwrite(xml.b + trailer) }
    end

    it "attaches without answering a license agreement" do
      unpack_strategy = described_class.new(path)
      attach_result = instance_double(SystemCommand::Result, success?: true, plist: { "system-entities" => [] })

      expect(unpack_strategy).to receive(:system_command).with(
        "diskutil",
        args:         [
          "image", "attach", "--plist", "--readOnly", "--nobrowse",
          "--mountPoint", kind_of(Pathname), unpack_strategy.path
        ],
        env:          { "PAGER" => "true" },
        print_stderr: false,
        verbose:      false,
      ).and_return(attach_result)
      expect(unpack_strategy).not_to receive(:system_command).with("hdiutil", any_args)

      unpack_strategy.mount { |mounts| expect(mounts).to be_empty }
    end

    context "with a license agreement" do
      let(:licensed_path) { udif_image("licensed.dmg", license_plist) }
      let(:raw_image) { satisfy { |image| image.is_a?(Pathname) && image.extname == ".img" } }

      it "strips it with diskutil before attaching" do
        unpack_strategy = described_class.new(licensed_path)
        result = instance_double(SystemCommand::Result, success?: true, plist: { "system-entities" => [] })

        expect(unpack_strategy).to receive(:system_command).with(
          "diskutil",
          args:         ["image", "create", "from", "--format", "RAW", unpack_strategy.path, raw_image],
          env:          { "PAGER" => "true" },
          print_stderr: false,
          verbose:      false,
        ).ordered.and_return(result)
        expect(unpack_strategy).to receive(:system_command).with(
          "diskutil",
          args:         [
            "image", "attach", "--plist", "--readOnly", "--nobrowse",
            "--mountPoint", kind_of(Pathname), raw_image
          ],
          env:          { "PAGER" => "true" },
          print_stderr: false,
          verbose:      false,
        ).ordered.and_return(result)
        expect(unpack_strategy).not_to receive(:system_command).with("hdiutil", any_args)

        unpack_strategy.mount { |mounts| expect(mounts).to be_empty }
      end

      it "strips it when the XML declaration uses single quotes" do
        unpack_strategy = described_class.new(udif_image("quoted.dmg", license_plist.sub('"UTF-8"', "'UTF-8'")))
        result = instance_double(SystemCommand::Result, success?: true, plist: { "system-entities" => [] })

        expect(unpack_strategy).to receive(:system_command)
          .with("diskutil", hash_including(args: array_including("create")))
          .and_return(result)
        allow(unpack_strategy).to receive(:system_command)
          .with("diskutil", hash_including(args: array_including("attach")))
          .and_return(result)

        unpack_strategy.mount { nil }
      end

      it "falls back to hdiutil when diskutil can't strip it" do
        unpack_strategy = described_class.new(licensed_path)
        failed_result = instance_double(SystemCommand::Result, success?: false, stderr: "")
        attach_result = instance_double(SystemCommand::Result, success?: true, plist: { "system-entities" => [] })

        expect(unpack_strategy).to receive(:system_command)
          .with("diskutil", hash_including(args: array_including("create")))
          .ordered
          .and_return(failed_result)
        expect(unpack_strategy).not_to receive(:system_command)
          .with("diskutil", hash_including(args: array_including("attach")))
        expect(unpack_strategy).to receive(:system_command)
          .with("hdiutil", hash_including(input: "qn\n"))
          .ordered
          .and_return(attach_result)

        unpack_strategy.mount { |mounts| expect(mounts).to be_empty }
      end

      it "deletes the RAW copy before falling back to hdiutil" do
        unpack_strategy = described_class.new(licensed_path)
        converted_result = instance_double(SystemCommand::Result, success?: true)
        refused_result = instance_double(SystemCommand::Result, success?: false, stderr: "")
        attach_result = instance_double(SystemCommand::Result, success?: true, plist: { "system-entities" => [] })
        raw_copy = T.let(nil, T.nilable(Pathname))
        raw_copy_kept = T.let(nil, T.nilable(T::Boolean))

        allow(unpack_strategy).to receive(:system_command)
          .with("diskutil", hash_including(args: array_including("create"))) do |_executable, args:, **|
            raw_copy = args.last.tap { |image| image.write("") }
            converted_result
          end
        allow(unpack_strategy).to receive(:system_command)
          .with("diskutil", hash_including(args: array_including("attach")))
          .and_return(refused_result)
        allow(unpack_strategy).to receive(:system_command).with("hdiutil", any_args) do
          raw_copy_kept = raw_copy&.exist?
          attach_result
        end

        unpack_strategy.mount { nil }
        expect(raw_copy_kept).to be false
      end
    end

    it "falls back to hdiutil when diskutil refuses the image" do
      unpack_strategy = described_class.new(path)
      refused_result = instance_double(SystemCommand::Result, success?: false, stderr: "")
      attach_result = instance_double(SystemCommand::Result, success?: true, plist: { "system-entities" => [] })

      expect(unpack_strategy).to receive(:system_command)
        .with("diskutil", any_args)
        .ordered
        .and_return(refused_result)
      expect(unpack_strategy).to receive(:system_command).with(
        "hdiutil",
        args:         [
          "attach", "-plist", "-nobrowse", "-readonly",
          "-mountrandom", kind_of(Pathname), unpack_strategy.path
        ],
        input:        "qn\n",
        print_stderr: false,
        verbose:      false,
      ).ordered.and_return(attach_result)

      unpack_strategy.mount { |mounts| expect(mounts).to be_empty }
    end
  end
end
