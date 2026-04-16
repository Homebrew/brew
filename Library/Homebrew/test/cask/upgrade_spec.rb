# typed: false
# frozen_string_literal: true

require "cask/upgrade"

RSpec.describe Cask::Upgrade, :cask do
  def write_info_plist(path, short_version:, bundle_version:)
    info_plist = path/"Contents/Info.plist"
    info_plist.dirname.mkpath
    info_plist.write <<~PLIST
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <plist version="1.0">
      <dict>
        <key>CFBundleShortVersionString</key>
        <string>#{short_version}</string>
        <key>CFBundleVersion</key>
        <string>#{bundle_version}</string>
      </dict>
      </plist>
    PLIST
  end

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
  let(:local_transmission) { Cask::CaskLoader.load("local-transmission-zip") }
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
    allow(Homebrew::EnvConfig).to receive(:upgrade_auto_updates_casks?).and_return(true)
  end

  context "when the upgrade is a dry run" do
    # Use stub installation for dry-run tests since they mock upgrade_cask
    # and only need to verify installation state, not perform real upgrades.
    # This avoids downloading and extracting archives, significantly speeding up tests.
    before do
      [
        "outdated/local-caffeine",
        "outdated/local-transmission-zip",
        "outdated/auto-updates",
        "outdated/version-latest",
        "outdated/renamed-app",
      ].each do |cask_name|
        InstallHelper.stub_cask_installation(Cask::CaskLoader.load(cask_path(cask_name)))
      end

      write_info_plist(auto_updates_path, short_version: "2.57", bundle_version: "2057")
    end

    describe "without --greedy" do
      it 'includes "auto_updates true" casks when the installed bundle version is older than the tap version' do
        expect(described_class).not_to receive(:upgrade_cask)
        expect(described_class).to receive(:show_upgrade_summary) do |cask_upgrades, dry_run:|
          expect(dry_run).to be(true)
          expect(cask_upgrades).to include(
            "local-caffeine 1.2.2 -> 1.2.3",
            "local-transmission-zip 2.60 -> 2.61",
            "auto-updates 2.57 -> 2.61",
            "renamed-app 1.0.0 -> 2.0.0",
          )
          expect(cask_upgrades.grep(/version-latest/)).to be_empty
        end

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

        described_class.upgrade_casks!(dry_run: true, args:)

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

      it 'excludes "auto_updates true" casks when HOMEBREW_NO_UPGRADE_AUTO_UPDATES_CASKS is set' do
        allow(Homebrew::EnvConfig).to receive(:upgrade_auto_updates_casks?).and_return(false)

        expect(described_class).not_to receive(:upgrade_cask)
        expect(described_class).to receive(:show_upgrade_summary) do |cask_upgrades, dry_run:|
          expect(dry_run).to be(true)
          expect(cask_upgrades).to include(
            "local-caffeine 1.2.2 -> 1.2.3",
            "local-transmission-zip 2.60 -> 2.61",
            "renamed-app 1.0.0 -> 2.0.0",
          )
          expect(cask_upgrades.grep(/auto-updates/)).to be_empty
        end

        described_class.upgrade_casks!(dry_run: true, args:)
      end

      it "raises if HOMEBREW_UPGRADE_AUTO_UPDATES_CASKS and HOMEBREW_NO_UPGRADE_AUTO_UPDATES_CASKS are set" do
        allow(Homebrew::EnvConfig).to receive(:upgrade_auto_updates_casks?).and_call_original

        with_env(
          "HOMEBREW_UPGRADE_AUTO_UPDATES_CASKS"    => "1",
          "HOMEBREW_NO_UPGRADE_AUTO_UPDATES_CASKS" => "1",
        ) do
          expect { described_class.upgrade_casks!(dry_run: true, args:) }
            .to raise_error(UsageError, /cannot both be set/i)
        end
      end

      it 'excludes "auto_updates true" casks when the installed bundle matches the tap version' do
        write_info_plist(auto_updates_path, short_version: "2.61", bundle_version: "2061")

        expect(described_class).not_to receive(:upgrade_cask)
        expect(described_class).to receive(:show_upgrade_summary) do |cask_upgrades, dry_run:|
          expect(dry_run).to be(true)
          expect(cask_upgrades).to include(
            "local-caffeine 1.2.2 -> 1.2.3",
            "local-transmission-zip 2.60 -> 2.61",
            "renamed-app 1.0.0 -> 2.0.0",
          )
          expect(cask_upgrades.grep(/auto-updates/)).to be_empty
        end

        described_class.upgrade_casks!(dry_run: true, args:)
      end

      it "would update only the Casks specified in the command line" do
        expect(described_class).not_to receive(:upgrade_cask)
        expect(described_class).to receive(:show_upgrade_summary)
          .with(["local-caffeine 1.2.2 -> 1.2.3"], dry_run: true)

        expect(local_caffeine).to be_installed
        expect(local_caffeine_path).to be_a_directory
        expect(local_caffeine.installed_version).to eq "1.2.2"

        expect(local_transmission).to be_installed
        expect(local_transmission_path).to be_a_directory
        expect(local_transmission.installed_version).to eq "2.60"

        described_class.upgrade_casks!(local_caffeine, dry_run: true, args:)

        expect(local_caffeine).to be_installed
        expect(local_caffeine_path).to be_a_directory
        expect(local_caffeine.installed_version).to eq "1.2.2"

        expect(local_transmission).to be_installed
        expect(local_transmission_path).to be_a_directory
        expect(local_transmission.installed_version).to eq "2.60"
      end

      it 'would update "auto_updates" and "latest" Casks when their tokens are provided in the command line' do
        expect(described_class).not_to receive(:upgrade_cask)
        expect(described_class).to receive(:show_upgrade_summary)
          .with(["local-caffeine 1.2.2 -> 1.2.3", "auto-updates 2.57 -> 2.61"], dry_run: true)

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

        described_class.upgrade_casks!(local_caffeine, auto_updates, dry_run: true, args:)

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

        described_class.upgrade_casks!(greedy: true, dry_run: true, args:)

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
        expect(described_class).to receive(:show_upgrade_summary)
          .with(["auto-updates 2.57 -> 2.61"], dry_run: true)

        expect(auto_updates).to be_installed
        expect(auto_updates_path).to be_a_directory
        expect(auto_updates.installed_version).to eq "2.57"

        described_class.upgrade_casks!(auto_updates, dry_run: true, greedy: true, args:)

        expect(auto_updates).to be_installed
        expect(auto_updates_path).to be_a_directory
        expect(auto_updates.installed_version).to eq "2.57"
      end

      it 'would update outdated Casks with "version latest"' do
        expect(described_class).not_to receive(:upgrade_cask)
        expect(described_class).to receive(:show_upgrade_summary)
          .with(["version-latest latest -> latest"], dry_run: true)

        expect(version_latest).to be_installed
        expect(version_latest_paths).to all be_a_directory
        expect(version_latest.installed_version).to eq "latest"
        # Change download sha so that :latest cask decides to update itself
        version_latest.download_sha_path.write("fake download sha")
        expect(version_latest.outdated_download_sha?).to be(true)

        described_class.upgrade_casks!(version_latest, dry_run: true, greedy: true, args:)

        expect(version_latest).to be_installed
        expect(version_latest_paths).to all be_a_directory
        expect(version_latest.installed_version).to eq "latest"
        expect(version_latest.outdated_download_sha?).to be(true)
      end
    end
  end

  context "when a cask has broken metadata" do
    before do
      [
        "outdated/local-caffeine",
        "outdated/auto-updates",
      ].each do |cask_name|
        InstallHelper.stub_cask_installation(Cask::CaskLoader.load(cask_path(cask_name)))
      end

      write_info_plist(auto_updates_path, short_version: "2.57", bundle_version: "2057")
    end

    it "warns and skips when the installed caskfile raises CaskInvalidError" do
      allow(Cask::CaskLoader).to receive(:load).and_call_original
      allow(Cask::CaskLoader).to receive(:load).with(auto_updates.installed_caskfile)
                                               .and_raise(Cask::CaskInvalidError.new(auto_updates.token,
                                                                                     "broken DSL"))

      expect do
        described_class.upgrade_casks!(dry_run: true, args:)
      end.to output(/The cask 'auto-updates' cannot be upgraded as-is/).to_stderr
    end

    it "warns and skips when the installed caskfile raises CaskUnreadableError" do
      allow(Cask::CaskLoader).to receive(:load).and_call_original
      allow(Cask::CaskLoader).to receive(:load).with(auto_updates.installed_caskfile)
                                               .and_raise(Cask::CaskUnreadableError.new(auto_updates.token,
                                                                                        "syntax error"))

      expect do
        described_class.upgrade_casks!(dry_run: true, args:)
      end.to output(/The cask 'auto-updates' cannot be upgraded as-is/).to_stderr
    end

    it "warns and skips when the cask is not fully installed" do
      # Stub installed? to return false after outdated detection
      # to simulate a cask with a broken metadata directory
      installed_calls = 0
      allow(auto_updates).to receive(:installed?) do
        installed_calls += 1
        installed_calls <= 1
      end

      expect do
        described_class.upgrade_casks!(auto_updates, dry_run: true, args:)
      end.to output(/The cask 'auto-updates' cannot be upgraded as-is/).to_stderr
    end
  end

  it "warns and skips disabled casks" do
    cask = Cask::CaskLoader.load(cask_path("livecheck/livecheck-disabled"))
    InstallHelper.stub_cask_installation(cask)
    allow(cask).to receive(:outdated?).with(greedy: true).and_return(true)

    expect(described_class).not_to receive(:upgrade_cask)

    expect do
      described_class.upgrade_casks!(cask, dry_run: true, args:)
    end.to output(/Not upgrading livecheck-disabled, it is disabled/).to_stderr
  end

  context "when an upgrade failed" do
    # These tests perform actual upgrades and test rollback behavior,
    # so they need full real installations.
    before do
      [
        "outdated/bad-checksum",
        "outdated/will-fail-if-upgraded",
      ].each do |cask|
        Cask::Installer.new(Cask::CaskLoader.load(cask_path(cask))).install
      end
    end

    let(:output_reverted) do
      Regexp.new <<~EOS
        Warning: Reverting upgrade for Cask .*
      EOS
    end

    it "restores the old Cask if the upgrade failed" do
      will_fail_if_upgraded = Cask::CaskLoader.load("will-fail-if-upgraded")
      will_fail_if_upgraded_path = will_fail_if_upgraded.config.appdir.join("container")

      expect(will_fail_if_upgraded).to be_installed
      expect(will_fail_if_upgraded_path).to be_a_file
      expect(will_fail_if_upgraded.installed_version).to eq "1.2.2"

      expect do
        described_class.upgrade_casks!(will_fail_if_upgraded, args:)
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
        described_class.upgrade_casks!(bad_checksum, args:)
      end.to raise_error(ChecksumMismatchError).and(not_to_output(output_reverted).to_stderr)

      expect(bad_checksum).to be_installed
      expect(bad_checksum_path).to be_a_directory
      expect(bad_checksum.installed_version).to eq "1.2.2"
      expect(bad_checksum.staged_path).not_to exist
    end
  end

  context "when there were multiple failures" do
    # These tests perform actual upgrades and test error handling,
    # so they need full real installations.
    before do
      [
        "outdated/bad-checksum",
        "outdated/local-transmission-zip",
        "outdated/bad-checksum2",
      ].each do |cask|
        Cask::Installer.new(Cask::CaskLoader.load(cask_path(cask))).install
      end
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
        described_class.upgrade_casks!(args:)
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
