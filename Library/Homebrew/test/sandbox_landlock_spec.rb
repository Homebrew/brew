# typed: true
# frozen_string_literal: true

require "sandbox"
require "extend/os/linux/sandbox/landlock"

RSpec.describe Sandbox::Landlock do
  subject(:landlock) { described_class.new(sandbox.send(:profile)) }

  let(:sandbox) { Sandbox.new }

  around do |example|
    described_class.reset_state!
    example.run
  ensure
    described_class.reset_state!
  end

  describe "::available?" do
    it "declares its weaker write-isolation contract" do
      expect(described_class.full_write_isolation?).to be(false)
    end

    it "reports the supported Landlock ABI" do
      allow(described_class).to receive(:landlock_create_ruleset).with(nil, 0, 1).and_return(4)

      expect(described_class).to be_available
      expect(described_class.state).to eq(:available)
      expect(described_class.abi_version).to eq(4)
      expect(described_class.failure_reason).to be_nil
    end

    it "returns false for a kernel without Landlock support" do
      allow(described_class).to receive(:landlock_create_ruleset).with(nil, 0, 1).and_return(-1)
      allow(described_class).to receive(:last_error).and_return(Errno::ENOSYS::Errno)

      expect(described_class).not_to be_available
      expect(described_class.state).to eq(:unsupported)
      expect(described_class.failure_reason).to include("not supported by this Linux kernel")
    end

    it "returns false when Landlock is disabled by the kernel configuration" do
      allow(described_class).to receive(:landlock_create_ruleset).with(nil, 0, 1).and_return(-1)
      allow(described_class).to receive(:last_error).and_return(Errno::EOPNOTSUPP::Errno)

      expect(described_class).not_to be_available
      expect(described_class.state).to eq(:disabled)
      expect(described_class.failure_reason).to include("disabled by this Linux kernel")
    end

    it "returns false when Linux sandboxing is disabled" do
      allow(Homebrew::EnvConfig).to receive(:sandbox_linux?).and_return(false)

      expect(described_class).not_to be_available
      expect(described_class.state).to eq(:config_disabled)
    end

    it "returns false when Fiddle is unavailable" do
      allow(described_class).to receive(:require).with("fiddle").and_raise(LoadError)

      expect(described_class).not_to be_available
      expect(described_class.state).to eq(:missing_fiddle)
      expect(described_class.failure_reason).to include("Fiddle")
    end

    it "returns false for an ABI without truncate restrictions" do
      allow(described_class).to receive(:landlock_create_ruleset).with(nil, 0, 1).and_return(2)

      expect(described_class).not_to be_available
      expect(described_class.state).to eq(:unsupported_abi)
      expect(described_class.abi_version).to eq(2)
      expect(described_class.failure_reason).to eq("Landlock ABI 3 or later is required; found ABI 2.")
    end

    it "only raises when explicitly configuring unavailable Landlock" do
      allow(described_class).to receive_messages(available?: false, failure_reason: "Landlock is not available.")

      expect { described_class.ensure_installed! }.not_to raise_error
      expect { described_class.configure! }.to raise_error(RuntimeError, "Landlock is not available.")
    end
  end

  describe "::kernel_abi_version" do
    it "reports the kernel ABI even when Linux sandboxing is disabled" do
      allow(Homebrew::EnvConfig).to receive(:sandbox_linux?).and_return(false)
      allow(described_class).to receive(:landlock_create_ruleset).with(nil, 0, 1).and_return(6)

      expect(described_class.kernel_abi_version).to eq(6)
    end

    it "returns nil for a kernel without Landlock support" do
      allow(described_class).to receive(:landlock_create_ruleset).with(nil, 0, 1).and_return(-1)

      expect(described_class.kernel_abi_version).to be_nil
    end

    it "returns nil when Fiddle function setup fails" do
      require "fiddle"
      allow(described_class).to receive(:landlock_create_ruleset).and_raise(Fiddle::DLError)

      expect(described_class.kernel_abi_version).to be_nil
    end
  end

  describe "#apply!" do
    let(:writable_dir) { mktmpdir }
    let(:tmpdir) { mktmpdir }

    before do
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?).with("/dev/full").and_return(false)
      allow(File).to receive(:exist?).with("/dev/mqueue").and_return(false)
      allow(File).to receive(:exist?).with("/dev/ptmx").and_return(true)
      allow(File).to receive(:exist?).with("/dev/pts").and_return(true)
      allow(File).to receive(:exist?).with("/dev/shm").and_return(false)
      allow(File).to receive(:exist?).with("/dev/tty").and_return(false)
    end

    it "rejects an ABI without complete write restrictions" do
      allow(described_class).to receive_messages(abi_version:    2,
                                                 failure_reason: "Landlock ABI 3 or later is required; found ABI 2.")
      expect(described_class).not_to receive(:landlock_create_ruleset)

      expect { landlock.apply! }
        .to raise_error(RuntimeError, "Landlock ABI 3 or later is required; found ABI 2.")
    end

    it "restricts writes and network access using the supported ABI" do
      sandbox.allow_write_path writable_dir
      sandbox.deny_all_network
      landlock.command(["true"], tmpdir.to_s)

      allow(described_class).to receive(:abi_version).and_return(10)
      expect(described_class).to receive(:landlock_create_ruleset) do |attributes, size, flags|
        expect(attributes.unpack("Q3")).to eq([131_058, 15, 1])
        expect(size).to eq(24)
        expect(flags).to eq(0)
        17
      end
      allow(landlock).to receive(:open_path).with(writable_dir.to_s).and_return(18)
      expect(landlock).to receive(:open_path).with(File::NULL).and_return(19)
      allow(landlock).to receive(:open_path).with(tmpdir.to_s).and_return(20)
      expect(landlock).to receive(:open_path).with("#{tmpdir}/socket").and_return(21)
      expect(landlock).to receive(:open_path).with("/dev/ptmx").and_return(22)
      expect(landlock).to receive(:open_path).with("/dev/pts").and_return(23)
      path_rules = []
      expect(described_class).to receive(:landlock_add_rule).exactly(6).times do |ruleset_fd, type, attributes, flags|
        expect(ruleset_fd).to eq(17)
        expect(type).to eq(1)
        expect(attributes.bytesize).to eq(12)
        path_rules << attributes.unpack("Ql")
        expect(flags).to eq(0)
        0
      end
      expect(described_class).to receive(:set_no_new_privileges).and_return(0)
      expect(described_class).to receive(:landlock_restrict_self).with(17, 0).and_return(0)
      expect(landlock).to receive(:close_file_descriptor).with(22).ordered
      expect(landlock).to receive(:close_file_descriptor).with(23).ordered
      expect(landlock).to receive(:close_file_descriptor).with(21).ordered
      expect(landlock).to receive(:close_file_descriptor).with(18).ordered
      expect(landlock).to receive(:close_file_descriptor).with(19).ordered
      expect(landlock).to receive(:close_file_descriptor).with(20).ordered
      expect(landlock).to receive(:close_file_descriptor).with(17).ordered

      landlock.apply!

      expect(path_rules).to eq([
        [32_770, 22], [32_770, 23], [65_536, 21], [32_754, 18], [16_386, 19], [32_754, 20]
      ])
    end

    it "handles reads, directory listings, and execution outside denied hierarchies" do
      readable_dir = mktmpdir
      readable_file = readable_dir/"file"
      readable_file.write("content")
      denied_dir = mktmpdir
      sandbox.deny_read_path denied_dir
      allow(landlock).to receive(:readable_paths).with([denied_dir])
                                                 .and_return([readable_dir.to_s, readable_file.to_s])
      landlock.command(["true"], tmpdir.to_s)

      allow(described_class).to receive(:abi_version).and_return(10)
      expect(described_class).to receive(:landlock_create_ruleset) do |attributes, size, flags|
        expect(attributes.unpack("Q")).to eq([65_535])
        expect(size).to eq(8)
        expect(flags).to eq(0)
        17
      end
      expect(landlock).to receive(:open_path).with(readable_dir.to_s).and_return(18)
      expect(landlock).to receive(:open_path).with(readable_file.to_s).and_return(19)
      expect(landlock).to receive(:open_path).with(File::NULL).and_return(20)
      expect(landlock).to receive(:open_path).with(tmpdir.to_s).and_return(21)
      expect(landlock).to receive(:open_path).with("/dev/ptmx").and_return(22)
      expect(landlock).to receive(:open_path).with("/dev/pts").and_return(23)
      path_rules = []
      expect(described_class).to receive(:landlock_add_rule).exactly(6).times do |ruleset_fd, type, attributes, flags|
        expect(ruleset_fd).to eq(17)
        expect(type).to eq(1)
        path_rules << attributes.unpack("Ql")
        expect(flags).to eq(0)
        0
      end
      expect(described_class).to receive(:set_no_new_privileges).and_return(0)
      expect(described_class).to receive(:landlock_restrict_self).with(17, 0).and_return(0)
      allow(landlock).to receive(:close_file_descriptor)

      landlock.apply!

      expect(path_rules).to eq([
        [32_774, 22], [32_774, 23], [13, 18], [5, 19], [16_386, 20], [32_754, 21]
      ])
    end

    it "allows pseudo-terminal device access" do
      landlock.command(["true"], tmpdir.to_s)

      allow(described_class).to receive_messages(abi_version: 10, landlock_create_ruleset: 17,
                                                 landlock_add_rule: 0, set_no_new_privileges: 0,
                                                 landlock_restrict_self: 0)
      allow(landlock).to receive(:open_path).and_return(18)
      allow(landlock).to receive(:close_file_descriptor)
      expect(landlock).to receive(:open_path).with("/dev/ptmx").and_return(19)
      expect(landlock).to receive(:open_path).with("/dev/pts").and_return(20)
      expect(described_class).to receive(:landlock_add_rule)
        .with(17, 1, [32_770, 19].pack("Ql"), 0).and_return(0)
      expect(described_class).to receive(:landlock_add_rule)
        .with(17, 1, [32_770, 20].pack("Ql"), 0).and_return(0)

      landlock.apply!
    end

    it "allows standard device and POSIX IPC paths" do
      denied_dir = mktmpdir
      sandbox.deny_read_path denied_dir
      allow(landlock).to receive(:readable_paths).with([denied_dir]).and_return([])
      landlock.command(["true"], tmpdir.to_s)

      allow(File).to receive(:exist?).with("/dev/full").and_return(true)
      allow(File).to receive(:exist?).with("/dev/mqueue").and_return(true)
      allow(File).to receive(:exist?).with("/dev/shm").and_return(true)
      allow(File).to receive(:exist?).with("/dev/tty").and_return(true)
      allow(described_class).to receive_messages(abi_version: 10, landlock_create_ruleset: 17,
                                                 landlock_add_rule: 0, set_no_new_privileges: 0,
                                                 landlock_restrict_self: 0)
      allow(landlock).to receive(:open_path).and_return(18)
      allow(landlock).to receive(:close_file_descriptor)
      {
        "/dev/full"   => [16_386, 19],
        "/dev/mqueue" => [32_754, 20],
        "/dev/shm"    => [32_754, 21],
        "/dev/tty"    => [32_774, 22],
      }.each do |path, (access, file_descriptor)|
        expect(landlock).to receive(:open_path).with(path).and_return(file_descriptor)
        expect(described_class).to receive(:landlock_add_rule)
          .with(17, 1, [access, file_descriptor].pack("Ql"), 0).and_return(0)
      end

      landlock.apply!
    end

    it "skips unavailable device and IPC paths" do
      landlock.command(["true"], tmpdir.to_s)

      allow(File).to receive(:exist?).with("/dev/full").and_return(false)
      allow(File).to receive(:exist?).with("/dev/mqueue").and_return(false)
      allow(File).to receive(:exist?).with("/dev/ptmx").and_return(false)
      allow(File).to receive(:exist?).with("/dev/pts").and_return(false)
      allow(File).to receive(:exist?).with("/dev/shm").and_return(false)
      allow(File).to receive(:exist?).with("/dev/tty").and_return(false)
      allow(described_class).to receive_messages(abi_version: 10, landlock_create_ruleset: 17,
                                                 landlock_add_rule: 0, set_no_new_privileges: 0,
                                                 landlock_restrict_self: 0)
      allow(landlock).to receive(:open_path).and_return(18)
      allow(landlock).to receive(:close_file_descriptor)
      expect(landlock).not_to receive(:open_path).with("/dev/full")
      expect(landlock).not_to receive(:open_path).with("/dev/mqueue")
      expect(landlock).not_to receive(:open_path).with("/dev/ptmx")
      expect(landlock).not_to receive(:open_path).with("/dev/pts")
      expect(landlock).not_to receive(:open_path).with("/dev/shm")
      expect(landlock).not_to receive(:open_path).with("/dev/tty")

      landlock.apply!
    end

    context "with an older ABI" do
      before do
        allow(landlock).to receive(:open_path).and_return(18)
        allow(described_class).to receive_messages(abi_version: 7, landlock_create_ruleset: 17, landlock_add_rule: 0,
                                                   set_no_new_privileges: 0, landlock_restrict_self: 0)
        allow(landlock).to receive(:close_file_descriptor)
      end

      it "warns when applying incomplete network denial" do
        sandbox.deny_all_network
        landlock.command(["true"], tmpdir.to_s)

        expect { landlock.apply! }
          .to output(/Landlock ABI 10 or later is required to deny all network access; found ABI 7/).to_stderr
      end

      it "does not warn before applying network denial" do
        sandbox.deny_all_network

        expect { landlock.command(["true"], tmpdir.to_s) }.not_to output.to_stderr
      end

      it "does not warn without network denial" do
        landlock.command(["true"], tmpdir.to_s)

        expect { landlock.apply! }.not_to output.to_stderr
      end

      it "uses the supported network access rights" do
        sandbox.deny_all_network
        landlock.command(["true"], tmpdir.to_s)

        attributes, = landlock.send(:ruleset_attributes, 7)

        expect(attributes.unpack("Q3")).to eq([65_522, 3, 1])
      end
    end
  end

  describe "#command" do
    it "prepares missing writable directories and removes them after running" do
      writable_dir = mktmpdir/"created"
      sandbox.allow_write_path writable_dir

      expect(landlock.command(["true"], mktmpdir.to_s)).to eq(["true"])
      expect(writable_dir).to be_a_directory

      landlock.run { nil }

      expect(writable_dir).not_to exist
    end

    it "rejects regex path filters" do
      sandbox.allow_write path: "^/tmp/homebrew-[^/]+$", type: :regex

      expect { landlock.command(["true"], mktmpdir.to_s) }
        .to raise_error(ArgumentError, /Linux sandbox does not support regex path filters/)
    end

    it "allows reading paths outside denied hierarchies" do
      root = mktmpdir
      readable_dir = root/"readable"
      denied_dir = root/"denied"
      readable_dir.mkpath
      denied_dir.mkpath
      allow(landlock).to receive(:root_path).and_return(root)

      expect(landlock.send(:readable_paths, [denied_dir])).to eq([readable_dir.to_s])
    end

    it "does not allow a symlink alias into a denied hierarchy" do
      root = mktmpdir
      denied_dir = root/"denied"
      denied_dir.mkpath
      alias_path = root/"alias"
      alias_path.make_symlink(denied_dir)
      allow(landlock).to receive(:root_path).and_return(root)

      expect(landlock.send(:readable_paths, [denied_dir])).to be_empty
    end

    it "skips dangling symlinks" do
      root = mktmpdir
      denied_dir = root/"denied"
      denied_dir.mkpath
      dangling_path = root/"dangling"
      dangling_path.make_symlink(root/"missing")
      allow(landlock).to receive(:root_path).and_return(root)

      expect(landlock.send(:readable_paths, [denied_dir])).to be_empty
    end
  end
end
