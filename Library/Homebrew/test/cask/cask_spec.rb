# frozen_string_literal: true

RSpec.describe Cask::Cask, :cask do
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
      expect(c.token).to eq("local-caffeine")
    end

    it "returns an instance of the Cask from a JSON file" do
      c = Cask::CaskLoader.load("#{TEST_FIXTURE_DIR}/cask/caffeine.json")
      expect(c).to be_a(described_class)
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
        expect(hash).to be_a(Hash)
        expect(JSON.pretty_generate(hash)).to eq(expected_json)
      end
    end
  end
end
