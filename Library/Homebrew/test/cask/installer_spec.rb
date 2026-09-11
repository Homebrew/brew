# typed: false
# frozen_string_literal: true

require "cask/installer"
require "install"

RSpec.describe Cask::Installer, :cask do
  def stub_dmg_extraction
    allow(UnpackStrategy::Dmg).to receive(:can_extract?).and_return(true)
    allow_any_instance_of(UnpackStrategy::Dmg).to receive(:extract_nestedly) do |_strategy, to:, **|
      to.mkpath
      yield to
    end
  end

  describe "#extract_primary_container" do
    it "respects the installer's download integrity setting" do
      cask = Cask::CaskLoader.load(cask_path("local-caffeine"))
      installer = described_class.new(cask, verify_download_integrity: false)
      download = instance_double(Cask::Download)
      downloaded_path = Pathname("/path/to/downloaded/cask")

      allow(installer).to receive(:downloader).and_return(download)
      expect(download).to receive(:fetch)
        .with(quiet: true, verify_download_integrity: false, timeout: nil)
        .and_return(downloaded_path)
      expect(download).to receive(:extract_primary_container).with(to: cask.staged_path, verbose: false)

      installer.extract_primary_container

      expect(cask.download).to eq(downloaded_path)
    end
  end

  describe "#save_caskfile" do
    it "stores casks loaded from Ruby source as JSON metadata" do
      cask = Cask::CaskLoader.load(cask_path("local-caffeine"))

      described_class.new(cask).save_caskfile
      Cask::Tab.create(cask).write

      expect([
        cask.installed_caskfile&.basename&.to_s,
        Cask::CaskLoader.load_from_installed_caskfile(cask.installed_caskfile).token,
        JSON.parse(cask.installed_caskfile.read).keys.sort,
      ]).to eq(["local-caffeine.json", "local-caffeine", []])
    end

    it "stores URL only_path metadata needed to reconstruct artifact sources" do
      cask = Cask::Cask.new("only-path", source: "{}") do
        version "1.0"
        sha256 :no_check
        url "https://example.com/only-path.git", only_path: "nested"
        app "Only Path.app"
      end

      described_class.new(cask).save_caskfile
      Cask::Tab.create(cask).write

      loaded_cask = Cask::CaskLoader.load_from_installed_caskfile(cask.installed_caskfile)
      expect([
        JSON.parse(cask.installed_caskfile.read).keys.sort,
        loaded_cask.artifacts.grep(Cask::Artifact::App).first.source,
      ]).to eq([
        %w[url_specs],
        Cask::Caskroom.path/"only-path/1.0/nested/Only Path.app",
      ])
    end

    it "strips legacy install flight blocks and records empty artifacts in JSON metadata" do
      ENV["HOMEBREW_DEVELOPER"] = nil
      Homebrew.raise_deprecation_exceptions = false
      cask = Cask::CaskLoader.load(cask_path("many-artifacts"))
      cask.artifacts.keep_if do |artifact|
        artifact.respond_to?(:directives) &&
          artifact.directives.keys.intersect?([:preflight, :postflight])
      end

      described_class.new(cask).save_caskfile

      expect(JSON.parse(cask.installed_caskfile.read)).to eq({ "artifacts" => [] })
    end

    it "stores intentional empty artifacts in JSON metadata" do
      cask = Cask::CaskLoader.load(cask_path("stage-only"))

      described_class.new(cask).save_caskfile

      expect(JSON.parse(cask.installed_caskfile.read)).to eq({ "artifacts" => [] })
    end

    it "stores legacy uninstall flight block casks as Ruby metadata" do
      ENV["HOMEBREW_DEVELOPER"] = nil
      Homebrew.raise_deprecation_exceptions = false
      cask = Cask::CaskLoader.load(cask_path("many-artifacts"))

      described_class.new(cask).save_caskfile

      expect([
        cask.installed_caskfile&.basename&.to_s,
        Cask::CaskLoader.load_from_installed_caskfile(cask.installed_caskfile).uninstall_flight_blocks?,
      ]).to eq(["many-artifacts.rb", true])
    end

    it "stores casks loaded from the internal API as JSON metadata" do
      cask = Cask::Cask.new(
        "api-cask",
        source:                   "{}",
        loaded_from_api:          true,
        loaded_from_internal_api: true,
        api_source:               {
          "homepage"      => "https://example.com/api-cask",
          "names"         => ["API Cask"],
          "raw_artifacts" => [[":app", ["API Cask.app"]]],
          "sha256"        => "no_check",
          "url_args"      => ["https://example.com/api-cask.zip"],
          "version"       => "1.0",
        },
      ) do
        version "1.0"
        sha256 :no_check
        url "https://example.com/api-cask.zip"
        name "API Cask"
        homepage "https://example.com/api-cask"
        app "API Cask.app"
      end

      described_class.new(cask).save_caskfile
      Cask::Tab.create(cask).write

      loaded_cask = Cask::CaskLoader.load_from_installed_caskfile(cask.installed_caskfile)
      expect([
        cask.installed_caskfile&.basename&.to_s,
        loaded_cask.token,
        loaded_cask.loaded_from_internal_api?,
        JSON.parse(cask.installed_caskfile.read).keys.sort,
      ]).to eq(["api-cask.json", "api-cask", false, []])
    end
  end

  describe "#prelude", :needs_macos do
    it "resolves the system languages before any other cask work" do
      caffeine = Cask::CaskLoader.load(cask_path("local-caffeine"))
      installer = described_class.new(caffeine)

      call_order = []
      allow(MacOS).to receive(:languages) do
        call_order << :languages
        ["en-US"]
      end
      allow(installer).to receive(:check_requirements) { call_order << :requirements }

      installer.prelude

      expect(call_order.first).to eq(:languages)
      expect(call_order).to include(:requirements)
    end
  end

  describe "install" do
    it "resolves the system languages before installing artifacts", :needs_macos do
      caffeine = Cask::CaskLoader.load(cask_path("local-caffeine"))

      call_order = []
      allow(MacOS).to receive(:languages) do
        call_order << :languages
        ["en-US"]
      end
      allow_any_instance_of(Cask::Artifact::App).to receive(:install_phase) { call_order << :install_phase }

      described_class.new(caffeine).install

      expect(call_order.first).to eq(:languages)
      expect(call_order).to include(:install_phase)
    end

    it "downloads and installs a nice fresh Cask" do
      caffeine = Cask::CaskLoader.load(cask_path("local-caffeine"))

      described_class.new(caffeine).install

      expect(Cask::Caskroom.path.join("local-caffeine", caffeine.version)).to be_a_directory
      expect(Pathname(caffeine.config.appdir).join("Caffeine.app")).to be_a_directory
    end

    it "works with HFS+ dmg-based Casks" do
      asset = Cask::CaskLoader.load(cask_path("container-dmg"))
      stub_dmg_extraction { |path| FileUtils.touch path/"container" }

      described_class.new(asset).install

      expect(Cask::Caskroom.path.join("container-dmg", asset.version)).to be_a_directory
      expect(Pathname(asset.config.appdir).join("container")).to be_a_file
    end

    it "works with tar-gz-based Casks" do
      asset = Cask::CaskLoader.load(cask_path("container-tar-gz"))

      described_class.new(asset).install

      expect(Cask::Caskroom.path.join("container-tar-gz", asset.version)).to be_a_directory
      expect(Pathname(asset.config.appdir).join("container")).to be_a_file
    end

    it "works with xar-based Casks" do
      ENV["HOMEBREW_DEVELOPER"] = nil
      Homebrew.raise_deprecation_exceptions = false
      asset = Cask::CaskLoader.load(cask_path("container-xar"))

      described_class.new(asset).install

      expect(Cask::Caskroom.path.join("container-xar", asset.version)).to be_a_directory
      expect(Pathname(asset.config.appdir).join("container")).to be_a_file
    end

    it "works with pure bzip2-based Casks" do
      asset = Cask::CaskLoader.load(cask_path("container-bzip2"))
      # The bzip2 container depends on the `bzip2` formula via its unpack
      # strategy. Exercise dependency resolution without pouring a real
      # bottle (and flaking on its GitHub Packages manifest).
      allow_any_instance_of(Formula).to receive(:any_version_installed?).and_return(false)
      allow(Homebrew::Install).to receive(:fetch_formulae) { |installers| installers }
      allow_any_instance_of(FormulaInstaller).to receive(:install)
      allow_any_instance_of(FormulaInstaller).to receive(:finish)

      described_class.new(asset).install

      expect(Cask::Caskroom.path.join("container-bzip2", asset.version)).to be_a_directory
      expect(Pathname(asset.config.appdir).join("container")).to be_a_file
    end

    it "works with pure gzip-based Casks" do
      asset = Cask::CaskLoader.load(cask_path("container-gzip"))

      described_class.new(asset).install

      expect(Cask::Caskroom.path.join("container-gzip", asset.version)).to be_a_directory
      expect(Pathname(asset.config.appdir).join("container")).to be_a_file
    end

    it "blows up on a bad checksum" do
      bad_checksum = Cask::CaskLoader.load(cask_path("bad-checksum"))
      expect do
        described_class.new(bad_checksum).install
      end.to raise_error(ChecksumMismatchError)
    end

    it "blows up on a missing checksum" do
      missing_checksum = Cask::CaskLoader.load(cask_path("missing-checksum"))
      expect do
        described_class.new(missing_checksum).install
      end.to output(/Cannot verify integrity/).to_stderr
    end

    it "installs fine if sha256 :no_check is used" do
      no_checksum = Cask::CaskLoader.load(cask_path("no-checksum"))

      described_class.new(no_checksum).install

      expect(no_checksum).to be_installed
    end

    it "fails to install if sha256 :no_check is used with --require-sha" do
      no_checksum = Cask::CaskLoader.load(cask_path("no-checksum"))
      expect do
        described_class.new(no_checksum, require_sha: true).install
      end.to raise_error(/--require-sha/)
    end

    it "names the cask when Linux is required" do
      linux_cask = Cask::CaskLoader.load("with-depends-on-linux-bare")
      expect do
        described_class.new(linux_cask).check_stanza_os_requirements
      end.to raise_error(Cask::CaskError, "with-depends-on-linux-bare: This cask requires Linux.")
    end

    it "names the cask when the macOS requirement is not satisfied" do
      macos_cask = Cask::CaskLoader.load("with-depends-on-macos-failure")
      allow(macos_cask.depends_on.maximum_macos).to receive(:satisfied?).and_return(false)
      expect do
        described_class.new(macos_cask).check_macos_requirements
      end.to raise_error(
        Cask::CaskError,
        "with-depends-on-macos-failure: This cask does not run on macOS versions newer than Monterey.",
      )
    end

    it "names the cask when the architecture is not supported" do
      arch_cask = Cask::CaskLoader.load("with-depends-on-arch")
      allow(Hardware::CPU).to receive(:type).and_return(:ppc)
      expect do
        described_class.new(arch_cask).check_arch_requirements
      end.to raise_error(Cask::CaskError, /\Awith-depends-on-arch: This cask depends on hardware architecture/)
    end

    it "names the cask when it has nothing to install on this system" do
      no_artifacts_cask = Cask::Cask.new("with-no-artifacts", loaded_from_api: true) do
        version "1.0"
        sha256 :no_check
        url "https://brew.sh/x.zip"
      end
      expect do
        described_class.new(no_artifacts_cask).check_supported_system
      end.to raise_error(Cask::CaskError, "with-no-artifacts: This cask is not available on macOS.")
    end

    it "treats uninstall-only artifacts as nothing to install" do
      zap_only_cask = Cask::Cask.new("with-zap-only", loaded_from_api: true) do
        version "1.0"
        sha256 :no_check
        url "https://brew.sh/x.zip"
        zap trash: "~/Library/Caches/brew-test"
      end
      expect do
        described_class.new(zap_only_cask).check_supported_system
      end.to raise_error(Cask::CaskError, "with-zap-only: This cask is not available on macOS.")
    end

    it "does not treat stage_only casks as having nothing to install" do
      stage_only_cask = Cask::Cask.new("with-stage-only", loaded_from_api: true) do
        version "1.0"
        sha256 :no_check
        url "https://brew.sh/x.zip"
        stage_only true
      end
      expect do
        described_class.new(stage_only_cask).check_supported_system
      end.not_to raise_error
    end

    it "installs fine if sha256 :no_check is used with --require-sha and --force" do
      no_checksum = Cask::CaskLoader.load(cask_path("no-checksum"))

      described_class.new(no_checksum, require_sha: true, force: true).install

      expect(no_checksum).to be_installed
    end

    it "records caveats without printing them inline" do
      with_caveats = Cask::CaskLoader.load(cask_path("with-caveats"))

      expect(Homebrew.messages).to receive(:record_caveats)
        .with(with_caveats.token, with_caveats.caveats)
      expect(described_class).not_to receive(:caveats)

      expect do
        described_class.new(with_caveats).install
      end.not_to output(/Here are some things you might want to know/).to_stdout

      expect(with_caveats).to be_installed
    end

    it "prints installer :manual instructions when present" do
      with_installer_manual = Cask::CaskLoader.load(cask_path("with-installer-manual"))

      expect do
        described_class.new(with_installer_manual).install
      end.to output(
        <<~EOS,
          ==> Downloading file://#{HOMEBREW_LIBRARY_PATH}/test/support/fixtures/cask/caffeine.zip
          ==> Installing Cask with-installer-manual
          Cask with-installer-manual only provides a manual installer. To run it and complete the installation:
            open #{with_installer_manual.staged_path.join("Caffeine.app")}
          🍺  with-installer-manual was successfully installed!
        EOS
      ).to_stdout

      expect(with_installer_manual).to be_installed
    end

    it "does not extract __MACOSX directories from zips" do
      with_macosx_dir = Cask::CaskLoader.load(cask_path("with-macosx-dir"))

      described_class.new(with_macosx_dir).install

      expect(with_macosx_dir.staged_path.join("__MACOSX")).not_to be_a_directory
    end

    it "allows already-installed Casks which auto-update to be installed if force is provided" do
      with_auto_updates = Cask::CaskLoader.load(cask_path("auto-updates"))

      expect(with_auto_updates).not_to be_installed

      described_class.new(with_auto_updates).install

      expect do
        described_class.new(with_auto_updates, force: true).install
      end.not_to raise_error
    end

    it "allows already-installed Casks to be installed if force is provided" do
      transmission = Cask::CaskLoader.load(cask_path("local-transmission-zip"))

      expect(transmission).not_to be_installed

      described_class.new(transmission).install

      expect do
        described_class.new(transmission, force: true).install
      end.not_to raise_error
    end

    it "installs a cask from a dmg file" do
      transmission = Cask::CaskLoader.load(cask_path("local-transmission"))
      stub_dmg_extraction { |path| (path/"Transmission.app").mkpath }

      expect(transmission).not_to be_installed

      described_class.new(transmission).install

      expect(transmission).to be_installed
    end

    it "works naked-pkg-based Casks" do
      naked_pkg = Cask::CaskLoader.load(cask_path("container-pkg"))

      described_class.new(naked_pkg).install

      expect(Cask::Caskroom.path.join("container-pkg", naked_pkg.version, "container.pkg")).to be_a_file
    end

    it "works properly with an overridden container :type" do
      naked_executable = Cask::CaskLoader.load(cask_path("naked-executable"))

      described_class.new(naked_executable).install

      expect(Cask::Caskroom.path.join("naked-executable", naked_executable.version, "naked_executable")).to be_a_file
    end

    it "works fine with a nested container" do
      nested_app = Cask::CaskLoader.load(cask_path("nested-app"))

      described_class.new(nested_app).install

      expect(Pathname(nested_app.config.appdir).join("MyNestedApp.app")).to be_a_directory
    end

    it "generates and finds a timestamped metadata directory for an installed Cask" do
      caffeine = Cask::CaskLoader.load(cask_path("local-caffeine"))

      described_class.new(caffeine).install

      m_path = caffeine.metadata_timestamped_path(timestamp: :now, create: true)
      expect(caffeine.metadata_timestamped_path(timestamp: :latest)).to eq(m_path)
    end

    it "generates and finds a metadata subdirectory for an installed Cask" do
      caffeine = Cask::CaskLoader.load(cask_path("local-caffeine"))

      described_class.new(caffeine).install

      subdir_name = "Casks"
      m_subdir = caffeine.metadata_subdir(subdir_name, timestamp: :now, create: true)
      expect(caffeine.metadata_subdir(subdir_name, timestamp: :latest)).to eq(m_subdir)
    end

    it "don't print cask installed message with --quiet option" do
      caffeine = Cask::CaskLoader.load(cask_path("local-caffeine"))
      expect do
        described_class.new(caffeine, quiet: true).install
      end.to output(nil).to_stdout
    end

    it "does NOT generate LATEST_DOWNLOAD_SHA256 file for installed Cask without version :latest" do
      caffeine = Cask::CaskLoader.load(cask_path("local-caffeine"))

      described_class.new(caffeine).install

      expect(caffeine.download_sha_path).not_to be_a_file
    end

    it "generates and finds LATEST_DOWNLOAD_SHA256 file for installed Cask with version :latest" do
      latest_cask = Cask::CaskLoader.load(cask_path("version-latest"))

      described_class.new(latest_cask).install

      expect(latest_cask.download_sha_path).to be_a_file
    end

    context "when loaded from the api with unsupported requirements" do
      let(:cask) { Cask::CaskLoader.load(cask_path("with-depends-on-macos-symbol")) }
      let(:download_queue) { instance_double(Homebrew::DownloadQueue, enqueue: nil) }
      let(:macos_requirement) { cask.depends_on.macos }

      before do
        allow(macos_requirement).to receive(:satisfied?).and_return(false)
        allow(macos_requirement).to receive(:message).with(type: :cask).and_return("macOS is required")
        allow(cask).to receive(:loaded_from_api?).and_return(true)
      end

      it "checks requirements before enqueueing downloads" do
        expect do
          described_class.new(cask, download_queue:).enqueue_downloads
        end.to raise_error(Cask::CaskError, "with-depends-on-macos-symbol: macOS is required")
      end

      it "checks requirements before downloading during fetch" do
        expect do
          described_class.new(cask).fetch
        end.to raise_error(Cask::CaskError, "with-depends-on-macos-symbol: macOS is required")
      end
    end

    it "zap method reinstall cask" do
      caffeine = Cask::CaskLoader.load(cask_path("local-caffeine"))
      described_class.new(caffeine).install

      expect(caffeine).to be_installed

      described_class.new(caffeine).zap

      expect(caffeine).not_to be_installed
      expect(Pathname(caffeine.config.appdir).join("Caffeine.app")).not_to be_a_symlink
    end
  end

  describe "#backup" do
    it "does not raise when the staged version directory is already missing" do
      caffeine = Cask::CaskLoader.load(cask_path("local-caffeine"))
      installer = described_class.new(caffeine)
      installer.install

      FileUtils.rm_rf(caffeine.staged_path)
      FileUtils.rm_rf(caffeine.metadata_versioned_path)

      expect { installer.backup }.not_to raise_error
      expect(installer.backup_path).not_to exist
      expect(installer.backup_metadata_path).not_to exist
    end
  end

  describe "uninstall" do
    it "fully uninstalls a Cask" do
      caffeine = Cask::CaskLoader.load(cask_path("local-caffeine"))
      installer = described_class.new(caffeine)

      installer.install
      installer.uninstall

      expect(Cask::Caskroom.path.join("local-caffeine", caffeine.version, "Caffeine.app")).not_to be_a_directory
      expect(Cask::Caskroom.path.join("local-caffeine", caffeine.version)).not_to be_a_directory
      expect(Cask::Caskroom.path.join("local-caffeine")).not_to be_a_directory
    end

    it "removes Caskroom symlinks the uninstall broke, whatever name they carry" do
      caffeine = Cask::CaskLoader.load(cask_path("local-caffeine"))
      alias_link = Cask::Caskroom.path.join("local-caffeine-renamed")
      unrelated_link = Cask::Caskroom.path.join("alias-of-another-cask")
      installer = described_class.new(caffeine)
      installer.install
      FileUtils.ln_s "local-caffeine", alias_link
      FileUtils.ln_s "another-cask", unrelated_link

      installer.uninstall

      expect([alias_link.symlink?, unrelated_link.symlink?, Cask::Caskroom.path.join("local-caffeine").exist?])
        .to eq([false, true, false])
    end

    it "uninstalls all versions if force is set" do
      caffeine = Cask::CaskLoader.load(cask_path("local-caffeine"))
      mutated_version = "#{caffeine.version}.1"

      described_class.new(caffeine).install

      expect(Cask::Caskroom.path.join("local-caffeine", caffeine.version)).to be_a_directory
      expect(Cask::Caskroom.path.join("local-caffeine", mutated_version)).not_to be_a_directory
      FileUtils.mv(Cask::Caskroom.path.join("local-caffeine", caffeine.version),
                   Cask::Caskroom.path.join("local-caffeine", mutated_version))
      expect(Cask::Caskroom.path.join("local-caffeine", caffeine.version)).not_to be_a_directory
      expect(Cask::Caskroom.path.join("local-caffeine", mutated_version)).to be_a_directory

      described_class.new(caffeine, force: true).uninstall

      expect(Cask::Caskroom.path.join("local-caffeine", caffeine.version)).not_to be_a_directory
      expect(Cask::Caskroom.path.join("local-caffeine", mutated_version)).not_to be_a_directory
      expect(Cask::Caskroom.path.join("local-caffeine")).not_to be_a_directory
    end
  end

  describe "uninstall_existing_cask" do
    it "uninstalls when cask file is outdated" do
      caffeine = Cask::CaskLoader.load(cask_path("local-caffeine"))
      described_class.new(caffeine).install

      expect(Cask::CaskLoader.load(cask_path("local-caffeine"))).to be_installed

      expect(caffeine).to receive(:installed?).once.and_return(true)
      outdate_caskfile = cask_path("invalid/invalid-depends-on-macos-bad-release")
      expect(caffeine).to receive(:installed_caskfile).once.and_return(outdate_caskfile)
      described_class.new(caffeine).uninstall_existing_cask

      expect(Cask::CaskLoader.load(cask_path("local-caffeine"))).not_to be_installed
    end
  end

  describe "#forbidden_tap_check" do
    before do
      allow(Tap).to receive_messages(allowed_taps: allowed_taps_set, forbidden_taps: forbidden_taps_set)
    end

    let(:homebrew_forbidden) { Tap.fetch("homebrew/forbidden") }
    let(:allowed_third_party) { Tap.fetch("nothomebrew/allowed") }
    let(:disallowed_third_party) { Tap.fetch("nothomebrew/notallowed") }
    let(:allowed_taps_set) { [allowed_third_party.name] }
    let(:forbidden_taps_set) { [homebrew_forbidden.name] }

    it "raises on forbidden tap on cask" do
      cask = Cask::Cask.new("homebrew-forbidden-tap", tap: homebrew_forbidden) do
        url "file://#{TEST_FIXTURE_DIR}/cask/container.tar.gz"
      end

      expect do
        described_class.new(cask).forbidden_tap_check
      end.to raise_error(Cask::CaskCannotBeInstalledError, /has the tap #{homebrew_forbidden}/)
    end

    it "raises on not allowed third-party tap on cask" do
      cask = Cask::Cask.new("homebrew-not-allowed-tap", tap: disallowed_third_party) do
        url "file://#{TEST_FIXTURE_DIR}/cask/container.tar.gz"
      end

      expect do
        described_class.new(cask).forbidden_tap_check
      end.to raise_error(Cask::CaskCannotBeInstalledError, /has the tap #{disallowed_third_party}/)
    end

    it "does not raise on allowed tap on cask" do
      cask = Cask::Cask.new("third-party-allowed-tap", tap: allowed_third_party) do
        url "file://#{TEST_FIXTURE_DIR}/cask/container.tar.gz"
      end

      expect { described_class.new(cask).forbidden_tap_check }.not_to raise_error
    end

    it "raises on forbidden tap on dependency" do
      dep_tap = homebrew_forbidden
      dep_name = "homebrew-forbidden-dependency-tap"
      dep_path = dep_tap.new_formula_path(dep_name)
      dep_path.parent.mkpath
      dep_path.write <<~RUBY
        class #{Formulary.class_s(dep_name)} < Formula
          url "foo"
          version "0.1"
        end
      RUBY

      cask = Cask::Cask.new("homebrew-forbidden-dependent-tap") do
        url "file://#{TEST_FIXTURE_DIR}/cask/container.tar.gz"
        depends_on formula: dep_name
      end

      expect do
        described_class.new(cask).forbidden_tap_check
      end.to raise_error(Cask::CaskCannotBeInstalledError, /from the #{dep_tap} tap but/)
    ensure
      FileUtils.rm_r(dep_path.parent.parent)
    end
  end

  describe "#forbidden_cask_and_formula_check" do
    it "raises on forbidden cask" do
      ENV["HOMEBREW_FORBIDDEN_CASKS"] = cask_name = "homebrew-forbidden-cask"
      cask = Cask::Cask.new(cask_name) do
        url "file://#{TEST_FIXTURE_DIR}/cask/container.tar.gz"
      end

      expect do
        described_class.new(cask).forbidden_cask_and_formula_check
      end.to raise_error(Cask::CaskCannotBeInstalledError, /forbidden for installation/)
    end

    it "raises on forbidden dependency" do
      ENV["HOMEBREW_FORBIDDEN_FORMULAE"] = dep_name = "homebrew-forbidden-dependency-formula"
      dep_path = CoreTap.instance.new_formula_path(dep_name)
      dep_path.write <<~RUBY
        class #{Formulary.class_s(dep_name)} < Formula
          url "foo"
          version "0.1"
        end
      RUBY

      cask = Cask::Cask.new("homebrew-forbidden-dependent-cask") do
        url "file://#{TEST_FIXTURE_DIR}/cask/container.tar.gz"
        depends_on formula: dep_name
      end

      expect do
        described_class.new(cask).forbidden_cask_and_formula_check
      end.to raise_error(Cask::CaskCannotBeInstalledError, /#{dep_name} formula was forbidden/)
    end
  end

  describe "#forbidden_cask_artifacts_check" do
    before do
      allow(Homebrew::EnvConfig).to receive(:odeprecated).with("HOMEBREW_FORBIDDEN_CASK_ARTIFACTS", nil,
                                                               disable: false)
    end

    it "raises when cask contains forbidden pkg artifact" do
      ENV["HOMEBREW_FORBIDDEN_CASK_ARTIFACTS"] = "pkg"
      cask = Cask::Cask.new("homebrew-pkg-cask") do
        url "file://#{TEST_FIXTURE_DIR}/cask/container.tar.gz"
        pkg "MyInstaller.pkg"
      end

      expect do
        described_class.new(cask).forbidden_cask_artifacts_check
      end.to raise_error(Cask::CaskCannotBeInstalledError, /contains a 'pkg' artifact/)
    end

    it "raises when cask contains forbidden installer artifact" do
      ENV["HOMEBREW_FORBIDDEN_CASK_ARTIFACTS"] = "installer"
      cask = Cask::Cask.new("homebrew-installer-cask") do
        url "file://#{TEST_FIXTURE_DIR}/cask/container.tar.gz"
        installer script: {
          executable: "MyInstaller.sh",
          args:       ["--silent"],
        }
      end

      expect do
        described_class.new(cask).forbidden_cask_artifacts_check
      end.to raise_error(Cask::CaskCannotBeInstalledError, /contains a 'installer' artifact/)
    end

    it "raises when cask contains multiple forbidden artifacts" do
      ENV["HOMEBREW_FORBIDDEN_CASK_ARTIFACTS"] = "pkg installer"
      cask = Cask::Cask.new("homebrew-multi-forbidden-cask") do
        url "file://#{TEST_FIXTURE_DIR}/cask/container.tar.gz"
        pkg "MyInstaller.pkg"
      end

      expect do
        described_class.new(cask).forbidden_cask_artifacts_check
      end.to raise_error(Cask::CaskCannotBeInstalledError, /contains a 'pkg' artifact/)
    end

    it "does not raise when cask does not contain forbidden artifacts" do
      ENV["HOMEBREW_FORBIDDEN_CASK_ARTIFACTS"] = "pkg installer"
      cask = Cask::Cask.new("homebrew-allowed-cask") do
        url "file://#{TEST_FIXTURE_DIR}/cask/container.tar.gz"
        app "MyApp.app"
      end

      expect { described_class.new(cask).forbidden_cask_artifacts_check }.not_to raise_error
    end
  end

  describe "#prelude" do
    it "raises on forbidden cask before downloading" do
      ENV["HOMEBREW_FORBIDDEN_CASKS"] = cask_name = "homebrew-forbidden-cask"
      cask = Cask::Cask.new(cask_name) do
        url "file://#{TEST_FIXTURE_DIR}/cask/container.tar.gz"
        app "Fake.app"
      end
      installer = described_class.new(cask)

      expect(installer).not_to receive(:download)

      expect { installer.prelude }.to raise_error(Cask::CaskCannotBeInstalledError, /forbidden for installation/)
    end
  end

  describe "#enqueue_downloads" do
    it "uses API cask metadata for API-loaded cask downloads" do
      cask = Cask::Cask.new("api-cask", loaded_from_api: true, loaded_from_internal_api: true) do
        url "https://example.com/source-cask.zip"
        version "0.9"
        sha256 "d7b9f4e8bf83608b71fe958a99f19f2e5e68bb2582965d32e41759c24f1aef97"
        app "Fake.app"
      end
      cask_struct = Homebrew::API::CaskStruct.new(
        sha256:   "d7b9f4e8bf83608b71fe958a99f19f2e5e68bb2582965d32e41759c24f1aef97",
        url_args: ["https://example.com/api-cask.zip"],
        version:  "1.0",
      )
      download_queue = instance_double(Homebrew::DownloadQueue)
      installer = described_class.new(cask, download_queue:)

      allow(Homebrew::API::Internal).to receive(:cask_struct).with("api-cask").and_return(cask_struct)
      expect(download_queue).to receive(:enqueue) do |download|
        expect(download).to be_a(Cask::Download)
        expect(download.url.to_s).to eq("https://example.com/api-cask.zip")
      end

      installer.enqueue_downloads
    end

    it "enqueues the selected language download from API data" do
      source_cask = Cask::CaskLoader.load("with-languages")
      cask_struct = Homebrew::API::Cask::CaskStructGenerator.generate_cask_struct_hash(
        source_cask.to_hash_with_variations,
      )
      config = Cask::Config.new(explicit: { languages: ["zh"] })
      cask = Cask::CaskLoader::FromAPILoader.new(
        "language-api-cask",
        from_json:          cask_struct.serialize,
        from_internal_json: true,
      ).load(config:)
      download_queue = instance_double(Homebrew::DownloadQueue)
      installer = described_class.new(cask, download_queue:)

      allow(Homebrew::API::Internal).to receive(:cask_struct).with("language-api-cask").and_return(cask_struct)
      expect(download_queue).to receive(:enqueue) do |download|
        expect(download.url.to_s).to eq("file://#{TEST_FIXTURE_DIR}/cask/container.tar.gz")
      end

      installer.enqueue_downloads
    end

    it "stages the main cask download outside Caskroom before install" do
      cask = Cask::CaskLoader.load(cask_path("local-caffeine"))
      download_queue = Homebrew::DownloadQueue.new(pour: true)
      installer = described_class.new(cask, download_queue:, defer_fetch: true)
      queued_staged_path = installer.downloader.staged_path_from_download_queue
      queued_staged_marker = installer.downloader.staged_path_from_download_queue_marker

      begin
        installer.enqueue_downloads
        download_queue.fetch
      ensure
        download_queue.shutdown
      end

      expect(cask.staged_path).not_to exist
      expect(cask).not_to be_installed
      expect(queued_staged_path/"Caffeine.app").to be_a_directory
      expect(queued_staged_marker).to exist

      expect(installer).not_to receive(:extract_primary_container)

      installer.stage

      expect(cask.staged_path/"Caffeine.app").to be_a_directory
      expect(cask).to be_installed
    end

    it "stages nested containers for API-loaded casks" do
      container_dir = mktmpdir
      FileUtils.cp(TEST_FIXTURE_DIR/"cask/caffeine.zip", container_dir/"NestedApp.zip")
      (container_dir/"README").write("NestedApp.zip contains the application")
      download = mktmpdir/"api-nested-cask.tar.gz"
      system "tar", "--create", "--gzip", "--file", download, "--directory", container_dir, "."
      sha256 = download.sha256
      cask = Cask::Cask.new("api-nested-cask", loaded_from_api: true, loaded_from_internal_api: true) do
        version "1.2.3"
        sha256 sha256
        url "file://#{download}"
        container nested: "NestedApp.zip"
        app "Caffeine.app"
      end
      cask_struct = Homebrew::API::CaskStruct.new(
        container_args:    { nested: "NestedApp.zip", type: nil },
        container_present: true,
        sha256:,
        url_args:          ["file://#{download}"],
        version:           "1.2.3",
      )
      allow(Homebrew::API::Internal).to receive(:cask_struct).with("api-nested-cask").and_return(cask_struct)
      download_queue = Homebrew::DownloadQueue.new(pour: true)
      installer = described_class.new(cask, download_queue:, defer_fetch: true)

      begin
        installer.enqueue_downloads
        download_queue.fetch
      ensure
        download_queue.shutdown
      end
      installer.stage

      expect(cask.staged_path/"Caffeine.app").to be_a_directory
    end

    it "does not stage queued downloads with missing unpack dependencies" do
      cask = Cask::CaskLoader.load(cask_path("container-bzip2"))
      download_queue = Homebrew::DownloadQueue.new(pour: true)
      installer = described_class.new(cask, download_queue:, defer_fetch: true)
      queued_staged_path = installer.downloader.staged_path_from_download_queue
      queued_staged_marker = installer.downloader.staged_path_from_download_queue_marker

      allow_any_instance_of(Formula).to receive(:any_version_installed?).and_return(false)
      expect(installer).not_to receive(:extract_primary_container)

      begin
        installer.enqueue_downloads
        download_queue.fetch
      ensure
        download_queue.shutdown
      end

      expect(cask.staged_path).not_to exist
      expect(cask).not_to be_installed
      expect(queued_staged_path).not_to exist
      expect(queued_staged_marker).not_to exist
    end
  end

  describe "#enqueue_dependency_downloads" do
    it "skips dependency resolution when the cask download failed" do
      cask = Cask::CaskLoader.load(cask_path("local-caffeine"))
      installer = described_class.new(cask, download_queue: instance_double(Homebrew::DownloadQueue))
      installer.download_failed!

      expect(installer).not_to receive(:cask_and_formula_dependencies)

      installer.enqueue_dependency_downloads
    end

    it "reuses formula dependencies fetched before installation" do
      cask = Cask::CaskLoader.load(cask_path("local-caffeine"))
      dependency = formula("cask-dependency") do
        url "https://brew.sh/cask-dependency-1.0.tar.gz"
      end
      queue = instance_double(Homebrew::DownloadQueue, failed_downloads: [])
      installer = described_class.new(cask, download_queue: queue)
      allow(installer).to receive_messages(cask_and_formula_dependencies:         [dependency],
                                           missing_cask_and_formula_dependencies: [dependency])
      allow(dependency).to receive_messages(any_version_installed?: false, optlinked?: false)
      formula_installers = nil

      expect(Homebrew::Install).to receive(:enqueue_formulae) do |installers, download_queue:|
        expect(download_queue).to equal(queue)
        formula_installers = installers
        installers
      end
      installer.enqueue_dependency_downloads
      formula_installers&.each do |formula_installer|
        allow(formula_installer).to receive(:install)
        allow(formula_installer).to receive(:finish)
      end
      allow(Homebrew::Install).to receive(:perform_preinstall_checks_once)
      expect(Homebrew::Install).not_to receive(:fetch_formulae)
      expect(Homebrew::Install).to receive(:reject_failed_downloads)
        .with(formula_installers, download_queue: queue)
        .and_return(formula_installers)

      installer.satisfy_cask_and_formula_dependencies
    end
  end

  describe "#load_installed_caskfile!" do
    it "uses recovered installed metadata before falling back to the current cask" do
      cask = Cask::CaskLoader.load(cask_path("local-caffeine"))
      recovered_cask = Cask::Cask.new(cask.token) do
        version "1.0"
        app "Recovered.app"
      end
      installed_caskfile = mktmpdir/"local-caffeine.json"
      installed_caskfile.write("{}")
      allow(Cask::Migrator).to receive(:migrate_if_needed)
      allow(cask).to receive(:installed_caskfile).and_return(installed_caskfile)
      allow(Cask::CaskLoader).to receive(:load_from_installed_caskfile)
        .with(installed_caskfile)
        .and_raise(Cask::CaskInvalidError.new(cask.token, "broken DSL"))
      expect(Cask::CaskLoader).to receive(:recover_from_installed_caskfile)
        .with(installed_caskfile, tab: an_instance_of(Cask::Tab), fallback_cask: cask)
        .and_return(recovered_cask)

      installer = described_class.new(cask)
      installer.load_installed_caskfile!

      expect(installer.cask).to equal(recovered_cask)
    end
  end

  describe "rename operations" do
    let(:tmpdir) { mktmpdir }
    let(:staged_path) { Pathname(tmpdir) }

    after do
      FileUtils.rm_rf(tmpdir) if tmpdir && File.exist?(tmpdir)
    end

    it "processes rename operations after extraction" do
      # Create test files
      (staged_path / "Original App.app").mkpath
      (staged_path / "Original App.app" / "Contents").mkpath

      cask = Cask::Cask.new("rename-test-cask") do
        url "file://#{TEST_FIXTURE_DIR}/cask/caffeine.zip"
        rename "Original App.app", "Renamed App.app"
        app "Renamed App.app"
      end

      # Mock the staged_path to point to our test directory
      allow(cask).to receive(:staged_path).and_return(staged_path)

      installer = described_class.new(cask)
      installer.process_rename_operations

      expect(staged_path / "Renamed App.app").to be_a_directory
      expect(staged_path / "Original App.app").not_to exist
    end

    it "handles multiple rename operations in order" do
      # Create test file
      (staged_path / "Original.app").mkpath

      cask = Cask::Cask.new("multi-rename-test-cask") do
        url "file://#{TEST_FIXTURE_DIR}/cask/caffeine.zip"
        rename "Original.app", "First Rename.app"
        rename "First Rename.app", "Final Name.app"
        app "Final Name.app"
      end

      allow(cask).to receive(:staged_path).and_return(staged_path)

      installer = described_class.new(cask)
      installer.process_rename_operations

      expect(staged_path / "Final Name.app").to be_a_directory
      expect(staged_path / "Original.app").not_to exist
      expect(staged_path / "First Rename.app").not_to exist
    end

    it "handles glob patterns in rename operations" do
      # Create test file with version
      (staged_path / "Test App v1.2.3.pkg").write("test content")

      cask = Cask::Cask.new("glob-rename-test-cask") do
        url "file://#{TEST_FIXTURE_DIR}/cask/caffeine.zip"
        rename "Test App*.pkg", "Test App.pkg"
        pkg "Test App.pkg"
      end

      allow(cask).to receive(:staged_path).and_return(staged_path)

      installer = described_class.new(cask)
      installer.process_rename_operations

      expect(staged_path / "Test App.pkg").to be_a_file
      expect((staged_path / "Test App.pkg").read).to eq("test content")
      expect(staged_path / "Test App v1.2.3.pkg").not_to exist
    end

    it "does nothing when no files match rename pattern" do
      # Create a different file
      (staged_path / "Different.app").mkpath

      cask = Cask::Cask.new("no-match-rename-test-cask") do
        url "file://#{TEST_FIXTURE_DIR}/cask/caffeine.zip"
        rename "NonExistent*.app", "Target.app"
        app "Different.app"
      end

      allow(cask).to receive(:staged_path).and_return(staged_path)

      installer = described_class.new(cask)

      expect { installer.process_rename_operations }.not_to raise_error
      expect(staged_path / "Different.app").to be_a_directory
      expect(staged_path / "Target.app").not_to exist
    end
  end
end
