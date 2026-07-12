# typed: true
# frozen_string_literal: true

require "cask/upgrade"

RSpec.describe Cask::Upgrade, :cask do
  let(:version_latest_paths) do
    [
      Pathname(version_latest.config.appdir).join("Caffeine Mini.app"),
      Pathname(version_latest.config.appdir).join("Caffeine Pro.app"),
    ]
  end
  let(:version_latest) { Cask::CaskLoader.load("version-latest") }
  let(:auto_updates_path) { Pathname(auto_updates.config.appdir).join("MyFancyApp.app") }
  let(:auto_updates) { Cask::CaskLoader.load("auto-updates") }
  let(:local_transmission_path) { Pathname(local_transmission.config.appdir).join("Transmission.app") }
  let(:local_transmission) { Cask::CaskLoader.load("local-transmission-zip") }
  let(:local_caffeine_path) { Pathname(local_caffeine.config.appdir).join("Caffeine.app") }
  let(:local_caffeine) { Cask::CaskLoader.load("local-caffeine") }
  let(:renamed_app) { Cask::CaskLoader.load("renamed-app") }
  let(:renamed_app_old_path) { Pathname(renamed_app.config.appdir).join("OldApp.app") }
  let(:renamed_app_new_path) { Pathname(renamed_app.config.appdir).join("NewApp.app") }
  let(:args) do
    parser = Homebrew::CLI::Parser.new(Homebrew::Cmd::Brew)
    parser.cask_options
    parser.args
  end

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
        allow(Homebrew::EnvConfig).to receive(:upgrade_auto_updates_casks?).and_call_original

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

        with_env(HOMEBREW_NO_UPGRADE_AUTO_UPDATES_CASKS: "1") do
          described_class.upgrade_casks!(dry_run: true, args:)
        end
      end

      it "lets HOMEBREW_NO_UPGRADE_AUTO_UPDATES_CASKS override HOMEBREW_UPGRADE_AUTO_UPDATES_CASKS" do
        allow(Homebrew::EnvConfig).to receive(:upgrade_auto_updates_casks?).and_call_original

        with_env(
          "HOMEBREW_UPGRADE_AUTO_UPDATES_CASKS"    => "1",
          "HOMEBREW_NO_UPGRADE_AUTO_UPDATES_CASKS" => "1",
        ) do
          expect { described_class.upgrade_casks!(dry_run: true, args:) }
            .not_to raise_error
        end
      end

      it "lets HOMEBREW_NO_UPGRADE_AUTO_UPDATES_CASKS override the developer default" do
        allow(Homebrew::EnvConfig).to receive(:upgrade_auto_updates_casks?).and_call_original

        with_env(
          "HOMEBREW_DEVELOPER"                     => "1",
          "HOMEBREW_UPGRADE_AUTO_UPDATES_CASKS"    => "1",
          "HOMEBREW_NO_UPGRADE_AUTO_UPDATES_CASKS" => "1",
        ) do
          expect { described_class.upgrade_casks!(dry_run: true, args:) }
            .not_to raise_error
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

      it "records final cask upgrade summary details" do
        summary_upgrades = []
        summary_deprecated = []
        allow(local_caffeine).to receive(:deprecated?).and_return(true)

        described_class.upgrade_casks!(
          local_caffeine,
          dry_run:              true,
          show_upgrade_summary: false,
          summary_upgrades:,
          summary_deprecated:,
          args:,
        )

        expect(summary_upgrades).to include("local-caffeine 1.2.2 -> 1.2.3")
        expect(summary_deprecated).to include("local-caffeine")
      end

      it "passes the quit option to cask upgrades" do
        expect(described_class).to receive(:upgrade_cask) do |_, _, **options|
          expect(options[:quit]).to be(false)
        end

        described_class.upgrade_casks!(
          local_caffeine,
          quit:                 false,
          skip_prefetch:        true,
          show_upgrade_summary: false,
          args:,
        )
      end

      it "excludes pinned Casks" do
        local_caffeine.pin
        summary_pinned = []

        begin
          expect(described_class).not_to receive(:upgrade_cask)
          expect(described_class).to receive(:show_upgrade_summary) do |cask_upgrades, dry_run:|
            expect(dry_run).to be(true)
            expect(cask_upgrades).to include(
              "local-transmission-zip 2.60 -> 2.61",
              "auto-updates 2.57 -> 2.61",
              "renamed-app 1.0.0 -> 2.0.0",
            )
            expect(cask_upgrades.grep(/local-caffeine/)).to be_empty
          end

          described_class.upgrade_casks!(dry_run: true, quiet: true, summary_pinned:, args:)
          expect(summary_pinned).to include("local-caffeine 1.2.2")
        ensure
          local_caffeine.unpin
        end
      end

      it "fails and skips explicitly named pinned Casks" do
        local_caffeine.pin

        begin
          expect(described_class).not_to receive(:upgrade_cask)

          expect do
            described_class.upgrade_casks!(local_caffeine, dry_run: true, args:)
          end.to not_to_output.to_stdout
             .and output(/Not upgrading 1 pinned package:.*local-caffeine 1\.2\.2/m).to_stderr
          expect(Homebrew).to be_failed
        ensure
          local_caffeine.unpin
          Homebrew.failed = false
        end
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
      allow(Cask::CaskLoader).to receive(:load_from_installed_caskfile).and_call_original
      allow(Cask::CaskLoader)
        .to receive(:load_from_installed_caskfile)
        .with(auto_updates.installed_caskfile)
        .and_raise(Cask::CaskInvalidError.new(auto_updates.token, "broken DSL"))

      expect do
        described_class.upgrade_casks!(dry_run: true, args:)
      end.to output(/The cask 'auto-updates' cannot be upgraded as-is/).to_stderr
    end

    it "warns and skips when the installed caskfile raises CaskUnreadableError" do
      allow(Cask::CaskLoader).to receive(:load_from_installed_caskfile).and_call_original
      allow(Cask::CaskLoader)
        .to receive(:load_from_installed_caskfile)
        .with(auto_updates.installed_caskfile)
        .and_raise(Cask::CaskUnreadableError.new(auto_updates.token, "syntax error"))

      expect do
        described_class.upgrade_casks!(dry_run: true, args:)
      end.to output(/The cask 'auto-updates' cannot be upgraded as-is/).to_stderr
    end

    it "warns and skips when the installed caskfile raises MethodDeprecatedError" do
      allow(Cask::CaskLoader).to receive(:load_from_installed_caskfile).and_call_original
      allow(Cask::CaskLoader)
        .to receive(:load_from_installed_caskfile)
        .with(auto_updates.installed_caskfile)
        .and_raise(MethodDeprecatedError.new)

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

  context "when releasing quarantine during upgrade" do
    let(:outdated_auto_updates) { Cask::CaskLoader.load(cask_path("outdated/auto-updates")) }
    let(:outdated_local_caffeine) { Cask::CaskLoader.load(cask_path("outdated/local-caffeine")) }
    let(:auto_updates_identity) do
      Cask::Quarantine::SigningIdentity.new(
        requirement: 'identifier "sh.brew.auto-updates" and certificate leaf[subject.OU] = "ABCDE12345"',
      )
    end
    let(:local_caffeine_identity) do
      Cask::Quarantine::SigningIdentity.new(
        requirement: 'identifier "sh.brew.local-caffeine" and certificate leaf[subject.OU] = "ABCDE12345"',
      )
    end

    before do
      [
        "outdated/local-caffeine",
        "outdated/auto-updates",
      ].each do |cask_name|
        InstallHelper.stub_cask_installation(Cask::CaskLoader.load(cask_path(cask_name)))
      end
    end

    it 'prefetches "auto_updates true" casks with quarantine until signed identity is checked' do
      installer = instance_double(Cask::Installer, check_requirements: nil, enqueue_downloads: nil,
                                                   source_download_requires_pre_fetch?: false)

      expect(Cask::Installer).to receive(:new) do |cask, **options|
        expect(cask).to eq(auto_updates)
        expect(options[:quarantine]).to be(true)
        installer
      end
      expect(described_class).to receive(:upgrade_cask)

      described_class.upgrade_casks!(auto_updates, show_upgrade_summary: false, args:)
    end

    it "releases quarantine when Gatekeeper was already approved and identity matches" do
      allow(Cask::Quarantine).to receive(:signing_identity_match)
        .with(auto_updates_path, auto_updates_identity).and_return(true)

      expect(described_class.quarantine_release_decision(
               outdated_auto_updates,
               auto_updates,
               { auto_updates_path.to_s => auto_updates_identity },
               { auto_updates_path.to_s => true },
             )).to eq(:release)
    end

    it "reports a changed signer when the new app does not satisfy the old designated requirement" do
      allow(Cask::Quarantine).to receive(:signing_identity_match)
        .with(auto_updates_path, auto_updates_identity).and_return(false)

      expect(described_class.quarantine_release_decision(
               outdated_auto_updates,
               auto_updates,
               { auto_updates_path.to_s => auto_updates_identity },
               { auto_updates_path.to_s => true },
             )).to eq(:signer_changed)
    end

    it "reports an unverified signer when the old signing identity is missing" do
      expect(described_class.quarantine_release_decision(
               outdated_auto_updates,
               auto_updates,
               { auto_updates_path.to_s => nil },
               { auto_updates_path.to_s => true },
             )).to eq(:signer_unverified)
    end

    it "reports an unverified signer when the new signing identity is missing" do
      allow(Cask::Quarantine).to receive(:signing_identity_match)
        .with(auto_updates_path, auto_updates_identity).and_return(nil)

      expect(described_class.quarantine_release_decision(
               outdated_auto_updates,
               auto_updates,
               { auto_updates_path.to_s => auto_updates_identity },
               { auto_updates_path.to_s => true },
             )).to eq(:signer_unverified)
    end

    it "reports missing approval when Gatekeeper was not approved" do
      expect(described_class.quarantine_release_decision(
               outdated_auto_updates,
               auto_updates,
               { auto_updates_path.to_s => auto_updates_identity },
               { auto_updates_path.to_s => false },
             )).to eq(:unapproved)
    end

    it "releases quarantine for casks without auto_updates when Gatekeeper was already approved " \
       "and identity matches" do
      allow(Cask::Quarantine).to receive(:signing_identity_match)
        .with(local_caffeine_path, local_caffeine_identity).and_return(true)

      expect(described_class.quarantine_release_decision(
               outdated_local_caffeine,
               local_caffeine,
               { local_caffeine_path.to_s => local_caffeine_identity },
               { local_caffeine_path.to_s => true },
             )).to eq(:release)
    end

    it "reports missing approval for casks without auto_updates when Gatekeeper was not approved" do
      expect(described_class.quarantine_release_decision(
               outdated_local_caffeine,
               local_caffeine,
               { local_caffeine_path.to_s => local_caffeine_identity },
               { local_caffeine_path.to_s => false },
             )).to eq(:unapproved)
    end
  end

  context "when an upgrade decides on quarantine after install" do
    before do
      Cask::Installer.new(Cask::CaskLoader.load(cask_path("outdated/local-caffeine"))).install
      allow(Cask::Quarantine).to receive(:available?).and_return(true)
    end

    it "inherits quarantine approval when the previous version was already approved" do
      identity = Cask::Quarantine::SigningIdentity.new(requirement: 'identifier "sh.brew.local-caffeine"')
      allow(Cask::Quarantine).to receive_messages(
        user_approved?:         true,
        signing_identity:       identity,
        signing_identity_match: true,
      )

      expect(Cask::Quarantine).to receive(:inherit_user_approval!).with(download_path: local_caffeine_path)

      described_class.upgrade_casks!(local_caffeine, args:)
    end

    it "reports the skipped quarantine release under --verbose when approval is missing" do
      allow(Cask::Quarantine).to receive_messages(user_approved?: false, inherit_user_approval!: nil)

      expect do
        described_class.upgrade_casks!(local_caffeine, verbose: true, args:)
      end.to output(/local-caffeine wasn't quarantine approved/).to_stdout
    end

    it "reports a changed signer by default so the returning Gatekeeper prompt is explained" do
      identity = Cask::Quarantine::SigningIdentity.new(requirement: 'identifier "sh.brew.local-caffeine"')
      allow(Cask::Quarantine).to receive_messages(
        user_approved?:         true,
        signing_identity:       identity,
        signing_identity_match: false,
        inherit_user_approval!: nil,
      )

      expect do
        described_class.upgrade_casks!(local_caffeine, args:)
      end.to output(/local-caffeine's signer changed so macOS will prompt/).to_stderr
    end

    it "reports an unverified signer by default so the returning Gatekeeper prompt is explained" do
      identity = Cask::Quarantine::SigningIdentity.new(requirement: 'identifier "sh.brew.local-caffeine"')
      allow(Cask::Quarantine).to receive_messages(
        user_approved?:         true,
        signing_identity:       identity,
        signing_identity_match: nil,
        inherit_user_approval!: nil,
      )

      expect do
        described_class.upgrade_casks!(local_caffeine, args:)
      end.to output(/couldn't verify local-caffeine's signer/).to_stderr
    end
  end

  it "warns and skips disabled casks" do
    cask = Cask::CaskLoader.load(cask_path("livecheck/livecheck-disabled"))
    InstallHelper.stub_cask_installation(cask)
    allow(cask).to receive(:outdated?).with(greedy: true).and_return(true)
    summary_disabled = []

    expect(described_class).not_to receive(:upgrade_cask)

    expect do
      described_class.upgrade_casks!(cask, dry_run: true, summary_disabled:, args:)
    end.to output(/Not upgrading livecheck-disabled, it is disabled/).to_stderr
    expect(summary_disabled).to eq(["livecheck-disabled"])
  end

  context "when upgrading the same cask twice" do
    before do
      Cask::Installer.new(Cask::CaskLoader.load(cask_path("outdated/local-caffeine"))).install
    end

    it "uses the installed metadata version for the second upgrade" do
      described_class.upgrade_casks!(local_caffeine, args:)
      newer_cask = Cask::CaskLoader::FromContentLoader.new(<<~RUBY).load(config: nil)
        cask "local-caffeine" do
          version "1.2.4"
          sha256 "67cdb8a02803ef37fdbf7e0be205863172e41a561ca446cd84f0d7ab35a99d94"

          url "file://#{TEST_FIXTURE_DIR}/cask/caffeine.zip"
          homepage "https://brew.sh/"

          app "Caffeine.app"
        end
      RUBY

      expect do
        described_class.upgrade_casks!(newer_cask, args:)
      end.to change(newer_cask, :installed_version).from("1.2.3").to("1.2.4")
    end
  end

  context "when upgrading after a forced upgrade without a cask receipt" do
    before do
      InstallHelper.stub_cask_installation(Cask::CaskLoader.load(cask_path("outdated/local-caffeine")))
    end

    it "uses the forced upgrade metadata for the next upgrade" do
      receipt_path = local_caffeine.metadata_main_container_path/AbstractTab::FILENAME

      expect(receipt_path).not_to exist
      expect(Cask::CaskLoader.load_from_installed_caskfile(local_caffeine.installed_caskfile).artifacts)
        .to be_empty

      described_class.upgrade_casks!(local_caffeine, force: true, args:)

      expect(receipt_path).to exist
      expect(local_caffeine.tab.installed_on_request).to be(true)
      expect(Cask::CaskLoader.load_from_installed_caskfile(local_caffeine.installed_caskfile).artifacts)
        .to include(an_instance_of(Cask::Artifact::App))

      newer_cask = Cask::CaskLoader::FromContentLoader.new(<<~RUBY).load(config: nil)
        cask "local-caffeine" do
          version "1.2.4"
          sha256 "67cdb8a02803ef37fdbf7e0be205863172e41a561ca446cd84f0d7ab35a99d94"

          url "file://#{TEST_FIXTURE_DIR}/cask/caffeine.zip"
          homepage "https://brew.sh/"

          app "Caffeine.app"
        end
      RUBY

      expect do
        described_class.upgrade_casks!(newer_cask, args:)
      end.to change(newer_cask, :installed_version).from("1.2.3").to("1.2.4")
    end
  end

  context "when an upgrade fails after installing artifacts" do
    before do
      Cask::Installer.new(Cask::CaskLoader.load(cask_path("outdated/local-caffeine"))).install
    end

    it "keeps the old cask receipt" do
      receipt_path = local_caffeine.metadata_main_container_path/AbstractTab::FILENAME

      expect(JSON.parse(receipt_path.read).dig("source", "version")).to eq("1.2.2")

      allow_any_instance_of(Cask::Installer).to receive(:finalize_upgrade)
        .and_raise(Cask::CaskError, "finalize failed")

      expect do
        described_class.upgrade_casks!(local_caffeine, args:)
      end.to raise_error(Cask::CaskError)

      expect(JSON.parse(receipt_path.read).dig("source", "version")).to eq("1.2.2")
    end
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
      will_fail_if_upgraded_path = Pathname(will_fail_if_upgraded.config.appdir).join("container")

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
      bad_checksum_path = Pathname(bad_checksum.config.appdir).join("Caffeine.app")

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

    it "raises the original upgrade error, not a failure that occurs while rolling back" do
      will_fail_if_upgraded = Cask::CaskLoader.load("will-fail-if-upgraded")
      allow_any_instance_of(Cask::Installer).to receive(:revert_upgrade).and_raise("rollback failed")

      expect do
        described_class.upgrade_casks!(will_fail_if_upgraded, args:)
      end.to raise_error(Cask::CaskError)
    end
  end

  context "when there were multiple failures" do
    # This test exercises upgrade error handling, so it needs installed Casks.
    before do
      [
        "outdated/bad-checksum",
        "outdated/local-transmission-zip",
        "outdated/bad-checksum2",
      ].each do |cask|
        InstallHelper.stub_cask_installation(Cask::CaskLoader.load(cask_path(cask)))
      end

      bad_checksum_2_path = Pathname(Cask::CaskLoader.load("bad-checksum2").config.appdir).join("container")
      FileUtils.rm_rf(bad_checksum_2_path)
      FileUtils.touch(bad_checksum_2_path)
    end

    it "does not end the upgrade process" do
      summary_upgrades = []
      upgraded_tokens = []
      bad_checksum = Cask::CaskLoader.load("bad-checksum")
      bad_checksum_path = Pathname(bad_checksum.config.appdir).join("Caffeine.app")

      bad_checksum_2 = Cask::CaskLoader.load("bad-checksum2")
      bad_checksum_2_path = Pathname(bad_checksum_2.config.appdir).join("container")

      expect(bad_checksum).to be_installed
      expect(bad_checksum_path).to be_a_directory
      expect(bad_checksum.installed_version).to eq "1.2.2"

      expect(local_transmission).to be_installed
      expect(local_transmission_path).to be_a_directory
      expect(local_transmission.installed_version).to eq "2.60"

      expect(bad_checksum_2).to be_installed
      expect(bad_checksum_2_path).to be_a_file
      expect(bad_checksum_2.installed_version).to eq "1.2.2"

      allow(described_class).to receive(:upgrade_cask) do |_, new_cask, **|
        upgraded_tokens << new_cask.token
        raise Cask::CaskError, "failed" if new_cask.token.start_with?("bad-checksum")

        InstallHelper.stub_cask_installation(new_cask)
      end

      expect do
        described_class.upgrade_casks!(args:, skip_prefetch: true, summary_upgrades:)
      end.to raise_error(Cask::MultipleCaskErrors)

      expect(upgraded_tokens).to contain_exactly("bad-checksum", "bad-checksum2", "local-transmission-zip")
      expect(summary_upgrades).to contain_exactly("local-transmission-zip 2.60 -> 2.61")

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

  context "when an outdated cask is incompatible" do
    before do
      [
        "outdated/local-caffeine",
        "outdated/local-transmission-zip",
      ].each do |cask|
        InstallHelper.stub_cask_installation(Cask::CaskLoader.load(cask_path(cask)))
      end
    end

    it "continues upgrading compatible casks" do
      summary_upgrades = []
      upgraded_tokens = []
      incompatible_installer = instance_double(Cask::Installer, source_download_requires_pre_fetch?: false)
      compatible_installer = instance_double(Cask::Installer, source_download_requires_pre_fetch?: false)

      allow(incompatible_installer).to receive(:check_requirements)
        .and_raise(Cask::CaskError, "local-caffeine: This cask does not run on macOS versions older than Tahoe.")
      allow(compatible_installer).to receive_messages(check_requirements: nil, enqueue_downloads: nil)
      allow(Cask::Installer).to receive(:new) do |cask, **|
        (cask.token == "local-caffeine") ? incompatible_installer : compatible_installer
      end
      allow(described_class).to receive(:upgrade_cask) do |_, new_cask, **|
        upgraded_tokens << new_cask.token
      end

      expect do
        described_class.upgrade_casks!(
          local_caffeine, local_transmission,
          show_upgrade_summary: false,
          summary_upgrades:,
          args:
        )
      end.to raise_error(
        Cask::CaskError,
        "local-caffeine: This cask does not run on macOS versions older than Tahoe.",
      )

      expect(upgraded_tokens).to eq(["local-transmission-zip"])
      expect(summary_upgrades).to eq(["local-transmission-zip 2.60 -> 2.61"])
    end

    it "raises prefetched requirement errors after compatible casks" do
      summary_upgrades = []
      upgraded_tokens = []
      cask_error = Cask::CaskError.new(
        "local-caffeine: This cask does not run on macOS versions older than Tahoe.",
      )

      allow(described_class).to receive(:upgrade_cask) do |_, new_cask, **|
        upgraded_tokens << new_cask.token
      end

      expect do
        described_class.upgrade_casks!(
          local_transmission,
          skip_prefetch:        true,
          show_upgrade_summary: false,
          summary_upgrades:,
          prefetched_errors:    [cask_error],
          args:,
        )
      end.to raise_error(Cask::CaskError, cask_error.message)

      expect(upgraded_tokens).to eq(["local-transmission-zip"])
      expect(summary_upgrades).to eq(["local-transmission-zip 2.60 -> 2.61"])
    end
  end
end
