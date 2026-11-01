# typed: true
# frozen_string_literal: true

RSpec.describe Cask::Artifact::App, :cask do
  let(:cask) { Cask::CaskLoader.from_path(cask_path("local-caffeine")) }
  let(:command) { NeverSudoSystemCommand }
  let(:adopt) { false }
  let(:force) { false }
  let(:auto_updates) { false }
  let(:app) { cask.artifacts.find { |a| a.is_a?(described_class) } }

  let(:source_path) { cask.staged_path.join("Caffeine.app") }
  let(:target_path) { Pathname(cask.config.appdir).join("Caffeine.app") }

  let(:install_phase) { app.install_phase(command:, adopt:, force:, auto_updates:) }
  let(:uninstall_phase) { app.uninstall_phase(command:, force:) }

  let(:setup_cask) { InstallHelper.install_without_artifacts(cask) }

  before do
    setup_cask
    allow(command).to receive(:run).and_call_original
    allow(SystemCommand).to receive(:run).and_call_original
    allow(SystemCommand).to receive(:run).with("chgrp", any_args)
                                         .and_return(instance_double(SystemCommand::Result, success?: true))
  end

  describe "install_phase" do
    context "with postflight script permissions" do
      let(:cask) do
        Cask::Cask.new("with-script-permissions") do
          version "1.2.3"
          sha256 :no_check
          url "file://#{TEST_FIXTURE_DIR}/cask/caffeine.zip"
          app "caffeine_darwin", target: "Renamed App.app"
        end
      end
      let(:target_path) { cask.config.appdir/"Renamed App.app" }
      let(:source_path) { cask.staged_path/"caffeine_darwin" }
      let(:prepared_steps) { [] }

      before do
        FileUtils.mv(cask.staged_path/"Caffeine.app", source_path)
        %w[installer.sh uninstaller.sh].each do |name|
          (source_path/name).write "#!/bin/sh\n"
          (source_path/name).chmod 0644
        end
        sandbox = instance_double(Sandbox).as_null_object
        allow(Sandbox).to receive_messages(available?: true, new: sandbox, avoid_nested_sandboxing?: false)
        allow(Sandbox).to receive(:with_preserved_brew_file).and_yield
        allow(sandbox).to receive(:run) do |*args, **options|
          prepared_steps.concat(JSON.parse(File.binread(args.fetch(-2))).fetch("steps"))
          Utils.safe_fork(child_message_handler: options[:child_message_handler]) { exec(*args.map(&:to_s)) }
        end
      end

      test_each([["0755", false], ["755", false], ["0755", true]]) do |mode, native|
        it "prepares mode #{mode} before installing the app (native sandbox: #{native})" do
          if native
            skip "Nested sandboxing is not supported." if Sandbox.nested_sandbox?

            allow(Sandbox).to receive(:new).and_call_original
            allow(Sandbox).to receive(:with_preserved_brew_file).and_call_original
          end
          steps = Homebrew::InstallSteps::DSL.build do
            set_permissions ["Renamed App.app/installer.sh", "Renamed App.app/uninstaller.sh"], mode,
                            base: :appdir, recursive: false
            run "Renamed App.app/installer.sh", args: ["{{version}}"], base: :appdir, sudo: true
          end
          postflight = Cask::Artifact::PostflightSteps.new(cask, steps)
          cask.artifacts.add(postflight)

          install_phase

          expect(%w[installer.sh uninstaller.sh].map { |name| (target_path/name).stat.mode & 0777 })
            .to eq([0755, 0755])
          unless native
            expect(prepared_steps).to eq([{
              "type" => "set_permissions", "permissions" => mode, "non_recursive" => true,
              "paths" => %w[installer.sh uninstaller.sh].map do |name|
                { "base" => "staged_path", "path" => "caffeine_darwin/#{name}" }
              end
            }])
          end

          expect(command).not_to receive(:run!).with("/usr/bin/sandbox-exec", any_args)
          expect(command).to receive(:run)
            .with(target_path/"installer.sh", hash_including(args: ["1.2.3"], sudo: true))
            .and_return(instance_double(SystemCommand::Result, success?: true))
          postflight.install_phase(command:)
        end
      end

      test_each([false, true]) do |reverse_steps|
        it "prepares both apps when permission step order is reversed: #{reverse_steps}" do
          second_app = described_class.new(cask, "second_darwin", target: "Second App.app")
          FileUtils.cp_r(source_path, second_app.source)
          cask.artifacts.add(second_app)
          app_names = ["Renamed App.app", "Second App.app"]
          app_names.reverse! if reverse_steps
          cask.artifacts.add(Cask::Artifact::PostflightSteps.new(cask, Homebrew::InstallSteps::DSL.build do
            app_names.each do |name|
              set_permissions "#{name}/installer.sh", "0755", base: :appdir, recursive: false
            end
          end))

          install_phase
          expect((second_app.source/"installer.sh").stat.mode & 0777).to eq(0644)
          second_app.install_phase(command:)

          expect([target_path, second_app.target].map { |path| (path/"installer.sh").stat.mode & 0777 })
            .to eq([0755, 0755])
        end
      end

      test_each([
        ["group writes", "0770", :appdir, false, "Renamed App.app/installer.sh"],
        ["group writes with world reads", "0775", :appdir, false, "Renamed App.app/installer.sh"],
        ["world writes", "0777", :appdir, false, "Renamed App.app/installer.sh"],
        ["special bits", "4755", :appdir, false, "Renamed App.app/installer.sh"],
        ["symbolic modes", "+x", :appdir, false, "Renamed App.app/installer.sh"],
        ["invalid octal modes", "0755x", :appdir, false, "Renamed App.app/installer.sh"],
        ["recursive changes", "0755", :appdir, true, "Renamed App.app/installer.sh"],
        ["staged paths", "0755", :staged_path, false, "caffeine_darwin/installer.sh"],
        ["an undeclared app", "0755", :appdir, false, "Other.app/installer.sh"],
        ["globs", "0755", :appdir, false, "Renamed App.app/*.sh"],
        ["traversal", "0755", :appdir, false, "Renamed App.app/../Renamed App.app/installer.sh"],
        ["absolute paths", "0755", :appdir, false, "/Applications/Renamed App.app/installer.sh"],
        ["app roots", "0755", :appdir, false, "Renamed App.app"],
        ["mixed paths", "0755", :appdir, false, ["Renamed App.app/installer.sh", "Other.app/script"]],
      ]) do |description, mode, base, recursive, paths|
        it "does not prepare #{description}" do
          cask.artifacts.add(Cask::Artifact::PostflightSteps.new(cask, Homebrew::InstallSteps::DSL.build do
            set_permissions(paths, mode, base:, recursive:)
            set_permissions "Renamed App.app/installer.sh", "0755", base: :appdir, recursive: false
          end))

          install_phase

          expect((target_path/"installer.sh").stat.mode & 0777).to eq(0644)
        end
      end

      test_each(%w[guarded preceding_command unavailable_sandbox adopt]) do |condition|
        it "does not prepare permissions with #{condition}" do
          allow(Sandbox).to receive(:available?).and_return(false) if condition == "unavailable_sandbox"
          cask.artifacts.add(Cask::Artifact::PostflightSteps.new(cask, Homebrew::InstallSteps::DSL.build do
            run "/usr/bin/true" if condition == "preceding_command"
            if condition == "guarded"
              if_path_exists "Renamed App.app/installer.sh", base: :appdir do
                set_permissions "Renamed App.app/installer.sh", "0755", base: :appdir, recursive: false
              end
            else
              set_permissions "Renamed App.app/installer.sh", "0755", base: :appdir, recursive: false
            end
          end))

          app.install_phase(command:, adopt: condition == "adopt")

          expect((target_path/"installer.sh").stat.mode & 0777).to eq(0644)
        end
      end

      test_each([:symlink, :hardlink, :directory_symlink]) do |link_type|
        it "does not prepare a #{link_type} to a file outside the app" do
          outside = cask.staged_path/"outside/installer.sh"
          outside.dirname.mkpath
          outside.write "#!/bin/sh\n"
          outside.chmod 0644
          (source_path/"installer.sh").unlink
          relative_path = (link_type == :directory_symlink) ? "linked/installer.sh" : "installer.sh"
          case link_type
          when :directory_symlink
            File.symlink(outside.dirname, source_path/"linked")
          when :symlink
            File.symlink(outside, source_path/"installer.sh")
          else
            File.link(outside, source_path/"installer.sh")
          end
          cask.artifacts.add(Cask::Artifact::PostflightSteps.new(cask, Homebrew::InstallSteps::DSL.build do
            set_permissions "Renamed App.app/#{relative_path}", "0755", base: :appdir, recursive: false
          end))

          install_phase

          expect(outside.stat.mode & 0777).to eq(0644)
        end
      end
    end

    it "installs the given app using the proper target directory" do
      expect(Sandbox).not_to receive(:use_for?)
      install_phase

      expect(target_path).to be_a_directory
      expect(source_path).to be_a_symlink
    end

    it "removes group and other write permissions from apps" do
      modes = {
        "."                       => 0777,
        "Contents"                => 0770,
        "Contents/MacOS/Caffeine" => 0777,
        "Contents/Info.plist"     => 0666,
        "Contents/PkgInfo"        => 0440,
      }
      modes.each { |path, mode| (source_path/path).chmod(mode) }

      install_phase

      expect(modes.keys.map { |path| (target_path/path).stat.mode & 0777 }).to eq([0755, 0755, 0755, 0644, 0444])
    end

    test_each(%w[admin root]) do |group|
      it "changes the group recursively to the platform default of #{group}" do
        allow(Cask::Caskroom).to receive(:expected_caskroom_group).and_return(group)

        expect(command).to receive(:run)
          .with("chgrp", args: ["-hR", group, target_path],
                         sudo: nil, must_succeed: true, print_stderr: true)

        install_phase
      end
    end

    it "tries changing the app group in the home directory without sudo" do
      allow(Cask::Caskroom).to receive(:expected_caskroom_group).and_return("admin")
      allow(Dir).to receive(:home).and_return(target_path.parent.to_s)
      expect(command).to receive(:run)
        .with("chgrp", args: ["-hR", "admin", target_path],
                       sudo: false, must_succeed: false, print_stderr: false)

      install_phase
    end

    test_each_hash({
      "/Applications/Caffeine.app"            => [0755, 0644],
      "/Applications/Tools/Caffeine.app"      => [0755, 0644],
      "/Caffeine.app"                         => [0755, 0644],
      "/custom-apps/Caffeine.app"             => [0700, 0600],
      "#{Dir.home}/Applications/Caffeine.app" => [0700, 0600],
    }) do |path, modes|
      it "sets permissions for #{path}" do
        allow(app.target).to receive_messages(ascend: Pathname(path).ascend, parent: Pathname(path).parent)
        source_path.chmod(0722)
        (source_path/"Contents/Info.plist").chmod(0622)

        install_phase

        expect([target_path, target_path/"Contents/Info.plist"].map { it.stat.mode & 0777 }).to eq(modes)
      end
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

      expect(Pathname(cask.config.appdir).join("Caffeine Deluxe.app")).not_to exist
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

    context "when source doesn't exist" do
      let(:setup_cask) { cask.staged_path.mkpath }

      it "gives a warning if the source doesn't exist" do
        message = "It seems the App source '#{source_path}' is not there."

        expect { install_phase }.to raise_error(Cask::CaskError, message)
      end
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

    it "uses clonefile copy arguments on supported macOS versions", :needs_macos do
      install_phase

      allow(MacOS).to receive(:version).and_return(MacOSVersion.from_symbol(:sonoma))

      expect(app.backup_copy_args(target_path, source_path)).to eq(["-c", "-pR", target_path, source_path])
    end

    it "uses portable copy arguments on older macOS versions", :needs_macos do
      install_phase

      allow(MacOS).to receive(:version).and_return(MacOSVersion.from_symbol(:ventura))

      expect(app.backup_copy_args(target_path, source_path)).to eq(["-pR", target_path, source_path])
    end

    it "uses portable copy arguments across filesystems", :needs_macos do
      install_phase

      source_dir = source_path.dirname
      allow(MacOS).to receive(:version).and_return(MacOSVersion.from_symbol(:sonoma))
      allow(target_path).to receive(:stat).and_return(instance_double(File::Stat, dev: 1))
      allow(source_path).to receive(:dirname).and_return(source_dir)
      allow(source_dir).to receive(:stat).and_return(instance_double(File::Stat, dev: 2))

      expect(app.backup_copy_args(target_path, source_path)).to eq(["-pR", target_path, source_path])
    end
  end

  describe "summary" do
    let(:description) { app.class.english_description }
    let(:contents) { app.summarize_installed }

    context "without installation" do
      let(:setup_cask) { nil }

      it "returns the correct english_description" do
        expect(description).to eq("Apps")
      end

      describe "app is missing" do
        it "returns a warning and the supposed path to the app" do
          expect(contents).to match(/.*Missing App.*: #{target_path}/)
        end
      end
    end

    describe "app is correctly installed" do
      it "returns the path to the app" do
        install_phase

        expect(contents).to eq("#{target_path} (#{target_path.abv})")
      end
    end
  end

  describe "upgrade" do
    before do
      install_phase
    end

    it "upgrades apps in the home directory without sudo" do
      allow(Dir).to receive(:home).and_return(target_path.parent.to_s)
      allow(command).to receive(:run).with("chgrp", hash_including(sudo: false))
                                     .and_return(instance_double(SystemCommand::Result, success?: false))
      expect(command).not_to receive(:run).with(anything, hash_including(sudo: true))

      app.uninstall_phase(command:, successor: cask)
      app.install_phase(command:, predecessor: cask)
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

    describe "when quarantine support is unavailable" do
      it "reinstalls into the reused directory without copying xattrs" do
        allow(Cask::Quarantine).to receive(:available?).and_return(false)
        expect(MacOS::FFI).not_to receive(:copy_xattrs)

        app.uninstall_phase(command:, force:, successor: cask)
        app.install_phase(command:, adopt:, force:, predecessor: cask)

        expect(target_path.join("Contents/Info.plist")).to exist
      end
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
                           sudo: nil)
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
                           sudo:         nil)
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
