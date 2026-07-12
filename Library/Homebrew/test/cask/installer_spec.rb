# typed: false
# frozen_string_literal: true

RSpec.describe Cask::Installer, :cask do
  def stub_dmg_extraction
    allow(UnpackStrategy::Dmg).to receive(:can_extract?).and_return(true)
    allow_any_instance_of(UnpackStrategy::Dmg).to receive(:extract_nestedly) do |_strategy, to:, **|
      to.mkpath
      yield to
    end
  end

  describe "#save_caskfile" do
    it "stores casks loaded from Ruby source as JSON metadata" do
      cask = Cask::CaskLoader.load(cask_path("local-caffeine"))

      described_class.new(cask).save_caskfile

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

    it "strips legacy install flight blocks from JSON metadata" do
      cask = Cask::CaskLoader.load(cask_path("with-preflight"))

      described_class.new(cask).save_caskfile

      expect(JSON.parse(cask.installed_caskfile.read).keys).to be_empty
    end

    it "stores legacy uninstall flight block casks as Ruby metadata" do
      expect(%w[with-uninstall-preflight with-uninstall-postflight].map do |token|
        cask = Cask::CaskLoader.load(cask_path(token))

        described_class.new(cask).save_caskfile

        [
          cask.installed_caskfile&.basename&.to_s,
          Cask::CaskLoader.load_from_installed_caskfile(cask.installed_caskfile).uninstall_flight_blocks?,
        ]
      end).to eq([
        ["with-uninstall-preflight.rb", true],
        ["with-uninstall-postflight.rb", true],
      ])
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

      loaded_cask = Cask::CaskLoader.load_from_installed_caskfile(cask.installed_caskfile)
      expect([
        cask.installed_caskfile&.basename&.to_s,
        loaded_cask.token,
        loaded_cask.loaded_from_internal_api?,
        JSON.parse(cask.installed_caskfile.read).keys.sort,
      ]).to eq(["api-cask.json", "api-cask", false, []])
    end
  end

  describe "install" do
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

    it "installs fine if sha256 :no_check is used with --require-sha and --force" do
      no_checksum = Cask::CaskLoader.load(cask_path("no-checksum"))

      described_class.new(no_checksum, require_sha: true, force: true).install

      expect(no_checksum).to be_installed
    end

    it "prints caveats if they're present" do
      with_caveats = Cask::CaskLoader.load(cask_path("with-caveats"))

      expect do
        described_class.new(with_caveats).install
      end.to output(/Here are some things you might want to know/).to_stdout

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

    context "when loaded from the api and caskfile is required" do
      let(:path) { cask_path("local-caffeine") }
      let(:content) { File.read(path) }

      it "installs cask" do
        source_caffeine = Cask::CaskLoader.load(path)
        expect(Homebrew::API::Cask).to receive(:source_download_cask).once.and_return(source_caffeine)

        caffeine = Cask::CaskLoader.load(path)
        expect(caffeine).to receive(:loaded_from_api?).once.and_return(true)
        expect(caffeine).to receive(:caskfile_only?).once.and_return(true)

        described_class.new(caffeine).install
        expect(Cask::CaskLoader.load(path)).to be_installed
      end
    end

    context "when loaded from the api with unsupported requirements" do
      let(:cask) { Cask::CaskLoader.load(cask_path("with-preflight")) }
      let(:download_queue) { instance_double(Homebrew::DownloadQueue, enqueue: nil) }
      let(:macos_requirement) { cask.depends_on.macos }

      before do
        allow(macos_requirement).to receive(:satisfied?).and_return(false)
        allow(macos_requirement).to receive(:message).with(type: :cask).and_return("macOS is required")
        allow(cask).to receive(:loaded_from_api?).and_return(true)
      end

      it "checks requirements before enqueueing downloads" do
        expect(Homebrew::API::Cask).not_to receive(:source_download)

        expect do
          described_class.new(cask, download_queue:).enqueue_downloads
        end.to raise_error(Cask::CaskError, "with-preflight: macOS is required")
      end

      it "checks requirements before loading the source cask during fetch" do
        expect(Homebrew::API::Cask).not_to receive(:source_download_cask)

        expect do
          described_class.new(cask).fetch
        end.to raise_error(Cask::CaskError, "with-preflight: macOS is required")
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

    context "when loaded from the api, caskfile is required and installed caskfile is invalid" do
      let(:path) { cask_path("local-caffeine") }
      let(:content) { File.read(path) }
      let(:invalid_path) { instance_double(Pathname) }

      before do
        allow(invalid_path).to receive(:exist?).and_return(false)
      end

      it "uninstalls cask" do
        source_caffeine = Cask::CaskLoader.load(path)
        expect(Homebrew::API::Cask).to receive(:source_download_cask).twice.and_return(source_caffeine)

        caffeine = Cask::CaskLoader.load(path)
        expect(caffeine).to receive(:loaded_from_api?).twice.and_return(true)
        expect(caffeine).to receive(:caskfile_only?).twice.and_return(true)
        expect(caffeine).to receive(:installed_caskfile).once.and_return(invalid_path)

        described_class.new(caffeine).install
        expect(Cask::CaskLoader.load(path)).to be_installed

        described_class.new(caffeine).uninstall
        expect(Cask::CaskLoader.load(path)).not_to be_installed
      end
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
      Formulary.cache.delete(dep_path.to_s)

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
      Formulary.cache.delete(dep_path.to_s)

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
    it "raises on forbidden cask before fetching the caskfile from the Source API" do
      ENV["HOMEBREW_FORBIDDEN_CASKS"] = cask_name = "homebrew-forbidden-cask"
      cask = Cask::Cask.new(cask_name) do
        url "file://#{TEST_FIXTURE_DIR}/cask/container.tar.gz"
      end
      allow(cask).to receive_messages(loaded_from_api?: true, caskfile_only?: true)
      installer = described_class.new(cask)

      expect(Homebrew::API::Cask).not_to receive(:source_download_cask)
      expect(installer).not_to receive(:download)

      expect { installer.prelude }.to raise_error(Cask::CaskCannotBeInstalledError, /forbidden for installation/)
    end
  end

  describe "#prelude_fetch" do
    it "uses API cask metadata for API-loaded cask downloads" do
      cask = Cask::Cask.new("api-cask", loaded_from_api: true, loaded_from_internal_api: true) do
        url "https://example.com/source-cask.zip"
        version "0.9"
        sha256 "d7b9f4e8bf83608b71fe958a99f19f2e5e68bb2582965d32e41759c24f1aef97"
      end
      cask_struct = Homebrew::API::CaskStruct.new(
        sha256:   "d7b9f4e8bf83608b71fe958a99f19f2e5e68bb2582965d32e41759c24f1aef97",
        url_args: ["https://example.com/api-cask.zip"],
        version:  "1.0",
      )
      download_queue = instance_double(Homebrew::DownloadQueue)
      installer = described_class.new(cask, download_queue:)

      allow(Homebrew::API::Internal).to receive(:cask_struct).with("api-cask").and_return(cask_struct)
      expect(Homebrew::API::Cask).not_to receive(:source_download)
      expect(download_queue).to receive(:enqueue) do |download|
        expect(download).to be_a(Cask::Download)
        expect(download.url.to_s).to eq("https://example.com/api-cask.zip")
      end

      installer.enqueue_downloads
    end

    it "enqueues source API caskfiles before the main cask download" do
      cask = Cask::Cask.new("source-api-cask") do
        url "file://#{TEST_FIXTURE_DIR}/cask/container.tar.gz"
      end
      allow(cask).to receive_messages(loaded_from_api?: true, caskfile_only?: true, languages: ["en"])
      download_queue = instance_double(Homebrew::DownloadQueue)
      installer = described_class.new(cask, download_queue:)
      source_download = instance_double(Homebrew::API::SourceDownload, downloaded?: false)

      expect(Homebrew::API::Cask).to receive(:source_download_for).with(cask).and_return(source_download)
      expect(download_queue).to receive(:enqueue).with(source_download)
      expect(Homebrew::API::Cask).not_to receive(:source_download_cask)
      expect(installer).not_to receive(:download)

      installer.prelude_fetch
    end

    it "leaves source API caskfiles in the main queue when their URL is known" do
      cask = Cask::Cask.new("source-api-cask") do
        url "file://#{TEST_FIXTURE_DIR}/cask/container.tar.gz"
      end
      allow(cask).to receive_messages(loaded_from_api?: true, caskfile_only?: true, languages: [])
      download_queue = instance_double(Homebrew::DownloadQueue)
      installer = described_class.new(cask, download_queue:)

      expect(Homebrew::API::Cask).to receive(:source_download).with(cask, download_queue:, enqueue: true)
      expect(Homebrew::API::Cask).not_to receive(:source_download_cask)
      expect(download_queue).to receive(:enqueue).with(instance_of(Cask::Download))

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
      installer.send(:process_rename_operations)

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
      installer.send(:process_rename_operations)

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
      installer.send(:process_rename_operations)

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

      expect { installer.send(:process_rename_operations) }.not_to raise_error
      expect(staged_path / "Different.app").to be_a_directory
      expect(staged_path / "Target.app").not_to exist
    end
  end
end
