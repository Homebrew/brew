# typed: true
# frozen_string_literal: true

RSpec.describe Cask::CaskLoader::FromAPILoader, :cask do
  shared_context "with API setup" do |local_token|
    let(:api_token) { "#{local_token}-api" }
    let(:cask_from_source) { Cask::CaskLoader.load(local_token.to_s) }
    let(:cask_json) do
      hash = cask_from_source.to_hash_with_variations
      # This value will always be present in the json API, but is skipped in tests
      hash["tap_git_head"] = "abcdef1234567890abcdef1234567890abcdef12"
      json = JSON.pretty_generate(hash)
      JSON.parse(json)
    end
    let(:casks_from_api_hash) { { api_token => cask_json.except("token") } }
    let(:api_loader) { described_class.new(api_token, from_json: cask_json) }

    before do
      allow(Homebrew::API).to receive_messages(cask_tokens: casks_from_api_hash.keys, cask_renames: {})
      allow(Homebrew::API).to receive(:cask_token?) { |token| casks_from_api_hash.key?(token) }
      allow(Homebrew::API::Cask).to receive(:all_casks).and_return(casks_from_api_hash)

      # The call to `Cask::CaskLoader.load` above sets the Tap cache prematurely.
      Tap.clear_cache
    end
  end

  shared_context "with internal API setup" do |local_token|
    # Load the cask and generate its hash first before we enable internal API mode for the test body
    let!(:cask_from_internal_source) { Cask::CaskLoader.load(local_token.to_s) }
    let!(:cask_internal_struct) do
      hash_with_variations = cask_from_internal_source.to_hash_with_variations
      Homebrew::API::Cask::CaskStructGenerator.generate_cask_struct_hash(hash_with_variations)
    end

    let(:internal_api_token) { "#{local_token}-internal-api" }
    let(:internal_tap_git_head) { "abcdef1234567890abcdef1234567890abcdef12" }
    let(:cask_internal_json) do
      hash = cask_internal_struct.serialize
      # This value must be manually added when loading from internal API contents directly
      hash["tap_git_head"] = internal_tap_git_head
      json = JSON.pretty_generate(hash)
      JSON.parse(json)
    end
    # let(:cask_structs_from_api_hash) { { internal_api_token => cask_internal_struct } }
    let(:casks_from_internal_api_hash) { { internal_api_token => cask_internal_json.except("tap_git_head") } }
    let(:internal_api_loader) do
      described_class.new(internal_api_token, from_json: cask_internal_json, from_internal_json: true)
    end

    before do
      allow(Homebrew::API::Internal)
        .to receive_messages(cask_hashes:         casks_from_internal_api_hash,
                             cask_renames:        {},
                             cask_tap_migrations: {},
                             cask_tap_git_head:   internal_tap_git_head)
      allow(Homebrew::API::Internal).to receive(:cask_name?) { |token| casks_from_internal_api_hash.key?(token) }
      allow(Homebrew::API::Internal).to receive(:cask_hash) { |token| casks_from_internal_api_hash[token] }

      # The call to `Cask::CaskLoader.load` above sets the Tap cache prematurely.
      Tap.clear_cache
    end
  end

  describe ".try_new" do
    context "when not using the API", :no_api do
      include_context "with API setup", "test-opera"

      it "returns false" do
        expect(described_class.try_new(api_token)).to be_nil
      end
    end

    context "when using the API" do
      include_context "with API setup", "test-opera"

      it "returns a loader for valid token" do
        expect(described_class.try_new(api_token))
          .to be_a(described_class)
          .and have_attributes(token: api_token)
      end

      it "returns a loader for valid full name" do
        expect(described_class.try_new("homebrew/cask/#{api_token}"))
          .to be_a(described_class)
          .and have_attributes(token: api_token)
      end

      context "with core tap migration renames" do
        let(:foo_tap) { Tap.fetch("homebrew", "foo") }

        before do
          foo_tap.path.mkpath
        end

        after do
          FileUtils.rm_rf foo_tap.path
        end

        it "returns the tap migration rename by old token" do
          old_token = "#{api_token}-old"
          (foo_tap.path/"tap_migrations.json").write <<~JSON
            { "#{old_token}": "homebrew/cask/#{api_token}" }
          JSON

          loader = Cask::CaskLoader::FromNameLoader.try_new(old_token)
          expect(loader).to be_a(described_class)
          expect(loader&.token).to eq api_token
          expect(loader&.path).not_to exist
        end

        it "returns the tap migration rename by old full name" do
          old_token = "#{api_token}-old"
          (foo_tap.path/"tap_migrations.json").write <<~JSON
            { "#{old_token}": "homebrew/cask/#{api_token}" }
          JSON

          loader = Cask::CaskLoader::FromTapLoader.try_new("#{foo_tap}/#{old_token}")
          expect(loader).to be_a(described_class)
          expect(loader&.token).to eq api_token
          expect(loader&.path).not_to exist
        end
      end
    end

    context "when using the internal API" do
      include_context "with internal API setup", "test-opera"

      it "returns a loader for valid token" do
        expect(described_class.try_new(internal_api_token))
          .to be_a(described_class)
          .and have_attributes(token: internal_api_token)
      end

      it "returns a loader for valid full name" do
        expect(described_class.try_new("homebrew/cask/#{internal_api_token}"))
          .to be_a(described_class)
          .and have_attributes(token: internal_api_token)
      end

      context "with core tap migration renames" do
        let(:foo_tap) { Tap.fetch("homebrew", "foo") }

        before do
          foo_tap.path.mkpath
        end

        after do
          FileUtils.rm_rf foo_tap.path
        end

        it "returns the tap migration rename by old token" do
          old_token = "#{internal_api_token}-old"
          (foo_tap.path/"tap_migrations.json").write <<~JSON
            { "#{old_token}": "homebrew/cask/#{internal_api_token}" }
          JSON

          loader = Cask::CaskLoader::FromNameLoader.try_new(old_token)
          expect(loader).to be_a(described_class)
          expect(loader&.token).to eq internal_api_token
          expect(loader&.path).not_to exist
        end

        it "returns the tap migration rename by old full name" do
          old_token = "#{internal_api_token}-old"
          (foo_tap.path/"tap_migrations.json").write <<~JSON
            { "#{old_token}": "homebrew/cask/#{internal_api_token}" }
          JSON

          loader = Cask::CaskLoader::FromTapLoader.try_new("#{foo_tap}/#{old_token}")
          expect(loader).to be_a(described_class)
          expect(loader&.token).to eq internal_api_token
          expect(loader&.path).not_to exist
        end
      end
    end

    it "returns nil for full name with invalid tap" do
      expect(described_class.try_new("homebrew/foo/test-opera")).to be_nil
    end
  end

  describe "#load" do
    it "loads existing JSON metadata that still has a verified URL spec" do
      cask = described_class.new(
        "legacy-verified",
        from_json:               {
          "version"   => "1.0",
          "url"       => "https://cdn.example.com/app.dmg",
          "url_specs" => { "verified" => "cdn.example.com/" },
          "artifacts" => [{ "app" => ["App.app"] }],
        },
        path:                    Pathname("/tmp/legacy-verified.json"),
        from_installed_caskfile: true,
      ).load(config: nil)

      expect(cask.url.to_s).to eq("https://cdn.example.com/app.dmg")
    end

    it "does not dispatch unknown raw artifacts" do
      marker = mktmpdir/"unexpected-dispatch"
      cask_struct = Homebrew::API::CaskStruct.new(
        version:       "1.0",
        sha256:        "0" * 64,
        url_args:      ["https://example.invalid/unknown-raw-artifact.zip"],
        raw_artifacts: [[:instance_eval, ["FileUtils.touch(#{marker.to_s.dump})"], {}, nil]],
      )
      loader = described_class.new(
        "unknown-raw-artifact",
        from_json:          cask_struct.serialize,
        from_internal_json: true,
      )

      expect { loader.load(config: nil) }.not_to change(marker, :exist?).from(false)
    end

    it "preserves supported stage-only, package, and uninstall artifacts" do
      base_source = {
        "token"   => "supported-artifacts",
        "version" => "1.0",
        "sha256"  => "0" * 64,
        "url"     => "https://example.invalid/supported-artifacts.zip",
      }
      stage_only_cask = described_class.new(
        "supported-stage-only",
        from_json:               base_source.merge("artifacts" => [{ "stage_only" => [true] }]),
        path:                    Pathname("/tmp/supported-stage-only.json"),
        from_installed_caskfile: true,
      ).load(config: nil)
      pkg_cask = described_class.new(
        "supported-pkg",
        from_json:               base_source.merge(
          "artifacts" => [
            { "pkg" => ["Test.pkg"] },
            { "uninstall" => [{ "pkgutil" => "com.example.test" }] },
          ],
        ),
        path:                    Pathname("/tmp/supported-pkg.json"),
        from_installed_caskfile: true,
      ).load(config: nil)

      expect([stage_only_cask.artifacts_list, pkg_cask.artifacts_list]).to eq([
        [{ stage_only: [true] }],
        [{ uninstall: [{ pkgutil: "com.example.test" }] }, { pkg: ["Test.pkg"] }],
      ])
    end

    it "handles greedy outdated checks for installed metadata without a URL" do
      token = "url-less-installed-cask"
      caskroom = mktmpdir
      allow(Cask::Caskroom).to receive(:path).and_return(caskroom)
      allow(described_class).to receive(:try_new).and_call_original
      allow(described_class).to receive(:try_new).with(token).and_return(
        Cask::CaskLoader::FromInstanceLoader.new(Cask::Cask.new(token)),
      )
      path = caskroom/token/".metadata/latest/20260713000000.000/Casks/#{token}.json"
      cask = described_class.new(token, from_json: {}, path:, from_installed_caskfile: true).load(config: nil)
      allow(cask).to receive(:installed_version).and_return("latest")
      cask.download_sha_path.dirname.mkpath
      cask.download_sha_path.write("old-download-sha")

      expect(cask.outdated?(greedy: true)).to be(true)
    end

    it "uses current API artifacts for installed metadata without receipt artifacts" do
      token = "receipt-less-installed-cask"
      caskroom = mktmpdir
      allow(Cask::Caskroom).to receive(:path).and_return(caskroom)
      api_cask = Cask::Cask.new(token) do
        app "Receipt-less.app"
        uninstall quit: "com.example.receipt-less"
        zap trash: "~/Library/Preferences/com.example.receipt-less.plist"
      end
      allow(described_class).to receive(:try_new).and_call_original
      allow(described_class).to receive(:try_new).with(token)
                                                 .and_return(Cask::CaskLoader::FromInstanceLoader.new(api_cask))
      path = caskroom/token/".metadata/1.0/20260713000000.000/Casks/#{token}.json"

      cask = described_class.new(token, from_json: {}, path:, from_installed_caskfile: true).load(config: nil)

      expect(cask.artifacts_list(uninstall_only: true)).to eq([
        { uninstall: [{ quit: "com.example.receipt-less" }] },
        { app: ["Receipt-less.app"] },
        { zap: [{ trash: "~/Library/Preferences/com.example.receipt-less.plist" }] },
      ])
    end

    it "does not read a malformed receipt when installed metadata is self-contained" do
      token = "self-contained-installed-cask"
      caskroom = mktmpdir
      allow(Cask::Caskroom).to receive(:path).and_return(caskroom)
      receipt = caskroom/token/".metadata/INSTALL_RECEIPT.json"
      receipt.dirname.mkpath
      receipt.write("{")
      path = caskroom/token/".metadata/1.0/20260713000000.000/Casks/#{token}.json"

      cask = described_class.new(
        token,
        from_json:               {
          "version"   => "1.0",
          "artifacts" => [{ "app" => ["Self-contained.app"] }],
        },
        path:,
        from_installed_caskfile: true,
      ).load(config: nil)

      expect(cask.artifacts_list(uninstall_only: true)).to eq([{ app: ["Self-contained.app"] }])
    end

    shared_examples "loads from API" do |cask_token|
      include_context "with API setup", cask_token
      include_context "with internal API setup", cask_token
      let(:cask_from_api) { api_loader.load(config: nil) }
      let(:cask_from_internal_api) { internal_api_loader.load(config: nil) }

      it "loads from JSON API" do
        expect(cask_from_api).to be_a(Cask::Cask)
        expect(cask_from_api.token).to eq(api_token)
        expect(cask_from_api.loaded_from_api?).to be(true)
        expect(cask_from_api.loaded_from_internal_api?).to be(false)
        expect(cask_from_api.sourcefile_path).to eq(Homebrew::API::Cask.cached_json_file_path)
      end

      it "loads from internal JSON API" do
        expect(cask_from_internal_api).to be_a(Cask::Cask)
        expect(cask_from_internal_api.token).to eq(internal_api_token)
        expect(cask_from_internal_api.loaded_from_api?).to be(true)
        expect(cask_from_internal_api.loaded_from_internal_api?).to be(true)
        expect(cask_from_internal_api.sourcefile_path).to eq(Homebrew::API::Internal.cached_packages_json_file_path)
      end
    end

    context "with a binary stanza" do
      include_examples "loads from API", "with-binary"
    end

    context "with cask dependencies" do
      include_examples "loads from API", "with-depends-on-cask-multiple"
    end

    context "with formula dependencies" do
      include_examples "loads from API", "with-depends-on-formula-multiple"
    end

    context "with macos dependencies" do
      include_examples "loads from API", "with-depends-on-macos-array"
    end

    context "with an installer stanza" do
      include_examples "loads from API", "with-installer-script"
    end

    context "with uninstall stanzas" do
      include_examples "loads from API", "with-uninstall-multi"
    end

    context "with a zap stanza" do
      include_examples "loads from API", "with-zap"
    end

    context "with install step stanzas" do
      include_examples "loads from API", "with-install-steps"

      context "when running install steps loaded from internal JSON API" do
        include_context "with internal API setup", "with-install-steps"

        it "runs the loaded steps" do
          cask = internal_api_loader.load(config: nil)
          cask.staged_path.mkpath
          cask.config_path.dirname.mkpath
          (cask.staged_path/"container").write "app"
          (cask.staged_path/"move-source").write "moved"
          allow(Sandbox).to receive(:use_for?).and_return(false)

          Cask::Installer.new(cask, command: NeverSudoSystemCommand).install_artifacts

          expect(cask.staged_path/"Prepared").to be_a_directory
          expect(cask.staged_path/"Prepared/touched").to exist
          expect(cask.staged_path/"Prepared/moved").to exist
          expect(cask.staged_path/"PreparedLink").to be_a_symlink
        end
      end
    end

    context "with legacy flight stanzas" do
      before do
        ENV["HOMEBREW_DEVELOPER"] = nil
        Homebrew.raise_deprecation_exceptions = false
      end

      include_examples "loads from API", "many-artifacts"
    end

    context "with a language stanza" do
      include_examples "loads from API", "with-languages"

      it "loads the selected language variation from both APIs" do
        config = Cask::Config.new(explicit: { languages: ["zh"] })
        casks = [api_loader.load(config:), internal_api_loader.load(config:)]

        expect(casks.map do |cask|
          [cask.language, cask.url.to_s, cask.sha256.to_s, cask.artifacts.first.to_args]
        end).to all(eq([
          "zh-CN",
          "file://#{TEST_FIXTURE_DIR}/cask/container.tar.gz",
          "fab685fabf73d5a9382581ce8698fce9408f5feaa49fa10d9bc6c510493300f5",
          ["Container.app"],
        ]))
      end
    end
  end
end
