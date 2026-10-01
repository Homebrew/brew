# typed: true
# frozen_string_literal: true

require_relative "shared_examples/uninstall_zap"

RSpec.describe Cask::Artifact::Uninstall, :cask do
  before { allow(Cask::Artifact::AbstractUninstall).to receive(:ancestor_bundle_ids).and_return([]) }

  describe "#uninstall_phase" do
    let(:fake_system_command) { NeverSudoSystemCommand }

    include_examples "#uninstall_phase or #zap_phase"

    context "when sudo is disabled" do
      let(:cask) { Cask::CaskLoader.load(cask_path("with-uninstall-launchctl")) }

      it "removes user services without probing system services" do
        ENV["HOMEBREW_NO_SUDO"] = "1"
        allow(Homebrew::Services::System).to receive(:launchctl_find_service)
          .with("my.fancy.package.service", sudo: false)
          .and_return(["", true, :launchctl_print])
        allow(fake_system_command).to receive(:run)
          .with("/bin/launchctl", args: ["remove", "my.fancy.package.service"],
                must_succeed: false, sudo: false, sudo_as_root: false)
          .and_return(instance_double(SystemCommand::Result, success?: true))
        allow(artifact).to receive(:sleep)

        expect { artifact.uninstall_phase(command: fake_system_command) }.not_to raise_error
      end
    end

    it "does not query sudo for unmatched service wildcards" do
      artifact = described_class.new(Cask::CaskLoader.load(cask_path("with-uninstall-launchctl")),
                                     launchctl: "unmatched.*")
      allow(artifact).to receive(:find_launchctl_with_wildcard).and_return([])

      expect(SystemCommand).not_to receive(:sudo_available?)

      artifact.uninstall_phase(command: fake_system_command)
    end

    describe "upgrade/reinstall uninstall directives" do
      context "with-uninstall-quit" do
        let(:cask) { Cask::CaskLoader.load(cask_path("with-uninstall-quit")) }
        let(:artifact) { cask.artifacts.find { |a| a.is_a?(described_class) } }

        it "invokes :quit during upgrade" do
          called_directives = T.let([], T::Array[Symbol])
          allow(artifact).to receive(:dispatch_uninstall_directive) do |directive, **options|
            called_directives << directive if options[:command] == fake_system_command
          end

          artifact.uninstall_phase(upgrade: true, command: fake_system_command)

          expect(called_directives).to include(:quit)
        end

        it "skips :quit during upgrade when quit is false" do
          called_directives = T.let([], T::Array[Symbol])
          allow(artifact).to receive(:dispatch_uninstall_directive) do |directive, **options|
            called_directives << directive if options[:command] == fake_system_command
          end

          artifact.uninstall_phase(upgrade: true, quit: false, command: fake_system_command)

          expect(called_directives).not_to include(:quit)
        end

        it "invokes :quit during reinstall" do
          called_directives = T.let([], T::Array[Symbol])
          allow(artifact).to receive(:dispatch_uninstall_directive) do |directive, **options|
            called_directives << directive if options[:command] == fake_system_command
          end

          artifact.uninstall_phase(reinstall: true, command: fake_system_command)

          expect(called_directives).to include(:quit)
        end
      end

      context "with-uninstall-signal" do
        let(:cask) { Cask::CaskLoader.load(cask_path("with-uninstall-signal")) }
        let(:artifact) { cask.artifacts.find { |a| a.is_a?(described_class) } }

        it "skips :signal by default during upgrade" do
          called_directives = T.let([], T::Array[Symbol])
          allow(artifact).to receive(:dispatch_uninstall_directive) do |directive, **options|
            called_directives << directive if options[:command] == fake_system_command
          end

          artifact.uninstall_phase(upgrade: true, command: fake_system_command)

          expect(called_directives).not_to include(:signal)
        end

        it "skips :signal by default during reinstall" do
          called_directives = T.let([], T::Array[Symbol])
          allow(artifact).to receive(:dispatch_uninstall_directive) do |directive, **options|
            called_directives << directive if options[:command] == fake_system_command
          end

          artifact.uninstall_phase(reinstall: true, command: fake_system_command)

          expect(called_directives).not_to include(:signal)
        end
      end

      context "with-uninstall-signal-on-upgrade" do
        let(:cask) { Cask::CaskLoader.load(cask_path("with-uninstall-signal-on-upgrade")) }
        let(:artifact) { cask.artifacts.find { |a| a.is_a?(described_class) } }

        it "invokes :signal during upgrade" do
          called_directives = T.let([], T::Array[Symbol])
          allow(artifact).to receive(:dispatch_uninstall_directive) do |directive, **options|
            called_directives << directive if options[:command] == fake_system_command
          end

          artifact.uninstall_phase(upgrade: true, command: fake_system_command)

          expect(called_directives).to include(:signal)
        end

        it "invokes :signal during reinstall" do
          called_directives = T.let([], T::Array[Symbol])
          allow(artifact).to receive(:dispatch_uninstall_directive) do |directive, **options|
            called_directives << directive if options[:command] == fake_system_command
          end

          artifact.uninstall_phase(reinstall: true, command: fake_system_command)

          expect(called_directives).to include(:signal)
        end
      end
    end

    context "with-uninstall-both-on-upgrade" do
      let(:cask) { Cask::CaskLoader.load(cask_path("with-uninstall-both-on-upgrade")) }
      let(:artifact) { cask.artifacts.find { |a| a.is_a?(described_class) } }

      it "invokes both quit and signal during upgrade when on_upgrade: :signal" do
        called_directives = T.let([], T::Array[Symbol])
        allow(artifact).to receive(:dispatch_uninstall_directive) do |directive, **options|
          called_directives << directive if options[:command] == fake_system_command
        end

        artifact.uninstall_phase(upgrade: true, command: fake_system_command)
        expect(called_directives).to include(:quit, :signal)
      end
    end

    context "with-uninstall-quit-only-on-upgrade" do
      let(:cask) { Cask::CaskLoader.load(cask_path("with-uninstall-quit-only-on-upgrade")) }
      let(:artifact) { cask.artifacts.find { |a| a.is_a?(described_class) } }

      it "invokes quit but not signal during upgrade without on_upgrade: :signal" do
        called_directives = T.let([], T::Array[Symbol])
        allow(artifact).to receive(:dispatch_uninstall_directive) do |directive, **options|
          called_directives << directive if options[:command] == fake_system_command
        end

        artifact.uninstall_phase(upgrade: true, command: fake_system_command)
        expect(called_directives).to include(:quit)
        expect(called_directives).not_to include(:signal)
      end
    end
  end

  describe "#uninstall_quit" do
    let(:cask) { Cask::CaskLoader.load(cask_path("with-uninstall-quit")) }
    let(:artifact) { cask.artifacts.find { |a| a.is_a?(described_class) } }

    let(:fake_system_command) { NeverSudoSystemCommand }

    before do
      allow(User.current).to receive(:gui?).and_return true
      allow(artifact).to receive(:quit).and_return(instance_double(SystemCommand::Result, success?: true))
    end

    it "does not quit the application hosting the `brew` process" do
      allow(artifact).to receive(:running?).with("com.example.app").and_return(true)
      allow(Cask::Artifact::AbstractUninstall).to receive(:ancestor_bundle_ids).and_return(["com.Example.App"])

      expect(artifact).not_to receive(:quit)
      expect do
        artifact.uninstall_quit("com.example.app", upgrade: true, command: fake_system_command)
      end.to output(/Skipping quitting application 'com.example.app'/).to_stderr

      expect(artifact.bundle_ids_to_reopen).to be_empty
    end

    it "quits every running application matching a wildcard" do
      allow(artifact).to receive(:running_bundle_ids)
        .and_return(["com.example.app", "com.example.app.helper", "com.other.app"])
      allow(artifact).to receive(:running?).with("com.example.app").and_return(true, false)
      allow(artifact).to receive(:running?).with("com.example.app.helper").and_return(true, false)

      artifact.uninstall_quit("com.example.app*", upgrade: true, command: fake_system_command)

      expect(artifact.bundle_ids_to_reopen).to eq ["com.example.app", "com.example.app.helper"]
    end

    it "matches a wildcard without regard to case" do
      allow(artifact).to receive(:running_bundle_ids).and_return(["com.example.app"])
      allow(artifact).to receive(:running?).with("com.example.app").and_return(true, false)

      artifact.uninstall_quit("com.Example.App*", upgrade: true, command: fake_system_command)

      expect(artifact.bundle_ids_to_reopen).to eq ["com.example.app"]
    end

    it "anchors a wildcard to the whole bundle ID" do
      allow(artifact).to receive(:running_bundle_ids).and_return(["org.other.com.example.app"])

      expect(artifact).not_to receive(:running?)

      artifact.uninstall_quit("com.example*", upgrade: true, command: fake_system_command)
    end

    it "does not list running applications without a GUI" do
      allow(User.current).to receive(:gui?).and_return(false)

      expect(artifact).not_to receive(:running_bundle_ids)

      expect { artifact.uninstall_quit("com.example.app*", upgrade: true, command: fake_system_command) }
        .to output(/Not logged into a GUI/).to_stderr
    end

    it "does not list running applications without a wildcard" do
      allow(artifact).to receive(:running?).and_return(false)

      expect(artifact).not_to receive(:running_bundle_ids)

      artifact.uninstall_quit("com.example.app", upgrade: true, command: fake_system_command)
    end
  end

  describe "#uninstall_signal" do
    subject(:artifact) { cask.artifacts.find { |a| a.is_a?(described_class) } }

    let(:fake_system_command) { NeverSudoSystemCommand }
    let(:cask) { Cask::CaskLoader.load(cask_path("with-uninstall-signal-wildcard")) }

    before do
      allow(User.current).to receive(:gui?).and_return(true)
      allow(artifact).to receive(:sleep).with(3)
      allow(Cask::Artifact::AbstractUninstall).to receive(:owner_uid).and_return(Process.uid)
    end

    it "does not signal processes owned by other users" do
      allow(artifact).to receive(:running_bundle_ids).and_return(["my.fancy.package"])
      allow(artifact).to receive(:running_processes).with("my.fancy.package")
                                                    .and_return([[123, 0, "my.fancy.package"],
                                                                 [456, 0, "my.fancy.package"]])
      allow(Cask::Artifact::AbstractUninstall).to receive(:owner_uid).with(123).and_return(Process.uid + 1)

      expect(Process).to receive(:kill).with("TERM", 456)

      artifact.uninstall_phase(command: fake_system_command)
    end

    it "does not signal processes whose owner cannot be determined" do
      allow(artifact).to receive(:running_bundle_ids).and_return(["my.fancy.package"])
      allow(artifact).to receive(:running_processes).with("my.fancy.package")
                                                    .and_return([[123, 0, "my.fancy.package"]])
      allow(Cask::Artifact::AbstractUninstall).to receive(:owner_uid).with(123).and_return(nil)

      expect(Process).not_to receive(:kill)

      artifact.uninstall_phase(command: fake_system_command)
    end

    it "does not signal the application hosting the `brew` process" do
      allow(artifact).to receive(:running_processes).with("my.fancy.package")
                                                    .and_return([[123, 0, "my.fancy.package"]])
      allow(artifact).to receive(:running_bundle_ids).and_return(["my.fancy.package"])
      allow(Cask::Artifact::AbstractUninstall).to receive(:ancestor_bundle_ids).and_return(["my.fancy.package"])

      expect(Process).not_to receive(:kill)

      expect { artifact.uninstall_phase(command: fake_system_command) }
        .to output(/Skipping signalling application 'my.fancy.package'/).to_stderr
    end

    it "signals the running processes of every application matching a wildcard" do
      allow(artifact).to receive(:running_bundle_ids)
        .and_return(["my.fancy.package", "my.fancy.package.helper", "my.other.package"])
      allow(artifact).to receive(:running_processes).with("my.fancy.package")
                                                    .and_return([[123, 0, "my.fancy.package"]])
      allow(artifact).to receive(:running_processes).with("my.fancy.package.helper")
                                                    .and_return([[456, 0, "my.fancy.package.helper"]])

      expect(Process).to receive(:kill).with("TERM", 123)
      expect(Process).to receive(:kill).with("TERM", 456)

      artifact.uninstall_phase(command: fake_system_command)
    end

    it "looks for no processes when a wildcard matches no running application" do
      allow(artifact).to receive(:running_bundle_ids).and_return(["my.other.package"])

      expect(artifact).not_to receive(:running_processes)

      artifact.uninstall_phase(command: fake_system_command)
    end
  end

  describe ".ancestor_bundle_ids" do
    let(:klass) { Cask::Artifact::AbstractUninstall }
    let(:pid) { Process.pid }

    before do
      allow(klass).to receive(:ancestor_bundle_ids).and_call_original
      klass.ancestor_bundle_ids = nil
    end

    after { klass.ancestor_bundle_ids = nil }

    def stub_process_tree(tree)
      allow(klass).to receive(:parent_pid) { |child| tree[child] }
    end

    it "resolves the bundle IDs of the processes between brew and launchd" do
      stub_process_tree({ pid => 300, 300 => 200, 200 => 1 })
      expect(klass).to receive(:bundle_identifier_for_pid).with(pid).ordered.and_return(nil)
      expect(klass).to receive(:bundle_identifier_for_pid).with(300).ordered.and_return(nil)
      expect(klass).to receive(:bundle_identifier_for_pid).with(200).ordered.and_return("com.example.terminal")

      expect(klass.ancestor_bundle_ids).to eq ["com.example.terminal"]
    end

    it "stops walking when a parent cannot be resolved" do
      stub_process_tree({ pid => 300 })
      expect(klass).to receive(:bundle_identifier_for_pid).with(pid).ordered.and_return(nil)
      expect(klass).to receive(:bundle_identifier_for_pid).with(300).ordered.and_return("com.example.terminal")

      expect(klass.ancestor_bundle_ids).to eq ["com.example.terminal"]
    end

    it "stops walking when the process tree loops back on itself" do
      stub_process_tree({ pid => 300, 300 => 200, 200 => 300 })
      expect(klass).to receive(:bundle_identifier_for_pid).exactly(3).times.and_return(nil)

      expect(klass.ancestor_bundle_ids).to be_empty
    end

    it "looks up the ancestry once for each brew invocation" do
      stub_process_tree({ pid => 300, 300 => 1 })
      allow(klass).to receive(:bundle_identifier_for_pid).and_return("com.example.terminal")

      klass.ancestor_bundle_ids
      expect(klass).not_to receive(:parent_pid)
      expect(klass).not_to receive(:bundle_identifier_for_pid)

      expect(klass.ancestor_bundle_ids).to eq %w[com.example.terminal com.example.terminal]
    end
  end

  describe "#bundle_ids_to_reopen" do
    subject(:artifact) { cask.artifacts.find { |a| a.is_a?(described_class) } }

    let(:fake_system_command) { NeverSudoSystemCommand }
    let(:cask) { Cask::CaskLoader.load(cask_path("with-uninstall-quit")) }
    let(:bundle_id) { "my.fancy.package.app" }

    before { allow(User.current).to receive(:gui?).and_return true }

    it "tracks a successfully quit app during upgrade" do
      allow(artifact).to receive(:running?).with(bundle_id).and_return(true, false)
      allow(artifact).to receive(:quit).with(bundle_id)
                                       .and_return(instance_double(SystemCommand::Result, success?: true))

      artifact.uninstall_quit(bundle_id, upgrade: true, command: fake_system_command)

      expect(artifact.bundle_ids_to_reopen).to eq [bundle_id]
    end

    it "does not track during regular uninstall" do
      allow(artifact).to receive(:running?).with(bundle_id).and_return(true, false)
      allow(artifact).to receive(:quit).with(bundle_id)
                                       .and_return(instance_double(SystemCommand::Result, success?: true))

      artifact.uninstall_quit(bundle_id, upgrade: false, command: fake_system_command)

      expect(artifact.bundle_ids_to_reopen).to be_empty
    end

    it "does not track when quit times out" do
      allow(artifact).to receive(:running?).with(bundle_id).and_return(true)
      allow(artifact).to receive(:quit).with(bundle_id)
                                       .and_return(instance_double(SystemCommand::Result, success?: false))
      allow(Timeout).to receive(:timeout).and_raise(Timeout::Error)

      expect do
        artifact.uninstall_quit(bundle_id, upgrade: true, command: fake_system_command)
      end.to output(/did not quit/).to_stderr

      expect(artifact.bundle_ids_to_reopen).to be_empty
    end
  end

  describe "#post_uninstall_phase" do
    context "when using :rmdir" do
      let(:fake_system_command) { NeverSudoSystemCommand }
      let(:artifact) { cask.artifacts.find { |a| a.is_a?(described_class) } }
      let(:cask) { Cask::CaskLoader.load(cask_path("with-uninstall-rmdir")) }
      let(:empty_directory) { Pathname.new("#{TEST_TMPDIR}/empty_directory_path") }
      let(:empty_directory_tree) { empty_directory.join("nested", "empty_directory_path") }
      let(:ds_store) { empty_directory.join(".DS_Store") }

      before do
        empty_directory_tree.mkpath
        FileUtils.touch ds_store
      end

      after do
        FileUtils.rm_rf empty_directory
      end

      it "is supported" do
        expect(empty_directory_tree).to exist
        expect(ds_store).to exist

        artifact.post_uninstall_phase(command: fake_system_command)

        expect(ds_store).not_to exist
        expect(empty_directory).not_to exist
      end
    end
  end
end
