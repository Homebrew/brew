# frozen_string_literal: true

require_relative "shared_examples/uninstall_zap"

RSpec.describe Cask::Artifact::Uninstall, :cask do
  describe "#uninstall_phase" do
    let(:fake_system_command) { NeverSudoSystemCommand }

    include_examples "#uninstall_phase or #zap_phase"

    describe "upgrade/reinstall opt-in uninstall directives" do
      context "with-uninstall-quit" do
        let(:cask) { Cask::CaskLoader.load(cask_path("with-uninstall-quit")) }
        let(:artifact) { cask.artifacts.find { |a| a.is_a?(described_class) } }

        it "skips :quit by default during upgrade" do
          quit_called = false
          allow(artifact).to receive(:dispatch_uninstall_directive) do |directive, **options|
            quit_called ||= directive == :quit && options[:command] == fake_system_command
          end

          artifact.uninstall_phase(upgrade: true, command: fake_system_command)

          expect(quit_called).to be false
        end

        it "skips :quit by default during reinstall" do
          quit_called = false
          allow(artifact).to receive(:dispatch_uninstall_directive) do |directive, **options|
            quit_called ||= directive == :quit && options[:command] == fake_system_command
          end

          artifact.uninstall_phase(reinstall: true, command: fake_system_command)

          expect(quit_called).to be false
        end
      end

      context "with-uninstall-quit-on-upgrade" do
        let(:cask) { Cask::CaskLoader.load(cask_path("with-uninstall-quit-on-upgrade")) }
        let(:artifact) { cask.artifacts.find { |a| a.is_a?(described_class) } }

        it "invokes :quit during upgrade" do
          quit_called = false
          allow(artifact).to receive(:dispatch_uninstall_directive) do |directive, **options|
            quit_called ||= directive == :quit && options[:command] == fake_system_command
          end

          artifact.uninstall_phase(upgrade: true, command: fake_system_command)

          expect(quit_called).to be true
        end

        it "invokes :quit during reinstall" do
          quit_called = false
          allow(artifact).to receive(:dispatch_uninstall_directive) do |directive, **options|
            quit_called ||= directive == :quit && options[:command] == fake_system_command
          end

          artifact.uninstall_phase(reinstall: true, command: fake_system_command)

          expect(quit_called).to be true
        end
      end

      context "with-uninstall-signal" do
        let(:cask) { Cask::CaskLoader.load(cask_path("with-uninstall-signal")) }
        let(:artifact) { cask.artifacts.find { |a| a.is_a?(described_class) } }

        it "skips :signal by default during upgrade" do
          signal_called = false
          allow(artifact).to receive(:dispatch_uninstall_directive) do |directive, **options|
            signal_called ||= directive == :signal && options[:command] == fake_system_command
          end

          artifact.uninstall_phase(upgrade: true, command: fake_system_command)

          expect(signal_called).to be false
        end

        it "skips :signal by default during reinstall" do
          signal_called = false
          allow(artifact).to receive(:dispatch_uninstall_directive) do |directive, **options|
            signal_called ||= directive == :signal && options[:command] == fake_system_command
          end

          artifact.uninstall_phase(reinstall: true, command: fake_system_command)

          expect(signal_called).to be false
        end
      end

      context "with-uninstall-signal-on-upgrade" do
        let(:cask) { Cask::CaskLoader.load(cask_path("with-uninstall-signal-on-upgrade")) }
        let(:artifact) { cask.artifacts.find { |a| a.is_a?(described_class) } }

        it "invokes :signal during upgrade" do
          signal_called = false
          allow(artifact).to receive(:dispatch_uninstall_directive) do |directive, **options|
            signal_called ||= directive == :signal && options[:command] == fake_system_command
          end

          artifact.uninstall_phase(upgrade: true, command: fake_system_command)

          expect(signal_called).to be true
        end

        it "invokes :signal during reinstall" do
          signal_called = false
          allow(artifact).to receive(:dispatch_uninstall_directive) do |directive, **options|
            signal_called ||= directive == :signal && options[:command] == fake_system_command
          end

          artifact.uninstall_phase(reinstall: true, command: fake_system_command)

          expect(signal_called).to be true
        end
      end
    end

    context "with-uninstall-both-on-upgrade" do
      let(:cask) { Cask::CaskLoader.load(cask_path("with-uninstall-both-on-upgrade")) }
      let(:artifact) { cask.artifacts.find { |a| a.is_a?(described_class) } }

      it "invokes both quit and signal during upgrade" do
        quit_called = false
        signal_called = false
        allow(artifact).to receive(:dispatch_uninstall_directive) do |directive, **options|
          quit_called   ||= directive == :quit && options[:command] == fake_system_command
          signal_called ||= directive == :signal && options[:command] == fake_system_command
        end

        artifact.uninstall_phase(upgrade: true, command: fake_system_command)
        expect(quit_called).to be true
        expect(signal_called).to be true
      end
    end

    context "with-uninstall-quit-only-on-upgrade" do
      let(:cask) { Cask::CaskLoader.load(cask_path("with-uninstall-quit-only-on-upgrade")) }
      let(:artifact) { cask.artifacts.find { |a| a.is_a?(described_class) } }

      it "invokes only quit during upgrade when on_upgrade: [:quit]" do
        quit_called = false
        signal_called = false
        allow(artifact).to receive(:dispatch_uninstall_directive) do |directive, **options|
          quit_called   ||= directive == :quit && options[:command] == fake_system_command
          signal_called ||= directive == :signal && options[:command] == fake_system_command
        end

        artifact.uninstall_phase(upgrade: true, command: fake_system_command)
        expect(quit_called).to be true
        expect(signal_called).to be false
      end
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
