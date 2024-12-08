# frozen_string_literal: true

require "cask/upgrade"

RSpec.describe Cask::Upgrade, :cask do
  let(:version_latest_paths) do
    [
      version_latest.config.appdir.join("Caffeine Mini.app"),
      version_latest.config.appdir.join("Caffeine Pro.app"),
    ]
  end
  let(:version_latest) { Cask::CaskLoader.load("version-latest") }
  let(:auto_updates_path) { auto_updates.config.appdir.join("MyFancyApp.app") }
  let(:auto_updates) { Cask::CaskLoader.load("auto-updates") }
  let(:local_transmission_path) { local_transmission.config.appdir.join("Transmission.app") }
  let(:local_transmission) { Cask::CaskLoader.load("local-transmission") }
  let(:local_caffeine_path) { local_caffeine.config.appdir.join("Caffeine.app") }
  let(:local_caffeine) { Cask::CaskLoader.load("local-caffeine") }
  let(:renamed_app) { Cask::CaskLoader.load("renamed-app") }
  let(:renamed_app_old_path) { renamed_app.config.appdir.join("OldApp.app") }
  let(:renamed_app_new_path) { renamed_app.config.appdir.join("NewApp.app") }
  let(:args) do
    parser = Homebrew::CLI::Parser.new(Homebrew::Cmd::Brew)
    parser.cask_options
    parser.args
  end

  before do
    installed.each do |cask|
      Cask::Installer.new(Cask::CaskLoader.load(cask_path(cask))).install
    end
  end

  context "when the upgrade is a dry run" do
    let(:installed) do
      [
        "outdated/local-caffeine",
        "outdated/local-transmission",
        "outdated/auto-updates",
        "outdated/version-latest",
        "outdated/renamed-app",
      ]
    end

    describe 'without --greedy it ignores the Casks with "version latest" or "auto_updates true"' do
      it "would update all the installed Casks when no token is provided" do
        expect(described_class).not_to receive(:upgrade_cask)

        expect(local_caffeine).to be_installed
        expect(local_caffeine_path).to be_a_directory
        expect(local_caffeine.installed_version).to eq "1.2.2"

        expect(local_transmission).to be_installed
        expect(local_transmission_path).to be_a_directory
        expect(local_transmission.installed_version).to eq "2.60"

        expect(renamed_app).to be_installed
        expect(renamed_app_old_path).to be_a_directory
        expect(renamed_app_new_path).not_to be_a_directory
        expect(renamed_app.installed_version).to eq "1.0.0"

        described_class.upgrade_casks(dry_run: true, args:)

        expect(local_caffeine).to be_installed
        expect(local_caffeine_path).to be_a_directory
        expect(local_caffeine.installed_version).to eq "1.2.2"

        expect(local_transmission).to be_installed
        expect(local_transmission_path).to be_a_directory
        expect(local_transmission.installed_version).to eq "2.60"

        expect(renamed_app).to be_installed
        expect(renamed_app_old_path).to be_a_directory
        expect(renamed_app_new_path).not_to be_a_directory
        expect(renamed_app.installed_version).to eq "1.0.0"
      end

      it "would update only the Casks specified in the command line" do
        expect(described_class).not_to receive(:upgrade_cask)

        expect(local_caffeine).to be_installed
        expect(local_caffeine_path).to be_a_directory
        expect(local_caffeine.installed_version).to eq "1.2.2"

        expect(local_transmission).to be_installed
        expect(local_transmission_path).to be_a_directory
        expect(local_transmission.installed_version).to eq "2.60"

        described_class.upgrade_casks(local_caffeine, dry_run: true, args:)

        expect(local_caffeine).to be_installed
        expect(local_caffeine_path).to be_a_directory
        expect(local_caffeine.installed_version).to eq "1.2.2"

        expect(local_transmission).to be_installed
        expect(local_transmission_path).to be_a_directory
        expect(local_transmission.installed_version).to eq "2.60"
      end

      it 'would update "auto_updates" and "latest" Casks when their tokens are provided in the command line' do
        expect(described_class).not_to receive(:upgrade_cask)

        expect(local_caffeine).to be_installed
        expect(local_caffeine_path).to be_a_directory
        expect(local_caffeine.installed_version).to eq "1.2.2"

        expect(auto_updates).to be_installed
        expect(auto_updates_path).to be_a_directory
        expect(auto_updates.installed_version).to eq "2.57"

        expect(renamed_app).to be_installed
        expect(renamed_app_old_path).to be_a_directory
        expect(renamed_app_new_path).not_to be_a_directory
        expect(renamed_app.installed_version).to eq "1.0.0"

        described_class.upgrade_casks(local_caffeine, auto_updates, dry_run: true, args:)

        expect(local_caffeine).to be_installed
        expect(local_caffeine_path).to be_a_directory
        expect(local_caffeine.installed_version).to eq "1.2.2"

        expect(auto_updates).to be_installed
        expect(auto_updates_path).to be_a_directory
        expect(auto_updates.installed_version).to eq "2.57"

        expect(renamed_app).to be_installed
        expect(renamed_app_old_path).to be_a_directory
        expect(renamed_app_new_path).not_to be_a_directory
        expect(renamed_app.installed_version).to eq "1.0.0"
      end
    end

    describe "with --greedy it checks additional Casks" do
      it 'would include the Casks with "auto_updates true" or "version latest"' do
        expect(described_class).not_to receive(:upgrade_cask)

        expect(local_caffeine).to be_installed
        expect(local_caffeine_path).to be_a_directory
        expect(local_caffeine.installed_version).to eq "1.2.2"

        expect(auto_updates).to be_installed
        expect(auto_updates_path).to be_a_directory
        expect(auto_updates.installed_version).to eq "2.57"

        expect(local_transmission).to be_installed
        expect(local_transmission_path).to be_a_directory
        expect(local_transmission.installed_version).to eq "2.60"

        expect(renamed_app).to be_installed
        expect(renamed_app_old_path).to be_a_directory
        expect(renamed_app_new_path).not_to be_a_directory
        expect(renamed_app.installed_version).to eq "1.0.0"

        expect(version_latest).to be_installed
        # Change download sha so that :latest cask decides to update itself
        version_latest.download_sha_path.write("fake download sha")
        expect(version_latest.outdated_download_sha?).to be(true)

        described_class.upgrade_casks(greedy: true, dry_run: true, args:)

        expect(local_caffeine).to be_installed
        expect(local_caffeine_path).to be_a_directory
        expect(local_caffeine.installed_version).to eq "1.2.2"

        expect(auto_updates).to be_installed
        expect(auto_updates_path).to be_a_directory
        expect(auto_updates.installed_version).to eq "2.57"

        expect(local_transmission).to be_installed
        expect(local_transmission_path).to be_a_directory
        expect(local_transmission.installed_version).to eq "2.60"

        expect(renamed_app).to be_installed
        expect(renamed_app_old_path).to be_a_directory
        expect(renamed_app_new_path).not_to be_a_directory
        expect(renamed_app.installed_version).to eq "1.0.0"

        expect(version_latest).to be_installed
        expect(version_latest.outdated_download_sha?).to be(true)
      end

      it 'would update outdated Casks with "auto_updates true"' do
        expect(described_class).not_to receive(:upgrade_cask)

        expect(auto_updates).to be_installed
        expect(auto_updates_path).to be_a_directory
        expect(auto_updates.installed_version).to eq "2.57"

        described_class.upgrade_casks(auto_updates, dry_run: true, greedy: true, args:)

        expect(auto_updates).to be_installed
        expect(auto_updates_path).to be_a_directory
        expect(auto_updates.installed_version).to eq "2.57"
      end

      it 'would update outdated Casks with "version latest"' do
        expect(described_class).not_to receive(:upgrade_cask)

        expect(version_latest).to be_installed
        expect(version_latest_paths).to all be_a_directory
        expect(version_latest.installed_version).to eq "latest"
        # Change download sha so that :latest cask decides to update itself
        version_latest.download_sha_path.write("fake download sha")
        expect(version_latest.outdated_download_sha?).to be(true)

        described_class.upgrade_casks(version_latest, dry_run: true, greedy: true, args:)

        expect(version_latest).to be_installed
        expect(version_latest_paths).to all be_a_directory
        expect(version_latest.installed_version).to eq "latest"
        expect(version_latest.outdated_download_sha?).to be(true)
      end
    end
  end

  context "when an upgrade failed" do
    let(:installed) do
      [
        "outdated/bad-checksum",
        "outdated/will-fail-if-upgraded",
      ]
    end

    output_reverted = Regexp.new <<~EOS
      Warning: Reverting upgrade for Cask .*
    EOS

    it "restores the old Cask if the upgrade failed" do
      will_fail_if_upgraded = Cask::CaskLoader.load("will-fail-if-upgraded")
      will_fail_if_upgraded_path = will_fail_if_upgraded.config.appdir.join("container")

      expect(will_fail_if_upgraded).to be_installed
      expect(will_fail_if_upgraded_path).to be_a_file
      expect(will_fail_if_upgraded.installed_version).to eq "1.2.2"

      expect do
        described_class.upgrade_casks(will_fail_if_upgraded, args:)
      end.to raise_error(Cask::CaskError).and output(output_reverted).to_stderr

      expect(will_fail_if_upgraded).to be_installed
      expect(will_fail_if_upgraded_path).to be_a_file
      expect(will_fail_if_upgraded.installed_version).to eq "1.2.2"
      expect(will_fail_if_upgraded.staged_path).not_to exist
    end

    it "does not restore the old Cask if the upgrade failed pre-install" do
      bad_checksum = Cask::CaskLoader.load("bad-checksum")
      bad_checksum_path = bad_checksum.config.appdir.join("Caffeine.app")

      expect(bad_checksum).to be_installed
      expect(bad_checksum_path).to be_a_directory
      expect(bad_checksum.installed_version).to eq "1.2.2"

      expect do
        described_class.upgrade_casks(bad_checksum, args:)
      end.to raise_error(ChecksumMismatchError).and(not_to_output(output_reverted).to_stderr)

      expect(bad_checksum).to be_installed
      expect(bad_checksum_path).to be_a_directory
      expect(bad_checksum.installed_version).to eq "1.2.2"
      expect(bad_checksum.staged_path).not_to exist
    end
  end

  context "when there were multiple failures" do
    let(:installed) do
      [
        "outdated/bad-checksum",
        "outdated/local-transmission",
        "outdated/bad-checksum2",
      ]
    end

    it "does not end the upgrade process" do
      bad_checksum = Cask::CaskLoader.load("bad-checksum")
      bad_checksum_path = bad_checksum.config.appdir.join("Caffeine.app")

      bad_checksum_2 = Cask::CaskLoader.load("bad-checksum2")
      bad_checksum_2_path = bad_checksum_2.config.appdir.join("container")

      expect(bad_checksum).to be_installed
      expect(bad_checksum_path).to be_a_directory
      expect(bad_checksum.installed_version).to eq "1.2.2"

      expect(local_transmission).to be_installed
      expect(local_transmission_path).to be_a_directory
      expect(local_transmission.installed_version).to eq "2.60"

      expect(bad_checksum_2).to be_installed
      expect(bad_checksum_2_path).to be_a_file
      expect(bad_checksum_2.installed_version).to eq "1.2.2"

      expect do
        described_class.upgrade_casks(args:)
      end.to raise_error(Cask::MultipleCaskErrors)

      expect(bad_checksum).to be_installed
      expect(bad_checksum_path).to be_a_directory
      expect(bad_checksum.installed_version).to eq "1.2.2"
      expect(bad_checksum.staged_path).not_to exist

      expect(local_transmission).to be_installed
      expect(local_transmission_path).to be_a_directory
      expect(local_transmission.installed_version).to eq "2.61"

      expect(bad_checksum_2).to be_installed
      expect(bad_checksum_2_path).to be_a_file
      expect(bad_checksum_2.installed_version).to eq "1.2.2"
      expect(bad_checksum_2.staged_path).not_to exist
    end
  end
end
