# frozen_string_literal: true

RSpec.describe Cask::Artifact::App, :cask do
  let(:cask) { Cask::CaskLoader.load(cask_path("local-caffeine")) }
  let(:command) { NeverSudoSystemCommand }
  let(:adopt) { false }
  let(:force) { false }
  let(:auto_updates) { false }
  let(:app) { cask.artifacts.find { |a| a.is_a?(described_class) } }

  let(:source_path) { cask.staged_path.join("Caffeine.app") }
  let(:target_path) { cask.config.appdir.join("Caffeine.app") }

  let(:install_phase) { app.install_phase(command:, adopt:, force:, auto_updates:) }
  let(:uninstall_phase) { app.uninstall_phase(command:, force:) }

  before do
    InstallHelper.install_without_artifacts(cask)
  end

  describe "install_phase" do
    it "installs the given app using the proper target directory" do
      install_phase

      expect(target_path).to be_a_directory
      expect(source_path).to be_a_symlink
    end

    describe "when app is in a subdirectory" do
      let(:cask) do
        Cask::Cask.new("subdir") do
          url "file://#{TEST_FIXTURE_DIR}/cask/caffeine.zip"
          homepage "https://brew.sh/local-caffeine"
          version "1.2.3"
          sha256 "67cdb8a02803ef37fdbf7e0be205863172e41a561ca446cd84f0d7ab35a99d94"
          app "subdir/Caffeine.app"
        end
      end

      it "installs the given app using the proper target directory" do
        appsubdir = cask.staged_path.join("subdir").tap(&:mkpath)
        FileUtils.mv(source_path, appsubdir)

        install_phase

        expect(target_path).to be_a_directory
        expect(appsubdir.join("Caffeine.app")).to be_a_symlink
      end
    end

    it "only uses apps when they are specified" do
      staged_app_copy = source_path.sub("Caffeine.app", "Caffeine Deluxe.app")
      FileUtils.cp_r source_path, staged_app_copy

      install_phase

      expect(target_path).to be_a_directory
      expect(source_path).to be_a_symlink

      expect(cask.config.appdir.join("Caffeine Deluxe.app")).not_to exist
      expect(cask.staged_path.join("Caffeine Deluxe.app")).to exist
    end

    describe "when the target already exists" do
      before do
        target_path.mkpath
      end

      it "avoids clobbering an existing app" do
        expect { install_phase }.to raise_error(
          Cask::CaskError,
          "It seems there is already an App at '#{target_path}'.",
        )

        expect(source_path).to be_a_directory
        expect(target_path).to be_a_directory
        expect(File.identical?(source_path, target_path)).to be false

        contents_path = target_path.join("Contents/Info.plist")
        expect(contents_path).not_to exist
      end

      describe "given the adopt option" do
        let(:adopt) { true }

        describe "when the target compares different from the source" do
          describe "when the cask does not auto_updates" do
            it "avoids clobbering the existing app if brew manages updates" do
              stdout = <<~EOS
                ==> Adopting existing App at '#{target_path}'
              EOS

              expect { install_phase }
                .to output(stdout).to_stdout
                .and raise_error(
                  Cask::CaskError,
                  "It seems the existing App is different from the one being installed.",
                )

              expect(source_path).to be_a_directory
              expect(target_path).to be_a_directory
              expect(File.identical?(source_path, target_path)).to be false

              contents_path = target_path.join("Contents/Info.plist")
              expect(contents_path).not_to exist
            end
          end

          describe "when the cask auto_updates" do
            before do
              target_path.delete
              FileUtils.cp_r source_path, target_path
              File.write(target_path.join("Contents/Info.plist"), "different")
            end

            let(:auto_updates) { true }

            it "adopts the existing app" do
              stdout = <<~EOS
                ==> Adopting existing App at '#{target_path}'
              EOS

              stderr = ""

              expect { install_phase }
                .to output(stdout).to_stdout
                .and output(stderr).to_stderr

              expect(source_path).to be_a_symlink
              expect(target_path).to be_a_directory

              contents_path = target_path.join("Contents/Info.plist")
              expect(contents_path).to exist
              expect(File.read(contents_path)).to eq("different")
            end
          end
        end

        describe "when the target compares the same as the source" do
          before do
            target_path.delete
            FileUtils.cp_r source_path, target_path
          end

          it "adopts the existing app" do
            stdout = <<~EOS
              ==> Adopting existing App at '#{target_path}'
            EOS

            stderr = ""

            expect { install_phase }
              .to output(stdout).to_stdout
              .and output(stderr).to_stderr

            expect(source_path).to be_a_symlink
            expect(target_path).to be_a_directory

            contents_path = target_path.join("Contents/Info.plist")
            expect(contents_path).to exist
          end
        end
      end

      describe "given the force option" do
        let(:force) { true }

        before do
          allow(User).to receive(:current).and_return(User.new("fake_user"))
        end

        describe "target is both writable and user-owned" do
          it "overwrites the existing app" do
            stdout = <<~EOS
              ==> Removing App '#{target_path}'
              ==> Moving App 'Caffeine.app' to '#{target_path}'
            EOS

            stderr = <<~EOS
              Warning: It seems there is already an App at '#{target_path}'; overwriting.
            EOS

            expect { install_phase }
              .to output(stdout).to_stdout
              .and output(stderr).to_stderr

            expect(source_path).to be_a_symlink
            expect(target_path).to be_a_directory

            contents_path = target_path.join("Contents/Info.plist")
            expect(contents_path).to exist
          end
        end

        describe "target is user-owned but contains read-only files" do
          before do
            FileUtils.touch "#{target_path}/foo"
            FileUtils.chmod 0555, target_path
          end

          after do
            FileUtils.chmod 0755, target_path
          end

          it "overwrites the existing app" do
            expect(command).to receive(:run).and_call_original.at_least(:once)

            stdout = <<~EOS
              ==> Removing App '#{target_path}'
              ==> Moving App 'Caffeine.app' to '#{target_path}'
            EOS

            stderr = <<~EOS
              Warning: It seems there is already an App at '#{target_path}'; overwriting.
            EOS

            expect { install_phase }
              .to output(stdout).to_stdout
              .and output(stderr).to_stderr

            expect(source_path).to be_a_symlink
            expect(target_path).to be_a_directory

            contents_path = target_path.join("Contents/Info.plist")
            expect(contents_path).to exist
          end
        end
      end
    end

    describe "when the target is a broken symlink" do
      let(:deleted_path) { cask.staged_path.join("Deleted.app") }

      before do
        deleted_path.mkdir
        File.symlink(deleted_path, target_path)
        deleted_path.rmdir
      end

      it "leaves the target alone" do
        expect { install_phase }.to raise_error(
          Cask::CaskError, "It seems there is already an App at '#{target_path}'."
        )
        expect(target_path).to be_a_symlink
      end

      describe "given the force option" do
        let(:force) { true }

        it "overwrites the existing app" do
          stdout = <<~EOS
            ==> Removing App '#{target_path}'
            ==> Moving App 'Caffeine.app' to '#{target_path}'
          EOS

          stderr = <<~EOS
            Warning: It seems there is already an App at '#{target_path}'; overwriting.
          EOS

          expect { install_phase }
            .to output(stdout).to_stdout
            .and output(stderr).to_stderr

          expect(source_path).to be_a_symlink
          expect(target_path).to be_a_directory

          contents_path = target_path.join("Contents/Info.plist")
          expect(contents_path).to exist
        end
      end
    end

    it "gives a warning if the source doesn't exist" do
      FileUtils.rm_r(source_path)

      message = "It seems the App source '#{source_path}' is not there."

      expect { install_phase }.to raise_error(Cask::CaskError, message)
    end
  end

  describe "uninstall_phase" do
    after do
      FileUtils.chmod 0755, target_path if target_path.exist?
      FileUtils.chmod 0755, source_path if source_path.exist?
    end

    it "deletes managed apps" do
      install_phase

      expect(target_path).to exist

      uninstall_phase

      expect(target_path).not_to exist
    end

    it "backs up read-only managed apps" do
      install_phase

      FileUtils.chmod 0544, target_path

      uninstall_phase

      expect(source_path).to be_a_directory
    end
  end

  describe "summary" do
    let(:description) { app.class.english_description }
    let(:contents) { app.summarize_installed }

    it "returns the correct english_description" do
      expect(description).to eq("Apps")
    end

    describe "app is correctly installed" do
      it "returns the path to the app" do
        install_phase

        expect(contents).to eq("#{target_path} (#{target_path.abv})")
      end
    end

    describe "app is missing" do
      it "returns a warning and the supposed path to the app" do
        expect(contents).to match(/.*Missing App.*: #{target_path}/)
      end
    end
  end

  describe "upgrade" do
    before do
      install_phase
    end

    # Fix for https://github.com/Homebrew/homebrew-cask/issues/102721
    it "reuses the same directory" do
      contents_path = target_path.join("Contents/Info.plist")

      expect(target_path).to exist
      inode = target_path.stat.ino
      expect(contents_path).to exist

      app.uninstall_phase(command:, force:, successor: cask)

      expect(target_path).to exist
      expect(target_path.children).to be_empty
      expect(contents_path).not_to exist

      app.install_phase(command:, adopt:, force:, predecessor: cask)
      expect(target_path).to exist
      expect(target_path.stat.ino).to eq(inode)

      expect(contents_path).to exist
    end

    describe "when the system blocks modifying apps" do
      it "uninstalls and reinstalls the app" do
        target_contents_path = target_path.join("Contents")

        expect(File).to receive(:write).with(target_path / ".homebrew-write-test",
                                             instance_of(String)).and_raise(Errno::EACCES)

        app.uninstall_phase(command:, force:, successor: cask)
        expect(target_path).not_to exist

        app.install_phase(command:, adopt:, force:, predecessor: cask)
        expect(target_contents_path).to exist
      end
    end

    describe "when the directory is owned by root" do
      before do
        allow(app.target).to receive_messages(writable?: false, owned?: false)
      end

      it "reuses the same directory" do
        source_contents_path = source_path.join("Contents")
        target_contents_path = target_path.join("Contents")

        allow(command).to receive(:run!).with(any_args).and_call_original

        expect(command).to receive(:run!)
          .with("/bin/cp", args: ["-pR", source_contents_path, target_path],
                           sudo: true)
          .and_call_original
        expect(FileUtils).not_to receive(:move).with(source_contents_path, an_instance_of(Pathname))

        app.uninstall_phase(command:, force:, successor: cask)
        expect(target_contents_path).not_to exist
        expect(target_path).to exist
        expect(source_contents_path).to exist

        app.install_phase(command:, adopt:, force:, predecessor: cask)
        expect(target_contents_path).to exist
      end

      describe "when the system blocks modifying apps" do
        it "uninstalls and reinstalls the app" do
          target_contents_path = target_path.join("Contents")

          allow(command).to receive(:run!).with(any_args).and_call_original

          expect(command).to receive(:run!)
            .with("touch", args:         [target_path / ".homebrew-write-test"],
                           print_stderr: false,
                           sudo:         true)
            .and_raise(ErrorDuringExecution.new([], status: 1,
output: [[:stderr, "touch: #{target_path}/.homebrew-write-test: Operation not permitted\n"]], secrets: []))

          app.uninstall_phase(command:, force:, successor: cask)
          expect(target_path).not_to exist

          app.install_phase(command:, adopt:, force:, predecessor: cask)
          expect(target_contents_path).to exist
        end
      end
    end
  end
end
