# frozen_string_literal: true

RSpec.describe "Internal Tap JSON -- Formula" do
  let(:internal_tap_json) { File.read(TEST_FIXTURE_DIR/"internal_tap_json/homebrew-core.json").chomp }
  let(:tap_git_head) { "9977471165641744a829d3e494fa563407503297" }

  context "when generating JSON", :needs_macos do
    before do
      cp_r(TEST_FIXTURE_DIR/"internal_tap_json/homebrew-core", Tap::TAP_DIRECTORY/"homebrew")

      # NOTE: Symlinks can't be copied recursively so we create them manually here.
      (Tap::TAP_DIRECTORY/"homebrew/homebrew-core").tap do |core_tap|
        mkdir(core_tap/"Aliases")
        ln_s(core_tap/"Formula/f/fennel.rb", core_tap/"Aliases/fennel-lang")
        ln_s(core_tap/"Formula/p/ponyc.rb", core_tap/"Aliases/ponyc-lang")
      end
    end

    it "creates the expected hash" do
      api_hash = CoreTap.instance.to_internal_api_hash
      api_hash["tap_git_head"] = tap_git_head # tricky to mock

      expect(JSON.pretty_generate(api_hash)).to eq(internal_tap_json)
    end
  end

  context "when loading JSON" do
    before do
      ENV["HOMEBREW_INTERNAL_JSON_V3"] = "1"
      ENV.delete("HOMEBREW_NO_INSTALL_FROM_API")

      allow(Homebrew::API).to receive(:fetch_json_api_file)
        .with("internal/v3/homebrew-core.jws.json")
        .and_return([JSON.parse(internal_tap_json), false])

      # `Tap.tap_migration_oldnames` looks for renames in every
      # tap so `CoreCaskTap.tap_migrations` gets called and tries to
      # fetch stuff from the API. This just avoids errors.
      allow(Homebrew::API).to receive(:fetch_json_api_file)
        .with("cask_tap_migrations.jws.json", anything)
        .and_return([{}, false])

      # To allow `formula_names.txt` to be written to the cache.
      (HOMEBREW_CACHE/"api").mkdir

      Homebrew::API::Formula.clear_cache
    end

    after do
      Homebrew::API::Formula.clear_cache
    end

    it "loads tap aliases" do
      expect(CoreTap.instance.alias_table).to eq({
        "fennel-lang" => "fennel",
        "ponyc-lang"  => "ponyc",
      })
    end

    it "loads formula renames" do
      expect(CoreTap.instance.formula_renames).to eq({
        "advancemenu" => "advancemame",
        "amtk"        => "libgedit-amtk",
        "annie"       => "lux",
        "antlr2"      => "antlr@2",
        "romanesco"   => "fennel",
      })
    end

    it "loads tap migrations" do
      expect(CoreTap.instance.tap_migrations).to eq({
        "adobe-air-sdk"          => "homebrew/cask",
        "android-ndk"            => "homebrew/cask",
        "android-platform-tools" => "homebrew/cask",
        "android-sdk"            => "homebrew/cask",
        "app-engine-go-32"       => "homebrew/cask/google-cloud-sdk",
      })
    end

    it "loads tap git head" do
      expect(Homebrew::API::Formula.tap_git_head)
        .to eq(tap_git_head)
    end

    context "when loading formulae" do
      let(:fennel_metadata) do
        {
          "dependencies"         => ["lua"],
          "desc"                 => "Lua Lisp Language",
          "full_name"            => "fennel",
          "homepage"             => "https://fennel-lang.org",
          "license"              => "MIT",
          "name"                 => "fennel",
          "ruby_source_path"     => "Formula/f/fennel.rb",
          "tap"                  => "homebrew/core",
          "tap_git_head"         => tap_git_head,
          "versions"             => { "bottle"=>true, "head"=>nil, "stable"=>"1.4.0" },
          "ruby_source_checksum" => {
            "sha256" => "5856e655fd1cea11496d67bc27fb14fee5cfbdea63c697c3773c7f247581197d",
          },
        }
      end

      let(:ponyc_metadata) do
        {
          "desc"                   => "Object-oriented, actor-model, capabilities-secure programming language",
          "full_name"              => "ponyc",
          "homepage"               => "https://www.ponylang.io/",
          "license"                => "BSD-2-Clause",
          "name"                   => "ponyc",
          "ruby_source_path"       => "Formula/p/ponyc.rb",
          "tap"                    => "homebrew/core",
          "tap_git_head"           => tap_git_head,
          # TODO: improve this API before we ship internal API v3 to users
          "uses_from_macos"        => [{ "llvm"=>[:build, :test] }, "zlib"],
          "uses_from_macos_bounds" => [{}, {}],
          "versions"               => { "bottle"=>true, "head"=>nil, "stable"=>"0.58.1" },
          "ruby_source_checksum"   => {
            "sha256" => "81d51c25d18710191beb62f9f380bae3d878aad815a65ec1ee2a3b132c1fadb3",
          },
        }
      end

      it "loads fennel" do
        fennel = Formulary.factory("fennel")
        expect(fennel.to_hash).to include(**fennel_metadata)
      end

      it "loads fennel from rename" do
        fennel = Formulary.factory("romanesco")
        expect(fennel.to_hash).to include(**fennel_metadata)
      end

      it "loads fennel from alias" do
        fennel = Formulary.factory("fennel-lang")
        expect(fennel.to_hash).to include(**fennel_metadata)
      end

      it "loads ponyc" do
        ponyc = Formulary.factory("ponyc")
        expect(ponyc.to_hash).to include(**ponyc_metadata)
      end

      it "loads ponyc from alias" do
        ponyc = Formulary.factory("ponyc-lang")
        expect(ponyc.to_hash).to include(**ponyc_metadata)
      end
    end
  end
end
