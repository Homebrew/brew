# typed: false
# frozen_string_literal: true

require_relative "shared_examples/uninstall_zap"

RSpec.describe Cask::Artifact::Uninstall, :cask do
  describe "#uninstall_phase" do
    let(:fake_system_command) { NeverSudoSystemCommand }

    include_examples "#uninstall_phase or #zap_phase"

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

      artifact.send(:uninstall_quit, bundle_id, upgrade: true, command: fake_system_command)

      expect(artifact.bundle_ids_to_reopen).to eq [bundle_id]
    end

    it "does not track during regular uninstall" do
      allow(artifact).to receive(:running?).with(bundle_id).and_return(true, false)
      allow(artifact).to receive(:quit).with(bundle_id)
                                       .and_return(instance_double(SystemCommand::Result, success?: true))

      artifact.send(:uninstall_quit, bundle_id, upgrade: false, command: fake_system_command)

      expect(artifact.bundle_ids_to_reopen).to be_empty
    end

    it "does not track when quit times out" do
      allow(artifact).to receive(:running?).with(bundle_id).and_return(true)
      allow(artifact).to receive(:quit).with(bundle_id)
                                       .and_return(instance_double(SystemCommand::Result, success?: false))
      allow(Timeout).to receive(:timeout).and_raise(Timeout::Error)

      expect do
        artifact.send(:uninstall_quit, bundle_id, upgrade: true, command: fake_system_command)
      end.to output(/did not quit/).to_stderr

      expect(artifact.bundle_ids_to_reopen).to be_empty
    end
  end

  describe "#post_uninstall_phase" do
    subject(:artifact) { cask.artifacts.find { |a| a.is_a?(described_class) } }

    context "when using :rmdir" do
      let(:fake_system_command) { NeverSudoSystemCommand }
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
