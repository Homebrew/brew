# typed: true
# frozen_string_literal: true

RSpec.describe Cask::Artifact::AppImage, :cask do
  let(:cask) { Cask::CaskLoader.from_path(cask_path("with-appimage")) }
  let(:command) { NeverSudoSystemCommand }
  let(:adopt) { false }
  let(:force) { false }
  let(:auto_updates) { false }
  let(:artifact) { cask.artifacts.find { |a| a.is_a?(described_class) } }

  let(:source_path) { cask.staged_path.join("naked.AppImage") }
  let(:target_path) { Pathname(cask.config.appimagedir).join("naked.AppImage") }

  let(:install_phase) { artifact.install_phase(command:, adopt:, force:, auto_updates:) }
  let(:uninstall_phase) { artifact.uninstall_phase(command:, force:) }

  let(:desktop_entry) { xdg_data_home/"applications/naked.desktop" }
  let(:desktop_entry_link) { cask.staged_path/"naked.desktop" }
  let(:xdg_data_home) { mktmpdir }

  let(:setup_cask) { InstallHelper.install_without_artifacts(cask) }

  before do
    ENV["HOMEBREW_XDG_DATA_HOME"] = xdg_data_home.to_s
    setup_cask
  end

  describe "install_phase" do
    it "moves the real AppImage to appimagedir and back-links from the Caskroom" do
      install_phase

      expect(target_path).to be_a_file
      expect(target_path).not_to be_a_symlink
      expect(source_path).to be_a_symlink
      expect(source_path.readlink).to eq(target_path)
    end

    it "makes a non-executable AppImage executable at the target" do
      FileUtils.chmod "-x", source_path
      expect(source_path).not_to be_executable

      install_phase

      expect(target_path).to be_executable
    end

    it "installs the embedded desktop entry, pointing it at the AppImage and its icon" do
      install_phase

      expect(desktop_entry_link.readlink).to eq(desktop_entry)
      expect(cask.staged_path/"naked.png").to be_a_file
      expect(desktop_entry.read).to eq <<~EOS
        [Desktop Entry]
        Type=Application
        Name=Naked
        Exec=env DESKTOPINTEGRATION=1 #{target_path} --flag %U
        TryExec=#{target_path}
        Icon=#{cask.staged_path}/naked.png
        MimeType=x-scheme-handler/naked;
        Actions=new;

        [Desktop Action new]
        Name=New
        Exec=env DESKTOPINTEGRATION=1 #{target_path} --new
      EOS
    end

    describe "when the desktop entry has MIME types" do
      let(:desktop_entry_dir) { xdg_data_home/"applications" }
      let(:update_desktop_database) { Pathname("/usr/bin/update-desktop-database") }

      before do
        desktop_entry_dir.mkpath
        (desktop_entry_dir/"mimeinfo.cache").write("[MIME Cache]\n")
        allow(artifact).to receive(:which).with("update-desktop-database").and_return(update_desktop_database)
        allow(command).to receive(:run).and_call_original
      end

      it "rebuilds an existing mimetype cache" do
        expect(command).to receive(:run).with(update_desktop_database, args: [desktop_entry_dir], print_stderr: false)
        install_phase
      end
    end

    describe "when the AppImage has several root-level `.desktop` files" do
      let(:installed_desktop_entries) { (xdg_data_home/"applications").children.map { |path| path.basename.to_s } }

      before { ENV["NAKED_DESKTOP_ENTRIES"] = "multiple" }

      it "installs only those that are desktop entries" do
        install_phase

        expect(installed_desktop_entries).to contain_exactly("naked.desktop.desktop", "naked-tools.desktop")
      end
    end

    describe "when the desktop entry's icon is not at the root of the AppImage" do
      before { ENV["NAKED_ICON"] = "missing" }

      it "uses the AppImage's extensionless `.DirIcon`, typed by its contents" do
        install_phase

        expect((cask.staged_path/"naked.png").binread).to eq("\x89PNG\r\n".b)
      end
    end

    describe "when a desktop entry already exists" do
      before do
        desktop_entry.dirname.mkpath
        desktop_entry.write("[Desktop Entry]\n")
      end

      it "refuses to overwrite it before moving the AppImage" do
        expect { install_phase }.to raise_error(Cask::CaskError, /already a desktop entry/)
        expect(target_path).not_to exist
      end

      describe "given the force option" do
        let(:force) { true }

        it "overwrites it" do
          install_phase

          expect(desktop_entry.read).to include("Name=Naked")
        end

        describe "when another cask links to it" do
          let(:other_desktop_entry_link) { Cask::Caskroom.path/"other-cask/1.0/naked.desktop" }

          before do
            other_desktop_entry_link.dirname.mkpath
            FileUtils.ln_s desktop_entry, other_desktop_entry_link
          end

          it "takes it over from that cask" do
            install_phase

            expect(other_desktop_entry_link).not_to be_a_symlink
          end
        end
      end

      describe "during an upgrade" do
        let(:install_phase) { artifact.install_phase(command:, predecessor: cask) }

        it "overwrites it" do
          install_phase

          expect(desktop_entry.read).to include("Name=Naked")
        end
      end
    end

    describe "when a self-updater replaces the target in place" do
      it "keeps the Caskroom back-link valid and pointing at the new contents" do
        install_phase

        replacement = "#!/bin/sh\necho \"AppImage v2\"\n"
        File.write(target_path, replacement)

        expect(source_path).to be_a_symlink
        expect(source_path.readlink).to exist
        expect(File.read(source_path)).to eq(replacement)
      end
    end

    describe "given the adopt option" do
      let(:adopt) { true }

      before do
        target_path.dirname.mkpath
        FileUtils.cp source_path, target_path
      end

      it "adopts an identical existing AppImage without auto_updates" do
        install_phase

        expect(target_path).to be_a_file
        expect(source_path).to be_a_symlink
      end

      describe "when the cask auto_updates" do
        let(:auto_updates) { true }

        before do
          File.write(target_path, "#!/bin/sh\necho \"AppImage v2\"\n")
        end

        it "adopts the existing AppImage without comparing contents" do
          install_phase

          expect(target_path).to be_a_file
          expect(source_path).to be_a_symlink
        end
      end
    end
  end

  describe "uninstall_phase" do
    it "removes the target AppImage" do
      install_phase

      expect(target_path).to exist

      uninstall_phase

      expect(target_path).not_to exist
    end

    describe "when the removed desktop entry has MIME types" do
      let(:update_desktop_database) { Pathname("/usr/bin/update-desktop-database") }

      before do
        install_phase
        allow(artifact).to receive(:which).with("update-desktop-database").and_return(update_desktop_database)
        allow(command).to receive(:run).and_call_original
      end

      it "rebuilds an existing mimetype cache" do
        (desktop_entry.dirname/"mimeinfo.cache").write("[MIME Cache]\n")

        expect(command).to receive(:run)
          .with(update_desktop_database, args: [desktop_entry.dirname], print_stderr: false)
        uninstall_phase
      end

      it "doesn't create a mimetype cache" do
        expect(command).not_to receive(:run).with(update_desktop_database, anything)
        uninstall_phase
      end
    end

    it "removes every linked desktop entry" do
      ENV["NAKED_DESKTOP_ENTRIES"] = "multiple"
      install_phase
      uninstall_phase

      expect((xdg_data_home/"applications").children).to be_empty
    end

    describe "migrating from the old Symlinked layout" do
      before do
        # Recreate the pre-inversion on-disk state: a real file in the
        # versioned Caskroom source and a symlink at the target pointing back.
        target_path.dirname.mkpath
        FileUtils.ln_sf source_path, target_path
      end

      it "removes both the target symlink and the Caskroom file without raising" do
        expect(source_path).to be_a_file
        expect(target_path).to be_a_symlink

        expect { uninstall_phase }.not_to raise_error

        expect(target_path).not_to exist
        expect(source_path).not_to exist
      end

      describe "when a self-updater already deleted the versioned source" do
        before do
          # The exact breakage this stanza fixes: `source` is gone and the
          # `target` symlink is left dangling.
          source_path.delete
        end

        it "removes the dangling target without raising" do
          expect(target_path).to be_a_symlink
          expect(target_path).not_to exist
          expect(source_path).not_to exist

          expect { uninstall_phase }.not_to raise_error

          expect(target_path).not_to be_a_symlink
          expect(target_path).not_to exist
        end
      end

      describe "during an upgrade" do
        let(:uninstall_phase) { artifact.uninstall_phase(command:, force:, upgrade: true) }

        it "removes the target symlink but preserves the source for the backup" do
          expect(source_path).to be_a_file
          expect(target_path).to be_a_symlink

          expect { uninstall_phase }.not_to raise_error

          expect(target_path).not_to exist
          expect(source_path).to be_a_file
        end
      end
    end
  end

  describe "summary" do
    let(:contents) { artifact.summarize_installed }

    it "returns the correct english_description" do
      expect(artifact.class.english_description).to eq("App Images")
    end

    describe "AppImage is missing" do
      let(:setup_cask) { nil }

      it "returns a warning and the supposed path to the AppImage" do
        expect(contents).to match(/.*Missing App Image.*: #{target_path}/)
      end
    end

    describe "AppImage is correctly installed" do
      it "returns the path to the AppImage" do
        install_phase

        expect(contents).to eq("#{target_path} (#{target_path.abv})")
      end
    end
  end
end
