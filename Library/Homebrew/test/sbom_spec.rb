# typed: true
# frozen_string_literal: true

require "sbom"

RSpec.describe SBOM do
  describe "#schema_validation_errors" do
    subject(:sbom) { described_class.create(f, tab) }

    before { ENV.delete("HOMEBREW_ENFORCE_SBOM") }

    let(:f) do
      formula do
        T.bind(self, T.class_of(Formula))
        url "foo-1.0"
      end
    end
    let(:tab) { Tab.new }

    it "returns true if valid" do
      expect(sbom.schema_validation_errors).to be_empty
    end

    it "returns true if valid when bottling" do
      expect(sbom.schema_validation_errors(bottling: true)).to be_empty
    end

    context "with a maximal SBOM" do
      let(:f) do
        formula do
          T.bind(self, T.class_of(Formula))
          homepage "https://brew.sh"

          url "https://brew.sh/test-0.1.tbz"
          sha256 TEST_SHA256

          patch do
            url "patch_macos"
            sha256 TEST_SHA256
          end

          bottle do
            sha256 all: "9befdad158e59763fb0622083974a6252878019702d8c961e1bec3a5f5305339"
          end

          # some random dependencies to test with
          depends_on "cmake" => :build
          depends_on "beanstalkd"

          uses_from_macos "python" => :build
          uses_from_macos "zlib"
        end
      end
      let(:tab) do
        beanstalkd = formula "beanstalkd" do
          T.bind(self, T.class_of(Formula))
          url "one-1.1"

          bottle do
            sha256 all: "ac4c0330b70dae06eaa8065bfbea78dda277699d1ae8002478017a1bd9cf1908"
          end
        end

        zlib = formula "zlib" do
          T.bind(self, T.class_of(Formula))
          url "two-1.1"

          bottle do
            sha256 all: "6a4642964fe5c4d1cc8cd3507541736d5b984e34a303a814ef550d4f2f8242f9"
          end
        end

        runtime_dependencies = [beanstalkd, zlib]
        runtime_deps_hash = runtime_dependencies.map do |dep|
          {
            "full_name"         => dep.full_name,
            "version"           => dep.version.to_s,
            "revision"          => dep.revision,
            "pkg_version"       => dep.pkg_version.to_s,
            "declared_directly" => true,
          }
        end
        allow(Tab).to receive(:runtime_deps_hash).and_return(runtime_deps_hash)
        tab = Tab.create(f, DevelopmentTools.default_compiler, :libcxx)

        allow(Formulary).to receive(:factory).with("beanstalkd").and_return(beanstalkd)
        allow(Formulary).to receive(:factory).with("zlib").and_return(zlib)

        tab
      end

      it "returns true if valid" do
        expect(sbom.schema_validation_errors).to be_empty
      end

      it "returns true if valid when bottling" do
        expect(sbom.schema_validation_errors(bottling: true)).to be_empty
      end

      it "only emits relationships with defined SPDX IDs" do
        spdx = sbom.send(:to_spdx_sbom, bottling: false)
        spdx_ids = Set.new(["SPDXRef-DOCUMENT"] + spdx[:packages].map { |package| package[:SPDXID] } +
                           spdx[:files].map { |file| file[:SPDXID] })

        expect(spdx[:relationships].flat_map do |relation|
          [relation[:spdxElementId], relation[:relatedSpdxElement]]
        end).to all(satisfy { |spdx_id| spdx_ids.include?(spdx_id) })
      end

      it "emits external patches as packages" do
        spdx = sbom.send(:to_spdx_sbom, bottling: false)

        expect(spdx[:packages]).to include(
          hash_including(
            SPDXID:           "SPDXRef-Patch-formula_name-0",
            downloadLocation: "patch_macos",
            checksums:        [{ algorithm: "SHA256", checksumValue: TEST_SHA256 }],
          ),
        )
      end
    end

    context "with an invalid SBOM" do
      before do
        allow(sbom).to receive(:to_spdx_sbom).and_return({}) # fake an empty SBOM
      end

      it "returns false" do
        expect(sbom.schema_validation_errors).not_to be_empty
      end

      it "returns false when bottling" do
        expect(sbom.schema_validation_errors(bottling: true)).not_to be_empty
      end
    end
  end
end
