# typed: true
# frozen_string_literal: true

RSpec.describe Cask::Artifact::DesktopEntry, :cask do
  let(:cask) { Cask::CaskLoader.from_path(cask_path("with-desktop-entry")) }
  let(:command) { NeverSudoSystemCommand }
  let(:artifact) { cask.artifacts.find { |a| a.is_a?(described_class) } }

  let(:install_phase) { artifact.install_phase(command:) }
  let(:uninstall_phase) { artifact.uninstall_phase(command:) }

  let(:prefix) { cask.staged_path/"Foo" }
  let(:source) { prefix/"share/applications/foo.desktop" }
  let(:program) { prefix/"bin/foo" }
  let(:icons) { prefix/"share/icons/hicolor" }
  let(:desktop_entry) { xdg_data_home/"applications/foo.desktop" }
  let(:xdg_data_home) { mktmpdir }

  before do
    ENV["HOMEBREW_XDG_DATA_HOME"] = xdg_data_home.to_s
    InstallHelper.install_without_artifacts(cask)
    source.dirname.mkpath
    source.write <<~EOS
      [Desktop Entry]
      Type=Application
      Name=Foo
      Exec=foo %U
      TryExec=foo
      Icon=dev.foo.Foo
    EOS
    program.dirname.mkpath
    FileUtils.touch program
    %w[48x48 512x512].each do |size|
      (icons/size/"apps").mkpath
      FileUtils.touch icons/size/"apps/dev.foo.Foo.png"
    end
  end

  it "requires a path in a `share/applications` directory" do
    expect { described_class.new(cask, "foo.desktop") }.to raise_error(Cask::CaskInvalidError)
  end

  it "requires a path within the staged cask" do
    expect { described_class.new(cask, "../share/applications/foo.desktop") }
      .to raise_error(Cask::CaskInvalidError)
  end

  describe "install_phase" do
    it "installs the desktop entry, pointing it at the prefix's program and its largest icon" do
      install_phase

      expect(desktop_entry.read).to eq <<~EOS
        [Desktop Entry]
        Type=Application
        Name=Foo
        Exec=#{program} %U
        TryExec=#{program}
        Icon=#{icons}/512x512/apps/dev.foo.Foo.png
      EOS
    end

    it "prefers a scalable icon" do
      (icons/"scalable/apps").mkpath
      FileUtils.touch icons/"scalable/apps/dev.foo.Foo.svg"

      install_phase

      expect(desktop_entry.read).to include("Icon=#{icons}/scalable/apps/dev.foo.Foo.svg\n")
    end

    it "points each action at its own icon" do
      source.write <<~EOS
        [Desktop Entry]
        Exec=foo
        Icon=dev.foo.Foo
        Actions=new-window;

        [Desktop Action new-window]
        Exec=foo --new-window
        Icon=dev.foo.NewWindow
      EOS
      FileUtils.touch icons/"48x48/apps/dev.foo.NewWindow.png"

      install_phase

      expect(desktop_entry.read).to include("Icon=#{icons}/48x48/apps/dev.foo.NewWindow.png\n")
    end

    it "matches an icon name literally" do
      source.write "[Desktop Entry]\nExec=foo\nIcon=dev.foo.*\n"

      install_phase

      expect(desktop_entry.read).to include("Icon=dev.foo.*\n")
    end

    it "rebuilds the mimetype cache when the entry it replaces had MIME types" do
      update_desktop_database = Pathname("/usr/bin/update-desktop-database")
      desktop_entry.dirname.mkpath
      desktop_entry.write "[Desktop Entry]\nMimeType=application/pdf;\n"
      (desktop_entry.dirname/"mimeinfo.cache").write("[MIME Cache]\n")
      allow(artifact).to receive(:which).with("update-desktop-database").and_return(update_desktop_database)

      expect(command).to receive(:run)
        .with(update_desktop_database, args: [desktop_entry.dirname], print_stderr: false)
      artifact.install_phase(command:, force: true)
    end

    it "raises when the program isn't in the prefix's `bin` directory" do
      program.unlink

      expect { install_phase }.to raise_error(Cask::CaskError, /runs 'foo', which is not at '#{program}'/)
    end

    it "raises when the source links outside the staged cask" do
      outside_desktop_entry = mktmpdir/"foo.desktop"
      FileUtils.mv source, outside_desktop_entry
      source.make_symlink(outside_desktop_entry)

      expect { install_phase }.to raise_error(Cask::CaskError, /links outside/)
    end

    it "raises when the source isn't a desktop entry" do
      source.write "token=hunter2\n"

      expect { install_phase }.to raise_error(Cask::CaskError, /is not a desktop entry/)
    end

    it "raises when an `Exec` is malformed" do
      source.write "[Desktop Entry]\nExec=foo \"%U\n"

      expect { install_phase }.to raise_error(Cask::CaskError, /'#{source}' has a malformed `Exec`/)
    end
  end

  describe "uninstall_phase" do
    it "removes the desktop entry" do
      install_phase
      uninstall_phase

      expect(desktop_entry).not_to exist
    end

    it "leaves the files the staged archive's own `.desktop` links point to" do
      linked_file = mktmpdir/"notes.desktop"
      FileUtils.touch linked_file
      (cask.staged_path/"notes.desktop").make_symlink(linked_file)

      install_phase
      uninstall_phase

      expect(linked_file).to exist
    end
  end
end
