# frozen_string_literal: true

RSpec.describe Cask::CaskLoader::FromAPILoader, :cask do
  shared_context "with API setup" do |local_token|
    let(:api_token) { "#{local_token}-api" }
    let(:cask_from_source) { Cask::CaskLoader.load(local_token) }
    let(:cask_json) do
      hash = cask_from_source.to_hash_with_variations
      json = JSON.pretty_generate(hash)
      JSON.parse(json)
    end
    let(:casks_from_api_hash) { { api_token => cask_json.except("token") } }
    let(:api_loader) { described_class.new(api_token, from_json: cask_json) }

    before do
      allow(Homebrew::API::Cask)
        .to receive_messages(all_casks: casks_from_api_hash, all_renames: {})

      # The call to `Cask::CaskLoader.load` above sets the Tap cache prematurely.
      Tap.clear_cache
    end
  end

  describe ".try_new" do
    include_context "with API setup", "test-opera"

    context "when not using the API", :no_api do
      it "returns false" do
        expect(described_class.try_new(api_token)).to be_nil
      end
    end

    context "when using the API" do
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

      it "returns nil for full name with invalid tap" do
        expect(described_class.try_new("homebrew/foo/#{api_token}")).to be_nil
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
          expect(loader.token).to eq api_token
          expect(loader.path).not_to exist
        end

        it "returns the tap migration rename by old full name" do
          old_token = "#{api_token}-old"
          (foo_tap.path/"tap_migrations.json").write <<~JSON
            { "#{old_token}": "homebrew/cask/#{api_token}" }
          JSON

          loader = Cask::CaskLoader::FromTapLoader.try_new("#{foo_tap}/#{old_token}")
          expect(loader).to be_a(described_class)
          expect(loader.token).to eq api_token
          expect(loader.path).not_to exist
        end
      end
    end
  end

  describe "#load" do
    shared_examples "loads from API" do |cask_token, caskfile_only:|
      include_context "with API setup", cask_token
      let(:cask_from_api) { api_loader.load(config: nil) }

      it "loads from JSON API" do
        expect(cask_from_api).to be_a(Cask::Cask)
        expect(cask_from_api.token).to eq(api_token)
        expect(cask_from_api.loaded_from_api?).to be(true)
        expect(cask_from_api.caskfile_only?).to be(caskfile_only)
        expect(cask_from_api.sourcefile_path).to eq(Homebrew::API::Cask.cached_json_file_path)
      end
    end

    context "with a binary stanza" do
      include_examples "loads from API", "with-binary", caskfile_only: false
    end

    context "with cask dependencies" do
      include_examples "loads from API", "with-depends-on-cask-multiple", caskfile_only: false
    end

    context "with formula dependencies" do
      include_examples "loads from API", "with-depends-on-formula-multiple", caskfile_only: false
    end

    context "with macos dependencies" do
      include_examples "loads from API", "with-depends-on-macos-array", caskfile_only: false
    end

    context "with an installer stanza" do
      include_examples "loads from API", "with-installer-script", caskfile_only: false
    end

    context "with uninstall stanzas" do
      include_examples "loads from API", "with-uninstall-multi", caskfile_only: false
    end

    context "with a zap stanza" do
      include_examples "loads from API", "with-zap", caskfile_only: false
    end

    context "with a preflight stanza" do
      include_examples "loads from API", "with-preflight", caskfile_only: true
    end

    context "with an uninstall-preflight stanza" do
      include_examples "loads from API", "with-uninstall-preflight", caskfile_only: true
    end

    context "with a postflight stanza" do
      include_examples "loads from API", "with-postflight", caskfile_only: true
    end

    context "with an uninstall-postflight stanza" do
      include_examples "loads from API", "with-uninstall-postflight", caskfile_only: true
    end

    context "with a language stanza" do
      include_examples "loads from API", "with-languages", caskfile_only: true
    end
  end
end
