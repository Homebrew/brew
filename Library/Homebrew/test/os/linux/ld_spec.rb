# frozen_string_literal: true

require "os/linux/ld"
require "tmpdir"

RSpec.describe OS::Linux::Ld do
  let(:diagnostics) do
    <<~EOS
      path.prefix="/usr"
      path.sysconfdir="/usr/local/etc"
      path.system_dirs[0x0]="/lib64"
      path.system_dirs[0x1]="/var/lib"
    EOS
  end

  describe "::system_ld_so" do
    let(:ld_so) { "/lib/ld-linux.so.3" }

    before do
      allow(File).to receive(:executable?).and_return(false)
      described_class.instance_variable_set(:@system_ld_so, nil)
    end

    it "returns the path to a known dynamic linker" do
      allow(File).to receive(:executable?).with(ld_so).and_return(true)
      expect(described_class.system_ld_so).to eq(Pathname(ld_so))
    end

    it "returns nil when there is no known dynamic linker" do
      expect(described_class.system_ld_so).to be_nil
    end
  end

  describe "::sysconfdir" do
    it "returns path.sysconfdir" do
      allow(described_class).to receive(:ld_so_diagnostics).and_return(diagnostics)
      expect(described_class.sysconfdir).to eq("/usr/local/etc")
      expect(described_class.sysconfdir(brewed: false)).to eq("/usr/local/etc")
    end

    it "returns fallback on blank diagnostics" do
      allow(described_class).to receive(:ld_so_diagnostics).and_return("")
      expect(described_class.sysconfdir).to eq("/etc")
      expect(described_class.sysconfdir(brewed: false)).to eq("/etc")
    end
  end

  describe "::system_dirs" do
    it "returns all path.system_dirs" do
      allow(described_class).to receive(:ld_so_diagnostics).and_return(diagnostics)
      expect(described_class.system_dirs).to eq(["/lib64", "/var/lib"])
      expect(described_class.system_dirs(brewed: false)).to eq(["/lib64", "/var/lib"])
    end

    it "returns an empty array on blank diagnostics" do
      allow(described_class).to receive(:ld_so_diagnostics).and_return("")
      expect(described_class.system_dirs).to eq([])
      expect(described_class.system_dirs(brewed: false)).to eq([])
    end
  end

  describe "::library_paths" do
    ld_etc = Pathname("")
    before do
      ld_etc = Pathname(Dir.mktmpdir("homebrew-tests-ld-etc-", Dir.tmpdir))
      FileUtils.mkdir [ld_etc/"subdir1", ld_etc/"subdir2"]
      (ld_etc/"ld.so.conf").write <<~EOS
        # This line is a comment

        include #{ld_etc}/subdir1/*.conf # This is an end-of-line comment, should be ignored

        # subdir2 is an empty directory
        include #{ld_etc}/subdir2/*.conf

        /a/b/c
          /d/e/f # Indentation on this line should be ignored
        /a/b/c # Duplicate entry should be ignored
      EOS

      (ld_etc/"subdir1/1-1.conf").write <<~EOS
        /foo/bar
        /baz/qux
      EOS

      (ld_etc/"subdir1/1-2.conf").write <<~EOS
        /g/h/i
      EOS

      # Empty files (or files containing only whitespace) should be ignored
      (ld_etc/"subdir1/1-3.conf").write "\n\t\n\t\n"
      (ld_etc/"subdir1/1-4.conf").write ""
    end

    after do
      FileUtils.rm_rf ld_etc
    end

    it "parses library paths successfully" do
      expect(described_class.library_paths(ld_etc/"ld.so.conf")).to eq(%w[/foo/bar /baz/qux /g/h/i /a/b/c /d/e/f])
    end
  end
end
