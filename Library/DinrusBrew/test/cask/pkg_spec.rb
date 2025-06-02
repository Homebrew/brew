# frozen_string_literal: true

RSpec.describe Cask::Pkg, :cask do
  describe "#uninstall" do
    let(:fake_system_command) { NeverSudoSystemCommand }
    let(:empty_response) do
      instance_double(
        SystemCommand::Result,
        stdout: "",
        plist:  { "volume" => "/", "install-location" => "", "paths" => {} },
      )
    end
    let(:pkg) { described_class.new("my.fake.pkg", fake_system_command) }

    it "removes files and dirs referenced by the pkg" do
      some_files = Array.new(3) { Pathname.new(Tempfile.new("plain_file").path) }

      some_specials = Array.new(3) { Pathname.new(Tempfile.new("special_file").path) }

      some_dirs = Array.new(3) { mktmpdir }

      root_dir = Pathname.new(mktmpdir)
      allow(pkg).to receive_messages(pkgutil_bom_files: some_files, pkgutil_bom_specials: some_specials,
                                     pkgutil_bom_dirs: some_dirs, root: root_dir)

      allow(pkg).to receive(:forget)

      pkg.uninstall

      some_files.each do |file|
        expect(file).not_to exist
      end

      some_specials.each do |file|
        expect(file).not_to exist
      end

      some_dirs.each do |dir|
        expect(dir).not_to exist
      end

      expect(root_dir).not_to exist
    ensure
      some_files&.each { |path| FileUtils.rm_rf(path) }
      some_specials&.each { |path| FileUtils.rm_rf(path) }
      some_dirs&.each { |path| FileUtils.rm_rf(path) }
      FileUtils.rm_rf(root_dir) if root_dir
    end

    describe "pkgutil" do
      it "forgets the pkg" do
        allow(fake_system_command).to receive(:run!).with(
          "/usr/sbin/pkgutil",
          args: ["--pkg-info-plist", "my.fake.pkg"],
        ).and_return(empty_response)

        expect(fake_system_command).to receive(:run!).with(
          "/usr/sbin/pkgutil",
          args: ["--files", "my.fake.pkg"],
        ).and_return(empty_response)

        expect(fake_system_command).to receive(:run!).with(
          "/usr/sbin/pkgutil",
          args:         ["--forget", "my.fake.pkg"],
          sudo:         true,
          sudo_as_root: true,
        )

        pkg.uninstall
      end
    end

    it "removes broken symlinks" do
      fake_root = mktmpdir
      fake_dir  = mktmpdir
      fake_file = fake_dir.join("ima_file").tap do |path|
        FileUtils.touch(path)
      end

      intact_symlink = fake_dir.join("intact_symlink").tap { |path| path.make_symlink(fake_file) }
      broken_symlink = fake_dir.join("broken_symlink").tap { |path| path.make_symlink("im_nota_file") }

      allow(pkg).to receive_messages(pkgutil_bom_specials: [], pkgutil_bom_files: [], pkgutil_bom_dirs: [fake_dir],
                                     root: fake_root)
      allow(pkg).to receive(:forget)

      pkg.uninstall

      expect(intact_symlink).to exist
      expect(broken_symlink).not_to exist
      expect(fake_dir).to exist
      expect(fake_root).not_to exist
    ensure
      FileUtils.rm_rf(fake_dir) if fake_dir
      FileUtils.rm_rf(fake_root) if fake_root
    end

    it "snags permissions on ornery dirs, but returns them afterwards" do
      fake_root = mktmpdir
      fake_dir = mktmpdir
      fake_file = fake_dir.join("ima_unrelated_file").tap { |path| FileUtils.touch(path) }
      fake_dir.chmod(0000)

      allow(pkg).to receive_messages(pkgutil_bom_specials: [], pkgutil_bom_files: [], pkgutil_bom_dirs: [fake_dir],
                                     root: fake_root)
      allow(pkg).to receive(:forget)

      # This is expected to fail in tests since we don't use `sudo`.
      allow(fake_system_command).to receive(:run!).and_call_original
      expect(fake_system_command).to receive(:run!).with(
        "/usr/bin/xargs",
        args:         ["-0", "--", a_string_including("rmdir")],
        input:        [fake_dir].join("\0"),
        sudo:         true,
        sudo_as_root: true,
      ).and_return(instance_double(SystemCommand::Result, stdout: ""))

      pkg.uninstall

      expect(fake_dir).to be_a_directory
      expect((fake_dir.stat.mode % 01000)).to eq(0)

      fake_dir.chmod(0777)
      expect(fake_file).to be_a_file
    ensure
      if fake_dir
        fake_dir.chmod(0777)
        FileUtils.rm_rf(fake_dir)
      end
      FileUtils.rm_rf(fake_root) if fake_root
    end
  end

  describe "#info" do
    let(:fake_system_command) { class_double(SystemCommand) }

    let(:volume) { "/" }
    let(:install_location) { "tmp" }

    let(:pkg_id) { "my.fancy.package.main" }

    let(:pkg_files) do
      %w[
        fancy/bin/fancy.exe
        fancy/var/fancy.data
      ]
    end
    let(:pkg_directories) do
      %w[
        fancy
        fancy/bin
        fancy/var
      ]
    end

    let(:pkg_info_plist) do
      <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>install-location</key>
          <string>#{install_location}</string>
          <key>volume</key>
          <string>#{volume}</string>
          <key>paths</key>
          <dict>
            #{(pkg_files + pkg_directories).map { |f| "<key>#{f}</key><dict></dict>" }.join}
          </dict>
        </dict>
        </plist>
      XML
    end

    it "correctly parses a Property List" do
      pkg = described_class.new(pkg_id, fake_system_command)

      expect(fake_system_command).to receive(:run!).with(
        "/usr/sbin/pkgutil",
        args: ["--pkg-info-plist", pkg_id],
      ).and_return(
        SystemCommand::Result.new(
          ["/usr/sbin/pkgutil", "--pkg-info-plist", pkg_id],
          [[:stdout, pkg_info_plist]],
          instance_double(Process::Status, exitstatus: 0),
          secrets: [],
        ),
      )

      info = pkg.info

      expect(info["install-location"]).to eq(install_location)
      expect(info["volume"]).to eq(volume)
      expect(info["paths"].keys).to eq(pkg_files + pkg_directories)
    end
  end
end
