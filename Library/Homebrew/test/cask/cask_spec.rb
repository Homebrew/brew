# typed: false
# frozen_string_literal: true

RSpec.describe Cask::Cask, :cask do
  def write_info_plist(path, short_version: nil, bundle_version: nil, contents: nil)
    info_plist = path/"Contents/Info.plist"
    info_plist.dirname.mkpath

    if contents
      info_plist.write(contents)
      return
    end

    entries = []
    if short_version
      entries << <<~PLIST.chomp
        <key>CFBundleShortVersionString</key>
        <string>#{short_version}</string>
      PLIST
    end
    if bundle_version
      entries << <<~PLIST.chomp
        <key>CFBundleVersion</key>
        <string>#{bundle_version}</string>
      PLIST
    end

    info_plist.write <<~PLIST
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <plist version="1.0">
      <dict>
      #{entries.join("\n")}
      </dict>
      </plist>
    PLIST
  end

  def write_auto_updates_cask(path, version:, artifacts:, token: "auto-updates-bundle-check")
    path.write <<~RUBY
      cask "#{token}" do
        version "#{version}"
        sha256 "5633c3a0f2e572cbf021507dec78c50998b398c343232bdfc7e26221d0a5db4d"

        url "file://#{TEST_FIXTURE_DIR}/cask/MyFancyApp.zip"
        homepage "https://brew.sh/MyFancyApp"

        auto_updates true

        #{artifacts.join("\n  ")}
      end
    RUBY

    Cask::CaskLoader.load(path)
  end

  let(:cask) { described_class.new("versioned-cask") }

  context "when multiple versions are installed" do
    describe "#installed_version" do
      context "when there are duplicate versions" do
        it "uses the last unique version" do
          allow(cask).to receive(:timestamped_versions).and_return([
            ["1.2.2", "0999"],
            ["1.2.3", "1000"],
            ["1.2.2", "1001"],
          ])

          # Installed caskfile must exist to count as installed.
          allow_any_instance_of(Pathname).to receive(:exist?).and_return(true)

          expect(cask).to receive(:timestamped_versions)
          expect(cask.installed_version).to eq("1.2.2")
        end
      end
    end
  end

  describe "load" do
    let(:tap_path) { CoreCaskTap.instance.path }
    let(:file_dirname) { Pathname.new(__FILE__).dirname }
    let(:relative_tap_path) { tap_path.relative_path_from(file_dirname) }

    it "returns an instance of the Cask for the given token" do
      c = Cask::CaskLoader.load("local-caffeine")
      expect(c).to be_a(described_class)
      expect(c.token).to eq("local-caffeine")
    end

    it "returns an instance of the Cask from a specific file location" do
      c = Cask::CaskLoader.load("#{tap_path}/Casks/local-caffeine.rb")
      expect(c).to be_a(described_class)
      expect(c).not_to be_loaded_from_api
      expect(c).not_to be_loaded_from_internal_api
      expect(c.token).to eq("local-caffeine")
    end

    it "returns an instance of the Cask from a JSON file" do
      c = Cask::CaskLoader.load("#{TEST_FIXTURE_DIR}/cask/caffeine.json")
      expect(c).to be_a(described_class)
      expect(c).to be_loaded_from_api
      expect(c).not_to be_loaded_from_internal_api
      expect(c.token).to eq("caffeine")
    end

    it "returns an instance of the Cask from an internal JSON file" do
      c = Cask::CaskLoader.load("#{TEST_FIXTURE_DIR}/cask/caffeine.internal.json")
      expect(c).to be_a(described_class)
      expect(c).to be_loaded_from_api
      expect(c).to be_loaded_from_internal_api
      expect(c.token).to eq("caffeine")
    end

    it "returns an instance of the Cask from a URL", :needs_utils_curl do
      c = Cask::CaskLoader.load("file://#{tap_path}/Casks/local-caffeine.rb")
      expect(c).to be_a(described_class)
      expect(c.token).to eq("local-caffeine")
    end

    it "raises an error when failing to download a Cask from a URL", :needs_utils_curl do
      expect do
        Cask::CaskLoader.load("file://#{tap_path}/Casks/notacask.rb")
      end.to raise_error(Cask::CaskUnavailableError)
    end

    it "returns an instance of the Cask from a relative file location" do
      c = Cask::CaskLoader.load(relative_tap_path/"Casks/local-caffeine.rb")
      expect(c).to be_a(described_class)
      expect(c.token).to eq("local-caffeine")
    end

    it "uses exact match when loading by token" do
      expect(Cask::CaskLoader.load("test-opera").token).to eq("test-opera")
      expect(Cask::CaskLoader.load("test-opera-mail").token).to eq("test-opera-mail")
    end

    it "raises an error when attempting to load a Cask that doesn't exist" do
      expect do
        Cask::CaskLoader.load("notacask")
      end.to raise_error(Cask::CaskUnavailableError)
    end
  end

  describe "metadata" do
    it "proposes a versioned metadata directory name for each instance" do
      cask_token = "local-caffeine"
      c = Cask::CaskLoader.load(cask_token)
      metadata_timestamped_path = Cask::Caskroom.path.join(cask_token, ".metadata", c.version)
      expect(c.metadata_versioned_path.to_s).to eq(metadata_timestamped_path.to_s)
    end
  end

  describe "outdated" do
    it "ignores the Casks that have auto_updates true (without --greedy)" do
      c = Cask::CaskLoader.load("auto-updates")
      expect(c).not_to be_outdated
      expect(c.outdated_version).to be_nil
    end

    it "ignores the Casks that have version :latest (without --greedy)" do
      c = Cask::CaskLoader.load("version-latest-string")
      expect(c).not_to be_outdated
      expect(c.outdated_version).to be_nil
    end

    describe "versioned casks" do
      subject { cask.outdated_version }

      let(:cask) { described_class.new("basic-cask") }

      shared_examples "versioned casks" do |tap_version, expectations|
        expectations.each do |installed_version, expected_output|
          context "when version #{installed_version.inspect} is installed and the tap version is #{tap_version}" do
            it {
              allow(cask).to receive_messages(installed_version:,
                                              version:           Cask::DSL::Version.new(tap_version))
              expect(cask).to receive(:outdated_version).and_call_original
              expect(subject).to eq expected_output
            }
          end
        end
      end

      describe "installed version is equal to tap version => not outdated" do
        include_examples "versioned casks", "1.2.3",
                         "1.2.3" => nil
      end

      describe "installed version is different than tap version => outdated" do
        include_examples "versioned casks", "1.2.4",
                         "1.2.3" => "1.2.3",
                         "1.2.4" => nil
      end
    end

    describe "auto-updating versioned casks with bundle metadata" do
      let(:dir) { Pathname(mktmpdir) }
      let(:cask_file) { dir/"auto-updates-bundle-check.rb" }
      let(:artifacts) { ['app "MyFancyApp.app"'] }

      before do
        allow(Homebrew::EnvConfig).to receive(:upgrade_auto_updates_casks?).and_return(true)
      end

      it "is outdated when the installed short version is lower than the tap version" do
        tap_version = "2.61"
        cask = write_auto_updates_cask(cask_file, version: tap_version, artifacts:)
        allow(cask).to receive(:installed_version).and_return("2.57")
        write_info_plist(cask.config.appdir/"MyFancyApp.app", short_version: "2.57", bundle_version: "2057")

        expect(cask.outdated_version).to eq("2.57")
      end

      it "is not outdated when the short version matches and the bundle version is lower than a CSV candidate" do
        tap_version = "2.61,3000"
        cask = write_auto_updates_cask(cask_file, version: tap_version, artifacts:)
        allow(cask).to receive(:installed_version).and_return("2.57")
        write_info_plist(cask.config.appdir/"MyFancyApp.app", short_version: "2.61", bundle_version: "2057")

        expect(cask.outdated_version).to be_nil
      end

      it "is not outdated when the short version matches and the bundle version matches any CSV candidate" do
        tap_version = "2.61,3000,2057"
        cask = write_auto_updates_cask(cask_file, version: tap_version, artifacts:)
        allow(cask).to receive(:installed_version).and_return("2.57")
        write_info_plist(cask.config.appdir/"MyFancyApp.app", short_version: "2.61", bundle_version: "2057")

        expect(cask.outdated_version).to be_nil
      end

      it "is not outdated when the installed short version is higher than the tap version" do
        tap_version = "2.61"
        cask = write_auto_updates_cask(cask_file, version: tap_version, artifacts:)
        allow(cask).to receive(:installed_version).and_return("2.57")
        write_info_plist(cask.config.appdir/"MyFancyApp.app", short_version: "2.62", bundle_version: "2057")

        expect(cask.outdated_version).to be_nil
      end

      it "is not outdated when the installed cask version already matches the tap version" do
        tap_version = "2.61"
        cask = write_auto_updates_cask(cask_file, version: tap_version, artifacts:)
        allow(cask).to receive(:installed_version).and_return("2.61")
        write_info_plist(cask.config.appdir/"MyFancyApp.app", short_version: "2.57", bundle_version: "2057")

        expect(cask.outdated_version).to be_nil
      end

      it "is not outdated when the installed short version directly matches the tap version" do
        tap_version = "2.61"
        cask = write_auto_updates_cask(cask_file, version: tap_version, artifacts:)
        allow(cask).to receive(:installed_version).and_return("2.57")
        write_info_plist(cask.config.appdir/"MyFancyApp.app", short_version: "2.61", bundle_version: "2057")

        expect(cask.outdated_version).to be_nil
      end

      it "is not outdated when the installed bundle version directly matches the tap version" do
        tap_version = "2057"
        cask = write_auto_updates_cask(cask_file, version: tap_version, artifacts:)
        allow(cask).to receive(:installed_version).and_return("2.57")
        write_info_plist(cask.config.appdir/"MyFancyApp.app", short_version: "2.61", bundle_version: "2057")

        expect(cask.outdated_version).to be_nil
      end

      it "is not outdated when the installed short version matches a CSV build candidate" do
        tap_version = "2.61,2057"
        cask = write_auto_updates_cask(cask_file, version: tap_version, artifacts:)
        allow(cask).to receive(:installed_version).and_return("2.57")
        write_info_plist(cask.config.appdir/"MyFancyApp.app", short_version: "2057", bundle_version: "3000")

        expect(cask.outdated_version).to be_nil
      end

      it "is not outdated when the short version matches and the bundle version is higher than all CSV candidates" do
        tap_version = "2.61,2056,2055"
        cask = write_auto_updates_cask(cask_file, version: tap_version, artifacts:)
        allow(cask).to receive(:installed_version).and_return("2.57")
        write_info_plist(cask.config.appdir/"MyFancyApp.app", short_version: "2.61", bundle_version: "2057")

        expect(cask.outdated_version).to be_nil
      end

      it "matches a bundle version candidate that is not first in the CSV list" do
        tap_version = "2.61,3000,2057"
        cask = write_auto_updates_cask(cask_file, version: tap_version, artifacts:)
        allow(cask).to receive(:installed_version).and_return("2.57")
        write_info_plist(cask.config.appdir/"MyFancyApp.app", short_version: "2.61", bundle_version: "2057")

        expect(cask.version.csv.first).not_to eq("2057")
        expect(cask.outdated_version).to be_nil
      end

      it "is not outdated when the app bundle metadata cannot be read" do
        tap_version = "2.61"
        cask = write_auto_updates_cask(cask_file, version: tap_version, artifacts:)
        allow(cask).to receive(:installed_version).and_return("2.57")

        expect(cask.outdated_version).to be_nil
      end

      it "falls back to the bundle version when the short version is missing" do
        tap_version = "2.61,3000"
        cask = write_auto_updates_cask(cask_file, version: tap_version, artifacts:)
        allow(cask).to receive(:installed_version).and_return("2.57")
        write_info_plist(cask.config.appdir/"MyFancyApp.app", bundle_version: "2057")

        expect(cask.outdated_version).to eq("2.57")
      end

      it "ignores bad bundle versions when the short version is missing" do
        tap_version = "2026.406.0"
        cask = write_auto_updates_cask(cask_file, version: tap_version, artifacts:)
        allow(cask).to receive(:installed_version).and_return("2025.816.0")
        write_info_plist(cask.config.appdir/"MyFancyApp.app", bundle_version: "0.0")

        expect(cask.outdated_version).to be_nil
      end

      it "is not outdated when plist version segment counts differ from the tap version" do
        tap_version = "1.0"
        cask = write_auto_updates_cask(cask_file, version: tap_version, artifacts:)
        allow(cask).to receive(:installed_version).and_return("0.9")
        write_info_plist(cask.config.appdir/"MyFancyApp.app", short_version: "1", bundle_version: "200")

        expect(cask.outdated_version).to be_nil
      end
    end

    describe ":latest casks" do
      let(:cask) { described_class.new("basic-cask") }

      shared_examples ":latest cask" do |greedy, outdated_sha, tap_version, expectations|
        expectations.each do |installed_version, expected_output|
          context "when versions #{installed_version} are installed and the " \
                  "tap version is #{tap_version}, #{"not " unless greedy}greedy " \
                  "and sha is #{"not " unless outdated_sha}outdated" do
            subject { cask.outdated_version(greedy:) }

            it {
              allow(cask).to receive_messages(installed_version:,
                                              version:                Cask::DSL::Version.new(tap_version),
                                              outdated_download_sha?: outdated_sha)
              expect(cask).to receive(:outdated_version).and_call_original
              expect(subject).to eq expected_output
            }
          end
        end
      end

      describe ":latest version installed, :latest version in tap" do
        include_examples ":latest cask", false, false, "latest",
                         "latest" => nil
        include_examples ":latest cask", true, false, "latest",
                         "latest" => nil
        include_examples ":latest cask", true, true, "latest",
                         "latest" => "latest"
      end

      describe "numbered version installed, :latest version in tap" do
        include_examples ":latest cask", false, false, "latest",
                         "1.2.3" => nil
        include_examples ":latest cask", true, false, "latest",
                         "1.2.3" => nil
        include_examples ":latest cask", true, true, "latest",
                         "1.2.3" => "1.2.3"
      end

      describe "latest version installed, numbered version in tap" do
        include_examples ":latest cask", false, false, "1.2.3",
                         "latest" => "latest"
        include_examples ":latest cask", true, false, "1.2.3",
                         "latest" => "latest"
        include_examples ":latest cask", true, true, "1.2.3",
                         "latest" => "latest"
      end
    end
  end

  describe "full_name" do
    context "when it is a core cask" do
      it "is the cask token" do
        c = Cask::CaskLoader.load("local-caffeine")
        expect(c.full_name).to eq("local-caffeine")
      end
    end

    context "when it is from a non-core tap" do
      it "returns the fully-qualified name of the cask" do
        c = Cask::CaskLoader.load("third-party/tap/third-party-cask")
        expect(c.full_name).to eq("third-party/tap/third-party-cask")
      end
    end

    context "when it is from no known tap" do
      it "returns the cask token" do
        file = Tempfile.new(%w[tapless-cask .rb])

        begin
          cask_name = File.basename(file.path, ".rb")
          file.write "cask '#{cask_name}'"
          file.close

          c = Cask::CaskLoader.load(file.path)
          expect(c.full_name).to eq(cask_name)
        ensure
          file.close
          file.unlink
        end
      end
    end
  end

  describe "#artifacts_list" do
    subject(:cask) { Cask::CaskLoader.load("many-artifacts") }

    it "returns all artifacts when no options are given" do
      expected_artifacts = [
        { uninstall_preflight: nil },
        { preflight: nil },
        { uninstall: [{
          rmdir: "#{TEST_TMPDIR}/empty_directory_path",
          trash: ["#{TEST_TMPDIR}/foo", "#{TEST_TMPDIR}/bar"],
        }] },
        { pkg: ["ManyArtifacts/ManyArtifacts.pkg"] },
        { app: ["ManyArtifacts/ManyArtifacts.app"] },
        { uninstall_postflight: nil },
        { postflight: nil },
        { zap: [{
          rmdir: ["~/Library/Caches/ManyArtifacts", "~/Library/Application Support/ManyArtifacts"],
          trash: "~/Library/Logs/ManyArtifacts.log",
        }] },
      ]

      expect(cask.artifacts_list).to eq(expected_artifacts)
    end

    it "returns only uninstall artifacts when uninstall_only is true" do
      expected_artifacts = [
        { uninstall_preflight: nil },
        { uninstall: [{
          rmdir: "#{TEST_TMPDIR}/empty_directory_path",
          trash: ["#{TEST_TMPDIR}/foo", "#{TEST_TMPDIR}/bar"],
        }] },
        { app: ["ManyArtifacts/ManyArtifacts.app"] },
        { uninstall_postflight: nil },
        { zap: [{
          rmdir: ["~/Library/Caches/ManyArtifacts", "~/Library/Application Support/ManyArtifacts"],
          trash: "~/Library/Logs/ManyArtifacts.log",
        }] },
      ]

      expect(cask.artifacts_list(uninstall_only: true)).to eq(expected_artifacts)
    end
  end

  describe "#rename_list" do
    subject(:cask) { Cask::CaskLoader.load("many-renames") }

    it "returns the correct rename list" do
      expect(cask.rename_list).to eq([
        { from: "Foobar.app", to: "Foo.app" },
        { from: "Foo.app", to: "Bar.app" },
      ])
    end
  end

  describe "#uninstall_flight_blocks?" do
    matcher :have_uninstall_flight_blocks do
      match do |actual|
        actual.uninstall_flight_blocks? == true
      end
    end

    it "returns true when there are uninstall_preflight blocks" do
      cask = Cask::CaskLoader.load("with-uninstall-preflight")
      expect(cask).to have_uninstall_flight_blocks
    end

    it "returns true when there are uninstall_postflight blocks" do
      cask = Cask::CaskLoader.load("with-uninstall-postflight")
      expect(cask).to have_uninstall_flight_blocks
    end

    it "returns false when there are only preflight blocks" do
      cask = Cask::CaskLoader.load("with-preflight")
      expect(cask).not_to have_uninstall_flight_blocks
    end

    it "returns false when there are only postflight blocks" do
      cask = Cask::CaskLoader.load("with-postflight")
      expect(cask).not_to have_uninstall_flight_blocks
    end

    it "returns false when there are no flight blocks" do
      cask = Cask::CaskLoader.load("local-caffeine")
      expect(cask).not_to have_uninstall_flight_blocks
    end
  end

  describe "#contains_os_specific_artifacts?" do
    it "returns false when there are no OSes defined" do
      cask = described_class.new("test-no-os") do
        version "0.0.1,2"

        url "https://brew.sh/test-0.0.1.dmg"
        name "Test"
        desc "Test cask"
        homepage "https://brew.sh"
      end

      expect(cask.contains_os_specific_artifacts?).to be false
    end

    it "returns false when there are no artifacts" do
      cask = described_class.new("test-os-no-artifacts") do
        os macos: "mac", linux: "Linux"
        version "0.0.1,2"

        url "https://brew.sh/test-0.0.1.dmg"
        name "Test"
        desc "Test cask"
        homepage "https://brew.sh"
      end

      expect(cask.contains_os_specific_artifacts?).to be false
    end

    it "returns false when there are scoped app" do
      cask = described_class.new("test-macos-app-artifact") do
        version "0.0.1,2"

        url "https://brew.sh/test-0.0.1.dmg"
        name "Test"
        desc "Test cask"
        homepage "https://brew.sh"

        on_macos do
          app "Test.app"
        end
      end

      expect(cask.contains_os_specific_artifacts?).to be false
    end

    it "returns false when version is only defined in on_* blocks and referenced at top level" do
      cask = described_class.new("test-version-in-on-blocks") do
        on_monterey :or_newer do
          version "2.0"
        end
        on_big_sur :or_older do
          version "1.0"
        end

        url "https://brew.sh/test-#{version.major}.dmg"
        name "Test"
        desc "Test cask"
        homepage "https://brew.sh"
      end

      expect(cask.contains_os_specific_artifacts?).to be false
    end

    it "returns true when there are unscoped app artifacts" do
      cask = described_class.new("test-os-app-artifact") do
        os macos: "mac", linux: "Linux"
        version "0.0.1,2"

        url "https://brew.sh/test-0.0.1.dmg"
        name "Test"
        desc "Test cask"
        homepage "https://brew.sh"

        app "Test.app"
      end

      expect(cask.contains_os_specific_artifacts?).to be true
    end
  end

  describe "#supports_linux?" do
    it "returns false for casks with bare depends_on :macos" do
      expect(Cask::CaskLoader.load("with-depends-on-macos-bare").supports_linux?).to be false
    end

    it "reflects whether the cask has only platform-agnostic artifacts" do
      expect(Cask::CaskLoader.load("with-non-executable-binary").supports_linux?).to be true
      expect(Cask::CaskLoader.load("basic-cask").supports_linux?).to be false
      expect(Cask::CaskLoader.load("with-installer-manual").supports_linux?).to be false

      arch_only_cask = described_class.new("arch-only-binary") do
        version "1.0"
        sha256 arm: "aaaa", intel: "bbbb"

        url "https://brew.sh/test-#{version}.tar.gz"
        name "Arch Only Binary"
        desc "Cask with arch-only sha256 and a binary artifact"
        homepage "https://brew.sh"

        binary "some-tool"
      end

      expect(arch_only_cask.supports_linux?).to be true
    end
  end

  describe "#to_h" do
    let(:expected_json) { (TEST_FIXTURE_DIR/"cask/everything.json").read.strip }

    context "when loaded from cask file" do
      it "returns expected hash" do
        allow(MacOS).to receive(:version).and_return(MacOSVersion.new("14"))

        cask = Cask::CaskLoader.load("everything")

        expect(cask.tap).to receive(:git_head).and_return("abcdef1234567890abcdef1234567890abcdef12")

        hash = cask.to_h

        expect(hash).to be_a(Hash)
        expect(JSON.pretty_generate(hash)).to eq(expected_json)
      end
    end

    context "when loaded from json file" do
      it "returns expected hash" do
        expect(Homebrew::API::Cask).not_to receive(:source_download)
        hash = Cask::CaskLoader::FromAPILoader.new(
          "everything", from_json: JSON.parse(expected_json)
        ).load(config: nil).to_h

        expect(hash).to be_a(Hash)
        expect(JSON.pretty_generate(hash)).to eq(expected_json)
      end
    end
  end

  describe "#to_hash_with_variations" do
    let!(:original_macos_version) { MacOS.full_version.to_s }
    let(:expected_versions_variations) do
      <<~JSON
        {
          "tahoe": {
            "url": "file://#{TEST_FIXTURE_DIR}/cask/caffeine/darwin/1.2.3/intel.zip"
          },
          "sequoia": {
            "url": "file://#{TEST_FIXTURE_DIR}/cask/caffeine/darwin/1.2.3/intel.zip"
          },
          "sonoma": {
            "url": "file://#{TEST_FIXTURE_DIR}/cask/caffeine/darwin/1.2.3/intel.zip"
          },
          "ventura": {
            "url": "file://#{TEST_FIXTURE_DIR}/cask/caffeine/darwin/1.2.3/intel.zip"
          },
          "monterey": {
            "url": "file://#{TEST_FIXTURE_DIR}/cask/caffeine/darwin/1.2.3/intel.zip"
          },
          "big_sur": {
            "url": "file://#{TEST_FIXTURE_DIR}/cask/caffeine/darwin/1.2.0/intel.zip",
            "version": "1.2.0",
            "sha256": "8c62a2b791cf5f0da6066a0a4b6e85f62949cd60975da062df44adf887f4370b"
          },
          "arm64_big_sur": {
            "url": "file://#{TEST_FIXTURE_DIR}/cask/caffeine/darwin-arm64/1.2.0/arm.zip",
            "version": "1.2.0",
            "sha256": "8c62a2b791cf5f0da6066a0a4b6e85f62949cd60975da062df44adf887f4370b"
          },
          "catalina": {
            "url": "file://#{TEST_FIXTURE_DIR}/cask/caffeine/darwin/1.0.0/intel.zip",
            "version": "1.0.0",
            "sha256": "1866dfa833b123bb8fe7fa7185ebf24d28d300d0643d75798bc23730af734216"
          }
        }
      JSON
    end
    let(:expected_sha256_variations) do
      <<~JSON
        {
          "tahoe": {
            "url": "file://#{TEST_FIXTURE_DIR}/cask/caffeine-intel.zip",
            "sha256": "8c62a2b791cf5f0da6066a0a4b6e85f62949cd60975da062df44adf887f4370b"
          },
          "sequoia": {
            "url": "file://#{TEST_FIXTURE_DIR}/cask/caffeine-intel.zip",
            "sha256": "8c62a2b791cf5f0da6066a0a4b6e85f62949cd60975da062df44adf887f4370b"
          },
          "sonoma": {
            "url": "file://#{TEST_FIXTURE_DIR}/cask/caffeine-intel.zip",
            "sha256": "8c62a2b791cf5f0da6066a0a4b6e85f62949cd60975da062df44adf887f4370b"
          },
          "ventura": {
            "url": "file://#{TEST_FIXTURE_DIR}/cask/caffeine-intel.zip",
            "sha256": "8c62a2b791cf5f0da6066a0a4b6e85f62949cd60975da062df44adf887f4370b"
          },
          "monterey": {
            "url": "file://#{TEST_FIXTURE_DIR}/cask/caffeine-intel.zip",
            "sha256": "8c62a2b791cf5f0da6066a0a4b6e85f62949cd60975da062df44adf887f4370b"
          },
          "big_sur": {
            "url": "file://#{TEST_FIXTURE_DIR}/cask/caffeine-intel.zip",
            "sha256": "8c62a2b791cf5f0da6066a0a4b6e85f62949cd60975da062df44adf887f4370b"
          },
          "catalina": {
            "url": "file://#{TEST_FIXTURE_DIR}/cask/caffeine-intel.zip",
            "sha256": "8c62a2b791cf5f0da6066a0a4b6e85f62949cd60975da062df44adf887f4370b"
          }
        }
      JSON
    end
    let(:expected_sha256_variations_os) do
      <<~JSON
        {
          "tahoe": {
            "url": "file://#{TEST_FIXTURE_DIR}/cask/caffeine-intel-darwin.zip",
            "sha256": "8c62a2b791cf5f0da6066a0a4b6e85f62949cd60975da062df44adf887f4370b"
          },
          "sequoia": {
            "url": "file://#{TEST_FIXTURE_DIR}/cask/caffeine-intel-darwin.zip",
            "sha256": "8c62a2b791cf5f0da6066a0a4b6e85f62949cd60975da062df44adf887f4370b"
          },
          "sonoma": {
            "url": "file://#{TEST_FIXTURE_DIR}/cask/caffeine-intel-darwin.zip",
            "sha256": "8c62a2b791cf5f0da6066a0a4b6e85f62949cd60975da062df44adf887f4370b"
          },
          "ventura": {
            "url": "file://#{TEST_FIXTURE_DIR}/cask/caffeine-intel-darwin.zip",
            "sha256": "8c62a2b791cf5f0da6066a0a4b6e85f62949cd60975da062df44adf887f4370b"
          },
          "monterey": {
            "url": "file://#{TEST_FIXTURE_DIR}/cask/caffeine-intel-darwin.zip",
            "sha256": "8c62a2b791cf5f0da6066a0a4b6e85f62949cd60975da062df44adf887f4370b"
          },
          "big_sur": {
            "url": "file://#{TEST_FIXTURE_DIR}/cask/caffeine-intel-darwin.zip",
            "sha256": "8c62a2b791cf5f0da6066a0a4b6e85f62949cd60975da062df44adf887f4370b"
          },
          "catalina": {
            "url": "file://#{TEST_FIXTURE_DIR}/cask/caffeine-intel-darwin.zip",
            "sha256": "8c62a2b791cf5f0da6066a0a4b6e85f62949cd60975da062df44adf887f4370b"
          },
          "x86_64_linux": {
            "url": "file://#{TEST_FIXTURE_DIR}/cask/caffeine-intel-linux.zip",
            "sha256": "8c62a2b791cf5f0da6066a0a4b6e85f62949cd60975da062df44adf887f4370b"
          },
          "arm64_linux": {
            "url": "file://#{TEST_FIXTURE_DIR}/cask/caffeine-arm-linux.zip"
          }
        }
      JSON
    end

    before do
      # For consistency, always run on Monterey and ARM
      MacOS.full_version = "12"
      allow(Hardware::CPU).to receive(:type).and_return(:arm)
    end

    after do
      MacOS.full_version = original_macos_version
    end

    it "returns the correct variations hash for a cask with multiple versions" do
      c = Cask::CaskLoader.load("multiple-versions")
      h = c.to_hash_with_variations

      expect(h).to be_a(Hash)
      expect(JSON.pretty_generate(h["variations"])).to eq expected_versions_variations.strip
    end

    it "returns the correct variations hash for a cask different sha256s on each arch" do
      c = Cask::CaskLoader.load("sha256-arch")
      h = c.to_hash_with_variations

      expect(h).to be_a(Hash)
      expect(JSON.pretty_generate(h["variations"])).to eq expected_sha256_variations.strip
    end

    it "returns the correct variations hash for a cask different sha256s on each arch and os" do
      c = Cask::CaskLoader.load("sha256-os")
      h = c.to_hash_with_variations

      expect(h).to be_a(Hash)
      expect(JSON.pretty_generate(h["variations"])).to eq expected_sha256_variations_os.strip
    end

    # NOTE: The calls to `Cask.generating_hash!` and `Cask.generated_hash!`
    #       are not idempotent so they can only be used in one test.
    it "returns the correct hash placeholders" do
      described_class.generating_hash!
      expect(described_class).to be_generating_hash
      c = Cask::CaskLoader.load("placeholders")
      h = c.to_hash_with_variations
      described_class.generated_hash!
      expect(described_class).not_to be_generating_hash

      expect(h).to be_a(Hash)
      expect(h["artifacts"].first[:binary].first).to eq "$APPDIR/some/path"
      expect(h["caveats"]).to eq "$HOMEBREW_PREFIX and /$HOME\n"
    end

    context "when loaded from json file" do
      let(:expected_json) { (TEST_FIXTURE_DIR/"cask/everything-with-variations.json").read.strip }

      it "returns expected hash with variations" do
        expect(Homebrew::API::Cask).not_to receive(:source_download)
        cask = Cask::CaskLoader::FromAPILoader.new("everything-with-variations", from_json: JSON.parse(expected_json))
                                              .load(config: nil)

        hash = cask.to_hash_with_variations

        expect(cask.loaded_from_api?).to be true
        expect(cask.loaded_from_internal_api?).to be false
        expect(hash).to be_a(Hash)
        expect(JSON.pretty_generate(hash)).to eq(expected_json)
      end
    end
  end
end
