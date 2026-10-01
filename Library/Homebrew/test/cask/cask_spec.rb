# typed: true
# frozen_string_literal: true

RSpec.describe Cask::Cask, :cask do
  let(:cask) { described_class.new("versioned-cask") }

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

  describe ".all" do
    it "skips untrusted tap casks when trust is enabled" do
      tap = Tap.fetch("thirdparty", "foo")
      cask_path = tap.cask_dir/"untrusted.rb"
      cask_path.dirname.mkpath
      cask_path.write <<~RUBY
        raise "untrusted cask evaluated"
      RUBY

      allow(CoreCaskTap.instance).to receive(:cask_tokens).and_return([])
      allow(Tap).to receive(:reject).and_return([tap])
      expect(Cask::CaskLoader).not_to receive(:load).with(cask_path)

      expect { expect(described_class.all).to eq([]) }
        .to output(%r{Skipping thirdparty/foo because it is not trusted}).to_stderr
    ensure
      FileUtils.rm_rf HOMEBREW_TAP_DIRECTORY/"thirdparty"
    end

    it "allows all casks when trust is disabled" do
      allow(CoreCaskTap.instance).to receive(:cask_tokens).and_return([])
      allow(Tap).to receive(:reject).and_return([])
      allow(Homebrew::EnvConfig).to receive(:no_require_tap_trust?).and_return(true)

      expect(described_class.all).to eq([])
    end

    it "skips invalid casks instead of aborting" do
      tap = Tap.fetch("thirdparty", "foo")
      cask_path = tap.cask_dir/"mismatch.rb"
      cask_path.dirname.mkpath
      cask_path.write <<~RUBY
        cask "not-mismatch" do
          version "1.0"
          sha256 :no_check
          url "https://example.com/foo.zip"
          name "Foo"
          app "Foo.app"
        end
      RUBY

      allow(CoreCaskTap.instance).to receive(:cask_tokens).and_return([])
      allow(Tap).to receive(:reject).and_return([tap])
      allow(Homebrew::EnvConfig).to receive(:no_require_tap_trust?).and_return(true)

      expect { expect(described_class.all).to eq([]) }
        .to output(/Cask 'mismatch' definition is invalid/).to_stderr
    ensure
      FileUtils.rm_rf HOMEBREW_TAP_DIRECTORY/"thirdparty"
    end
  end

  describe "#any_version_installed?" do
    it "matches #installed?" do
      allow(cask).to receive(:installed?).and_return(true)

      expect(cask.any_version_installed?).to be true
    end
  end

  context "when multiple versions are installed" do
    describe "#installed_version" do
      context "when there are duplicate versions" do
        it "uses the last unique version" do
          Dir.mktmpdir do |dir|
            allow(Cask::Caskroom).to receive(:path).and_return(Pathname(dir))
            [
              ["1.2.2", "0999"],
              ["1.2.3", "1000"],
              ["1.2.2", "1001"],
            ].each do |version, timestamp|
              casks_dir = Pathname(dir)/"versioned-cask/.metadata/#{version}/#{timestamp}/Casks"
              casks_dir.mkpath
              # Installed caskfile must exist to count as installed.
              (casks_dir/"versioned-cask.rb").write("cask \"versioned-cask\"\n")
            end

            expect(cask.installed_version).to eq("1.2.2")
          end
        end
      end
    end
  end

  describe "#pinned?" do
    it "ignores and replaces a dangling pin" do
      HOMEBREW_PINNED_CASKS.mkpath
      cask.pin_path.make_relative_symlink(cask.caskroom_path/"missing")

      expect(cask).not_to be_pinned
      expect(cask.pinned_version).to be_nil

      allow(cask).to receive(:installed_version).and_return("1.0")
      (cask.caskroom_path/"1.0").mkpath
      cask.pin

      expect(cask).to be_pinned
      expect(cask.pinned_version).to eq("1.0")
    end

    it "replaces a regular file pin record" do
      HOMEBREW_PINNED_CASKS.mkpath
      cask.pin_path.write("not a symlink")
      allow(cask).to receive(:installed_version).and_return("1.0")
      (cask.caskroom_path/"1.0").mkpath

      cask.pin

      expect(cask).to be_pinned
      expect(cask.pin_path).to be_a_symlink
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
      shared_examples "versioned casks" do |tap_version, installed_version, expected_output|
        let(:cask) { described_class.new("basic-cask") }

        context "when version #{installed_version.inspect} is installed and the tap version is #{tap_version}" do
          it {
            allow(cask).to receive_messages(installed_version:,
                                            version:           Cask::DSL::Version.new(tap_version))
            expect(cask).to receive(:outdated_version).and_call_original
            expect(cask.outdated_version).to eq expected_output
          }
        end
      end

      describe "installed version is equal to tap version => not outdated" do
        include_examples "versioned casks", "1.2.3", "1.2.3", nil
      end

      describe "installed version is different than tap version => outdated" do
        include_examples "versioned casks", "1.2.4", "1.2.3", "1.2.3"
        include_examples "versioned casks", "1.2.4", "1.2.4", nil
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

      it "is not outdated when auto-update upgrades are disabled" do
        allow(Homebrew::EnvConfig).to receive(:upgrade_auto_updates_casks?).and_return(false)
        tap_version = "2.61"
        cask = write_auto_updates_cask(cask_file, version: tap_version, artifacts:)
        allow(cask).to receive(:installed_version).and_return("2.57")
        write_info_plist(cask.config.appdir/"MyFancyApp.app", short_version: "2.57", bundle_version: "2057")

        expect(cask.outdated_version).to be_nil
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

      it "is not outdated when the installed short and bundle versions combine to the tap version" do
        tap_version = "2.61-2057"
        cask = write_auto_updates_cask(cask_file, version: tap_version, artifacts:)
        allow(cask).to receive(:installed_version).and_return("2.57-2056")
        write_info_plist(cask.config.appdir/"MyFancyApp.app", short_version: "2.61", bundle_version: "2057")

        expect(cask.outdated_version).to be_nil
      end

      it "is not outdated when the tap version has a suffix absent from the app bundle" do
        tap_version = "3.6.4-28955b81"
        cask = write_auto_updates_cask(cask_file, version: tap_version, artifacts:)
        allow(cask).to receive(:installed_version).and_return("3.6.3-931da4a1")
        write_info_plist(cask.config.appdir/"MyFancyApp.app", short_version: "3.6.4", bundle_version: "3.6.4")

        expect(cask.outdated_version).to be_nil
      end

      it "is not outdated when the combined installed version is higher than the tap version" do
        tap_version = "2.61-2057"
        cask = write_auto_updates_cask(cask_file, version: tap_version, artifacts:)
        allow(cask).to receive(:installed_version).and_return("2.57-2056")
        write_info_plist(cask.config.appdir/"MyFancyApp.app", short_version: "2.61", bundle_version: "2058")

        expect(cask.outdated_version).to be_nil
      end

      it "is outdated when the combined installed version is lower than the tap version" do
        tap_version = "2.61-2057"
        cask = write_auto_updates_cask(cask_file, version: tap_version, artifacts:)
        allow(cask).to receive(:installed_version).and_return("2.57-2056")
        write_info_plist(cask.config.appdir/"MyFancyApp.app", short_version: "2.61", bundle_version: "2056")

        expect(cask.outdated_version).to eq("2.57-2056")
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
      shared_examples ":latest cask" do |greedy, outdated_sha, tap_version, installed_version, expected_output|
        let(:cask) { described_class.new("basic-cask") }

        context "when versions #{installed_version} are installed and the " \
                "tap version is #{tap_version}, #{"not " unless greedy}greedy " \
                "and sha is #{"not " unless outdated_sha}outdated" do
          it {
            allow(cask).to receive_messages(installed_version:,
                                            version:                Cask::DSL::Version.new(tap_version),
                                            outdated_download_sha?: outdated_sha)
            expect(cask).to receive(:outdated_version).and_call_original
            expect(cask.outdated_version(greedy:)).to eq expected_output
          }
        end
      end

      describe ":latest version installed, :latest version in tap" do
        include_examples ":latest cask", false, false, "latest", "latest", nil
        include_examples ":latest cask", true, false, "latest", "latest", nil
        include_examples ":latest cask", true, true, "latest", "latest", "latest"
      end

      describe "numbered version installed, :latest version in tap" do
        include_examples ":latest cask", false, false, "latest", "1.2.3", nil
        include_examples ":latest cask", true, false, "latest", "1.2.3", nil
        include_examples ":latest cask", true, true, "latest", "1.2.3", "1.2.3"
      end

      describe "latest version installed, numbered version in tap" do
        include_examples ":latest cask", false, false, "1.2.3", "latest", "latest"
        include_examples ":latest cask", true, false, "1.2.3", "latest", "latest"
        include_examples ":latest cask", true, true, "1.2.3", "latest", "latest"
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
        allow(Homebrew::EnvConfig).to receive(:no_require_tap_trust?).and_return(true)
        c = Cask::CaskLoader.load("third-party/tap/third-party-cask")
        expect(c.full_name).to eq("third-party/tap/third-party-cask")
      end
    end

    context "when it is from no known tap" do
      it "returns the cask token" do
        path = mktmpdir/"tapless-cask.rb"
        path.write "cask 'tapless-cask'"

        expect(Cask::CaskLoader.load(path).full_name).to eq("tapless-cask")
      end
    end
  end

  describe "#artifacts_list" do
    subject(:cask) { Cask::CaskLoader.load("many-artifacts") }

    before do
      ENV["HOMEBREW_DEVELOPER"] = nil
      Homebrew.raise_deprecation_exceptions = false
    end

    it "returns all artifacts when no options are given" do
      expected_artifacts = [
        { uninstall_preflight: nil },
        { preflight: nil },
        { uninstall: [{
          rmdir: "#{TEST_TMPDIR}/empty_directory_path",
          trash: ["#{TEST_TMPDIR}/foo", "#{TEST_TMPDIR}/bar"],
        }] },
        { pkg: ["ManyArtifacts/ManyArtifacts.pkg"] },
        { app: ["ManyArtifacts/ManyArtifacts.app"], target: "#{TEST_TMPDIR}/cask-appdir/ManyArtifacts.app" },
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
    before do
      ENV["HOMEBREW_DEVELOPER"] = nil
      Homebrew.raise_deprecation_exceptions = false
    end

    matcher :have_uninstall_flight_blocks do
      T.bind(self, T.class_of(RSpec::Matchers::DSL::Matcher))
      match do |actual|
        actual.uninstall_flight_blocks? == true
      end
    end

    it "returns true when there are uninstall flight blocks" do
      cask = Cask::CaskLoader.load("many-artifacts")
      expect(cask).to have_uninstall_flight_blocks
    end

    it "returns false when there are no flight blocks" do
      cask = Cask::CaskLoader.load("local-caffeine")
      expect(cask).not_to have_uninstall_flight_blocks
    end
  end

  describe "#supports_linux?" do
    it "uses explicit OS dependencies and defaults to Linux support" do
      expect(Cask::CaskLoader.load("with-depends-on-macos-bare").supports_linux?).to be false
      expect(Cask::CaskLoader.load("with-depends-on-maximum-macos").supports_linux?).to be false
      expect(Cask::CaskLoader.load("with-depends-on-macos-in-on-macos").supports_linux?).to be true
      expect(Cask::CaskLoader.load("with-depends-on-linux-bare").supports_linux?).to be true

      expect(Cask::CaskLoader.load("with-non-executable-binary").supports_linux?).to be true
      expect(Cask::CaskLoader.load("basic-cask").supports_linux?).to be true
      expect(Cask::CaskLoader.load("with-installer-manual").supports_linux?).to be true
    end
  end

  describe "#supports_macos?" do
    it "returns false for casks with bare depends_on :linux" do
      expect(Cask::CaskLoader.load("with-depends-on-linux-bare").supports_macos?).to be false
    end
  end

  describe "#outdated_info" do
    it "includes pinned cask details" do
      cask = Cask::CaskLoader.load("local-caffeine")
      allow(cask).to receive_messages(outdated_version: "1.2.2", pinned?: true, pinned_version: "1.2.2")

      expect(cask.outdated_info(false, true, false, false, false))
        .to eq("local-caffeine (1.2.2) != 1.2.3 [pinned at 1.2.2]")
      expect(cask.outdated_info(false, false, true, false, false)).to include(
        pinned:         true,
        pinned_version: "1.2.2",
      )
    end
  end

  describe "#to_h" do
    let(:expected_json) do
      (TEST_FIXTURE_DIR/"cask/everything.json").read.strip.gsub("$APPDIR", "#{TEST_TMPDIR}/cask-appdir")
    end

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
        hash = Cask::CaskLoader::FromAPILoader.new(
          "everything", from_json: JSON.parse(expected_json)
        ).load(config: nil).to_h

        expect(hash).to be_a(Hash)
        expect(JSON.pretty_generate(hash)).to eq(expected_json)
      end
    end
  end

  describe "#refresh_for_tag" do
    let(:cask) { Cask::CaskLoader.load("on-linux-asymmetric") }

    it "yields with the cask refreshed for a supported tag" do
      tag = Utils::Bottles::Tag.new(system: :sonoma, arch: :intel)
      expect(cask.refresh_for_tag(tag) { cask.url.to_s }).to include("caffeine-intel-darwin")
    end

    it "yields for a Linux architecture whose checksum is missing" do
      tag = Utils::Bottles::Tag.new(system: :linux, arch: :arm)
      expect(cask.refresh_for_tag(tag) { cask.url.to_s }).to include("caffeine-arm-linux")
    end

    it "returns nil for a tag the cask cannot be refreshed for" do
      invalid_on_linux_cask = described_class.new("on-linux-invalid") do
        on_macos do
          version "1.2.3"
        end
        sha256 :no_check
        url "https://brew.sh/foo-#{version&.major_minor || raise(Cask::CaskInvalidError.new(cask, "version is only set on macOS"))}.zip"
      end

      tag = Utils::Bottles::Tag.new(system: :linux, arch: :arm)
      expect(invalid_on_linux_cask.refresh_for_tag(tag) { invalid_on_linux_cask.url }).to be_nil
    end
  end

  describe "#to_hash_with_variations" do
    let!(:original_macos_version) { MacOS.full_version.to_s }
    let(:expected_versions_variations) do
      <<~JSON
        {
          "golden_gate": {
            "url": "file://#{TEST_FIXTURE_DIR}/cask/caffeine/darwin/1.2.3/intel.zip"
          },
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
          "x86_64_linux": {
            "url": "file://#{TEST_FIXTURE_DIR}/cask/caffeine/darwin//intel.zip",
            "version": null,
            "sha256": null
          },
          "arm64_linux": {
            "url": "file://#{TEST_FIXTURE_DIR}/cask/caffeine/darwin-arm64//arm.zip",
            "version": null,
            "sha256": null
          }
        }
      JSON
    end
    let(:expected_sha256_variations) do
      <<~JSON
        {
          "golden_gate": {
            "url": "file://#{TEST_FIXTURE_DIR}/cask/caffeine-intel.zip",
            "sha256": "8c62a2b791cf5f0da6066a0a4b6e85f62949cd60975da062df44adf887f4370b"
          },
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
          "x86_64_linux": {
            "url": "file://#{TEST_FIXTURE_DIR}/cask/caffeine-intel.zip",
            "sha256": null
          },
          "arm64_linux": {
            "sha256": null
          }
        }
      JSON
    end
    let(:expected_sha256_variations_os) do
      <<~JSON
        {
          "golden_gate": {
            "url": "file://#{TEST_FIXTURE_DIR}/cask/caffeine-intel-darwin.zip",
            "sha256": "8c62a2b791cf5f0da6066a0a4b6e85f62949cd60975da062df44adf887f4370b"
          },
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

    it "returns language variations with a deterministic default" do
      hash = JSON.parse(JSON.generate(Cask::CaskLoader.load("with-languages").to_hash_with_variations))

      expect(hash.slice("url", "sha256", "language_variations")).to eq({
        "url"                 => "file://#{TEST_FIXTURE_DIR}/cask/caffeine.zip",
        "sha256"              => "67cdb8a02803ef37fdbf7e0be205863172e41a561ca446cd84f0d7ab35a99d94",
        "language_variations" => [
          {
            "languages" => ["zh"],
            "default"   => false,
            "value"     => "zh-CN",
            "url"       => "file://#{TEST_FIXTURE_DIR}/cask/container.tar.gz",
            "sha256"    => "fab685fabf73d5a9382581ce8698fce9408f5feaa49fa10d9bc6c510493300f5",
            "artifacts" => [{
              "app"    => ["Container.app"],
              "target" => "#{TEST_TMPDIR}/cask-appdir/Container.app",
            }],
          },
          { "languages" => ["en-US"], "default" => true, "value" => "en-US" },
        ],
      })
    end

    it "preserves the cask configuration while generating language variations" do
      appdir = Pathname(TEST_TMPDIR)/"configured-appdir"
      config = Cask::Config.from_json({ default: { appdir:, languages: ["en-US"] } }.to_json)
      hash = Cask::CaskLoader.load("with-languages", config:).to_hash_with_variations

      expect([
        hash.dig("artifacts", 0, :target),
        hash.dig("language_variations", 0, "artifacts", 0, :target),
      ]).to eq([appdir/"Caffeine.app", appdir/"Container.app"].map(&:to_s))
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

    it "emits variations without checksums for Linux architectures a cask omits" do
      c = Cask::CaskLoader.load("on-linux-asymmetric")
      h = JSON.parse(JSON.generate(c.to_hash_with_variations))

      expect(h["variations"]["arm64_linux"]).to include(
        "depends_on" => { "arch" => [{ "type" => "intel", "bits" => 64 }] },
        "sha256"     => nil,
      )
    end

    it "emits Linux variations for a cask with Linux checksums but no `os` stanza" do
      c = Cask::CaskLoader.load("sha256-linux")
      h = c.to_hash_with_variations

      expect(h["variations"]).to include(:x86_64_linux, :arm64_linux)
    end

    it "emits Linux variations with checksums for a Linux-only cask" do
      c = Cask::CaskLoader.load("sha256-linux-only")
      h = c.to_hash_with_variations

      expect(h["variations"].slice(:x86_64_linux, :arm64_linux).transform_values { |v| v["sha256"].to_s }).to eq(
        x86_64_linux: "244d413861cecb3707cfbcc5c4346d5367daa827da5ea08fb3f3bc2b6276d239",
        arm64_linux:  "9a1c0967baa46828930ccbbc88668d1b0db07e6edf778800ed4da073c00054f8",
      )
    end

    it "emits Linux variations for a cask with `on_linux` content but no `os` stanza" do
      c = Cask::CaskLoader.load("on-linux-blocks")
      h = JSON.parse(JSON.generate(c.to_hash_with_variations))

      app_image_artifacts = [{
        "app_image" => ["Caffeine.AppImage"],
        "target"    => "#{TEST_TMPDIR}/cask-appimagedir/Caffeine.AppImage",
      }]
      expect(h["variations"].slice("x86_64_linux", "arm64_linux").transform_values do |v|
        v.slice("sha256", "artifacts")
      end).to eq(
        "x86_64_linux" => {
          "sha256"    => "244d413861cecb3707cfbcc5c4346d5367daa827da5ea08fb3f3bc2b6276d239",
          "artifacts" => app_image_artifacts,
        },
        "arm64_linux"  => {
          "sha256"    => "9a1c0967baa46828930ccbbc88668d1b0db07e6edf778800ed4da073c00054f8",
          "artifacts" => app_image_artifacts,
        },
      )
    end

    context "when recording supported platforms" do
      let(:platform_tags) do
        [
          Utils::Bottles::Tag.new(system: :sonoma, arch: :intel),
          Utils::Bottles::Tag.new(system: :sonoma, arch: :arm),
          Utils::Bottles::Tag.new(system: :monterey, arch: :intel),
          Utils::Bottles::Tag.new(system: :monterey, arch: :arm),
          Utils::Bottles::Tag.new(system: :big_sur, arch: :intel),
          Utils::Bottles::Tag.new(system: :big_sur, arch: :arm),
          Utils::Bottles::Tag.new(system: :linux, arch: :intel),
          Utils::Bottles::Tag.new(system: :linux, arch: :arm),
        ]
      end
      let(:macos_platforms) { [:sonoma, :arm64_sonoma, :monterey, :arm64_monterey, :big_sur, :arm64_big_sur] }

      before do
        stub_const("OnSystem::VALID_OS_ARCH_TAGS", platform_tags)
      end

      it "records platforms allowed by scoped macOS requirements" do
        c = Cask::CaskLoader.load("with-depends-on-macos-in-on-macos")

        expect(c.to_hash_with_variations["supported_platforms"]).to eq(
          [:sonoma, :arm64_sonoma, :monterey, :arm64_monterey, :x86_64_linux, :arm64_linux],
        )
      end

      it "excludes platforms without complete download data" do
        c = Cask::CaskLoader.load("multiple-versions")

        expect(c.to_hash_with_variations["supported_platforms"]).to eq(macos_platforms)
      end

      it "excludes platforms rejected by architecture requirements" do
        c = described_class.new("architecture-restricted") do
          version :latest
          arch arm: "arm64", intel: "x86_64"
          sha256 :no_check
          url "https://brew.sh/#{arch}.zip"
          on_linux do
            depends_on arch: :x86_64
          end
          binary "foo"
        end

        expect(c.to_hash_with_variations["supported_platforms"]).to eq(
          [*macos_platforms, :x86_64_linux],
        )
      end

      it "does not infer macOS support from artifact types" do
        c = described_class.new("macos-artifact") do
          version :latest
          arch arm: "arm64", intel: "x86_64"
          sha256 :no_check
          url "https://brew.sh/#{arch}.zip"
          app "Foo.app"
        end

        expect(c.to_hash_with_variations["supported_platforms"]).to eq(platform_tags.map(&:to_sym))
      end

      it "does not infer macOS support from manual installers" do
        c = described_class.new("manual-installer") do
          version :latest
          arch arm: "arm64", intel: "x86_64"
          sha256 :no_check
          url "https://brew.sh/#{arch}.zip"
          installer manual: "Foo.app"
        end

        expect(c.to_hash_with_variations["supported_platforms"]).to eq(platform_tags.map(&:to_sym))
      end

      it "does not infer Linux support from artifact types" do
        c = described_class.new("linux-artifact") do
          version :latest
          arch arm: "arm64", intel: "x86_64"
          sha256 :no_check
          url "https://brew.sh/#{arch}.zip"
          app_image "Foo.AppImage"
        end

        expect(c.to_hash_with_variations["supported_platforms"]).to eq(platform_tags.map(&:to_sym))
      end

      it "excludes Linux for casks with a bare macOS dependency" do
        c = described_class.new("macos-only") do
          version :latest
          sha256 :no_check
          url "https://brew.sh/foo.zip"
          depends_on :macos
          app "Foo.app"
        end

        expect(c.to_hash_with_variations["supported_platforms"]).to eq(macos_platforms)
      end

      it "excludes macOS for casks with a bare Linux dependency" do
        c = described_class.new("linux-only") do
          version :latest
          sha256 :no_check
          url "https://brew.sh/foo.zip"
          depends_on :linux
          app_image "Foo.AppImage"
        end

        expect(c.to_hash_with_variations["supported_platforms"]).to eq([:x86_64_linux, :arm64_linux])
      end

      it "includes stage-only casks" do
        c = described_class.new("stage-only") do
          version :latest
          arch arm: "arm64", intel: "x86_64"
          sha256 :no_check
          url "https://brew.sh/#{arch}.zip"
          stage_only true
        end

        expect(c.to_hash_with_variations["supported_platforms"]).to eq(platform_tags.map(&:to_sym))
      end

      it "records no supported platforms for a cask without an installable artifact" do
        c = described_class.new("zap-only") do
          version :latest
          arch arm: "arm64", intel: "x86_64"
          sha256 :no_check
          url "https://brew.sh/#{arch}.zip"
          zap trash: "~/Library/Caches/brew-test"
        end

        expect(c.to_hash_with_variations["supported_platforms"]).to eq([])
      end

      it "records every platform when a cask has no platform variations" do
        c = described_class.new("no-platform-variations") do
          version :latest
          sha256 :no_check
          url "https://brew.sh/foo.zip"
          binary "foo"
        end

        expect(c.to_hash_with_variations["supported_platforms"]).to eq(platform_tags.map(&:to_sym))
      end

      it "records top-level platform requirements without variations" do
        c = described_class.new("top-level-platform-requirements") do
          version :latest
          sha256 :no_check
          url "https://brew.sh/foo.zip"
          depends_on macos: :monterey
          depends_on arch: :x86_64
          binary "foo"
        end

        expect(c.to_hash_with_variations["supported_platforms"]).to eq([:sonoma, :monterey])
      end

      it "serializes architecture-varying and universal casks with the same macOS requirement" do
        tags = OnSystem::ALL_OS_ARCH_COMBINATIONS.map do |os, arch|
          Utils::Bottles::Tag.new(system: os, arch:)
        end
        stub_const("OnSystem::VALID_OS_ARCH_TAGS", tags)

        architecture_varying = described_class.new("architecture-varying") do
          arch arm: "ARM64", intel: "64"
          version "1.2.3"
          sha256 arm:   "a" * 64,
                 intel: "b" * 64
          url "https://brew.sh/#{arch}.zip"
          depends_on macos: :big_sur
          app "Foo.app"
        end
        universal = described_class.new("universal") do
          version :latest
          sha256 :no_check
          url "https://brew.sh/foo.zip"
          depends_on macos: :big_sur
          app "Foo.app"
        end

        architecture_varying.to_hash_with_variations
        supported_platforms = Timeout.timeout(5) do
          universal.to_hash_with_variations["supported_platforms"]
        end

        expected_platforms = tags.filter_map { |tag| tag.to_sym if tag.macos? }
        expect(supported_platforms).to eq(expected_platforms)
      end

      it "isolates macOS requirement comparisons between casks" do
        supported_platforms = [:monterey, :sonoma].map do |minimum_macos|
          c = described_class.new("requires-#{minimum_macos}") do
            version :latest
            sha256 :no_check
            url "https://brew.sh/foo.zip"
            depends_on macos: minimum_macos
            binary "foo"
          end

          c.to_hash_with_variations["supported_platforms"]
        end

        expect(supported_platforms).to eq(
          [
            [:sonoma, :arm64_sonoma, :monterey, :arm64_monterey],
            [:sonoma, :arm64_sonoma],
          ],
        )
      end
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
      let(:expected_json) do
        (TEST_FIXTURE_DIR/"cask/everything-with-variations.json").read.strip
          .gsub("$APPDIR", "#{TEST_TMPDIR}/cask-appdir")
      end

      it "returns expected hash with variations" do
        cask = Cask::CaskLoader::FromAPILoader.new("everything-with-variations", from_json: JSON.parse(expected_json))
                                              .load(config: nil)

        hash = cask.to_hash_with_variations

        expect(cask.loaded_from_api?).to be true
        expect(cask.loaded_from_internal_api?).to be false
        expect(hash).to be_a(Hash)
        expect(JSON.pretty_generate(hash)).to eq(expected_json)
      end
    end

    it "does not include macOS dependency in Linux variations" do
      c = Cask::CaskLoader.load("sha256-os")
      h = c.to_hash_with_variations

      [:x86_64_linux, :arm64_linux].each do |tag|
        merged = Homebrew::API.merge_variations(h.deep_dup, bottle_tag: Utils::Bottles::Tag.from_symbol(tag))
        expect(merged["depends_on"]).not_to include("macos") if merged["depends_on"].present?
      end
    end
  end
end
