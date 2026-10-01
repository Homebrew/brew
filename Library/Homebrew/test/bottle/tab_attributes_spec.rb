# typed: true
# frozen_string_literal: true

require "bottle"
require "bottle_specification"

RSpec.describe Bottle do
  describe "#tab_attributes" do
    let(:bottle) do
      bottle_spec = BottleSpecification.new
      bottle_spec.root_url(HOMEBREW_BOTTLE_DEFAULT_DOMAIN)
      bottle_spec.sha256(cellar: :any_skip_relocation, arm64_golden_gate: "deadbeef" * 8)
      described_class.new(nil, bottle_spec, Utils::Bottles::Tag.from_symbol(:arm64_golden_gate),
                          name: "pkgconf", pkg_version: PkgVersion.new(Version.new("1.2.3"), 0))
    end
    let(:manifest_resource) { bottle.github_packages_manifest_resource || raise("Expected a bottle manifest") }
    let(:manifest) do
      {
        "manifests" => [{
          "annotations" => {
            "org.opencontainers.image.ref.name" => "1.2.3.arm64_golden_gate",
            "sh.brew.bottle.digest"             => "deadbeef" * 8,
            "sh.brew.tab"                       => { "built_on" => { "os_version" => "macOS 27.0" } }.to_json,
          },
        }],
      }
    end

    before do
      manifest_resource.cached_download.dirname.mkpath
      manifest_resource.cached_download.write({ "manifests" => [{ "annotations" => {} }] }.to_json)
      allow(manifest_resource.downloader).to receive(:fetch) do
        manifest_resource.cached_download.write(manifest.to_json) unless manifest_resource.downloaded?
      end
    end

    it "refreshes cached metadata missing the bottle checksum before checking compatibility" do
      expect([bottle.compatible_locations?, bottle.tab_attributes])
        .to eq([true, { "built_on" => { "os_version" => "macOS 27.0" } }])
    end

    it "does not keep retrying invalid metadata across repeated accesses", timeout: 5 do
      manifest.fetch("manifests").fetch(0).fetch("annotations").delete("sh.brew.bottle.digest")
      expect(manifest_resource).to receive(:clear_cache).once.and_call_original

      bottle.compatible_locations?

      expect { bottle.tab_attributes }.to raise_error(Resource::BottleManifest::Error,
                                                      "Couldn't find manifest matching bottle checksum.")
    end

    it "does not fetch metadata that is already valid" do
      manifest_resource.cached_download.write(manifest.to_json)
      expect(manifest_resource.downloader).not_to receive(:fetch)

      bottle.tab_attributes
    end

    it "keeps metadata fetching lazy when nothing is cached" do
      manifest_resource.clear_cache
      expect(manifest_resource.downloader).not_to receive(:fetch)

      expect(bottle.tab_attributes).to eq({})
    end
  end
end
