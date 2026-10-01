# typed: true
# frozen_string_literal: true

require "sbom"
require "json_schemer"

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

    it "omits unavailable source checksums" do
      expect(sbom.to_spdx_sbom[:packages]).to include(hash_including(name: f.name, checksums: []))
    end

    context "with an empty source checksum" do
      let(:f) do
        formula do
          T.bind(self, T.class_of(Formula))
          url "foo-1.0"
          sha256 ""
        end
      end

      it "generates a valid SBOM" do
        expect(sbom.schema_validation_errors).to be_empty
      end
    end

    context "with an empty patch checksum" do
      let(:f) do
        formula do
          T.bind(self, T.class_of(Formula))
          url "foo-1.0"
          sha256 TEST_SHA256

          patch do
            url "patch_macos"
            sha256 ""
          end
        end
      end

      it "generates a valid SBOM" do
        expect(sbom.schema_validation_errors).to be_empty
      end
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
            root_url "https://brew.sh/bottles"
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

      context "with punctuation in names and a revised dependency" do
        before do
          allow(f).to receive(:name).and_return("gcc@13+foo_bar.40.baz")
          allow(tab).to receive(:runtime_dependencies).and_return([
            { "full_name" => "beanstalkd", "pkg_version" => "1.1_1" },
          ])
        end

        it "generates a valid source-install SBOM" do
          expect(sbom.schema_validation_errors).to be_empty
        end

        it "preserves names and versions in package metadata" do
          expect(sbom.to_spdx_sbom[:packages]).to include(
            hash_including(name: "gcc@13+foo_bar.40.baz", versionInfo: "0.1"),
            hash_including(name: "beanstalkd", versionInfo: "1.1_1"),
          )
        end

        it "merges a valid bottle supplement with resolvable relationships" do
          spdxfile = mktmpdir/SBOM::FILENAME
          spdxfile.write(JSON.pretty_generate(sbom.to_spdx_sbom(bottling: true)))
          annotation = described_class.github_packages_sbom_supplement_annotation(
            sbom.to_spdx_supplement,
            formula_full_name: f.full_name,
            formula_name:      f.name,
            version:           f.version,
            tar_gz_sha256:     TEST_SHA256,
            root_url:          "https://ghcr.io/v2/homebrew/core",
            license:           "MIT",
            created_date:      "2026-05-10T00:00:00Z",
          )
          raise "missing annotation" if annotation.nil?

          described_class.update_pour_metadata(spdxfile, homebrew_version: "1.2.3", time: 1_720_189_863,
                                                        supplement: JSON.parse(annotation))
          spdx = JSON.parse(spdxfile.read)
          spdx_ids = Set.new([spdx.fetch("SPDXID")] +
                             spdx.fetch("packages").map { |package| package.fetch("SPDXID") } +
                             spdx.fetch("files").map { |file| file.fetch("SPDXID") })

          expect(
            validation_errors: JSONSchemer.schema(described_class.schema).validate(spdx).map do |error|
              error.fetch("error")
            end,
            unresolved_ids:    spdx.fetch("relationships").flat_map do |relation|
              [relation.fetch("spdxElementId"), relation.fetch("relatedSpdxElement")]
              .reject { |spdx_id| spdx_ids.include?(spdx_id) }
            end,
          ).to eq(validation_errors: [], unresolved_ids: [])
        end
      end

      it "only emits relationships with defined SPDX IDs" do
        spdx = sbom.to_spdx_sbom
        spdx_ids = Set.new(["SPDXRef-DOCUMENT"] + spdx[:packages].map { |package| package[:SPDXID] } +
                           spdx[:files].map { |file| file[:SPDXID] })

        expect(spdx[:relationships].flat_map do |relation|
          [relation[:spdxElementId], relation[:relatedSpdxElement]]
        end).to all(satisfy { |spdx_id| spdx_ids.include?(spdx_id) })
      end

      it "emits external patches as packages" do
        spdx = sbom.to_spdx_sbom

        expect(spdx[:packages]).to include(
          hash_including(
            SPDXID:           "SPDXRef-Patch-formula.5f.name-0",
            downloadLocation: "patch_macos",
            checksums:        [{ algorithm: "SHA256", checksumValue: TEST_SHA256 }],
          ),
        )
      end

      it "emits reproducible creation info" do
        expect(sbom.to_spdx_sbom[:creationInfo]).to eq(
          created:  Time.at(tab.source_modified_time.to_i).utc.iso8601,
          creators: ["Tool: https://github.com/Homebrew/brew"],
        )
      end

      it "emits bottle metadata when bottle filenames are available" do
        expect(sbom.to_spdx_sbom[:packages]).to include(
          hash_including(
            SPDXID:           "SPDXRef-Bottle-formula.5f.name",
            downloadLocation: "https://brew.sh/bottles/formula_name-0.1.all.bottle.tar.gz",
            checksums:        [{
              algorithm:     "SHA256",
              checksumValue: "9befdad158e59763fb0622083974a6252878019702d8c961e1bec3a5f5305339",
            }],
          ),
        )
      end

      it "emits pkg:brew purl in externalRefs for source archive package" do
        expect(sbom.to_spdx_sbom[:packages]).to include(
          hash_including(
            SPDXID:       "SPDXRef-Archive-formula.5f.name-src",
            externalRefs: [{
              referenceCategory: "PACKAGE-MANAGER",
              referenceLocator:  "pkg:brew/homebrew/core/formula_name@0.1",
              referenceType:     "purl",
            }],
          ),
        )
      end

      # NOTE: We don't package `requests`. This is here for testing upstream purl identification.
      context "with a PyPI source URL" do
        let(:f) do
          formula do
            T.bind(self, T.class_of(Formula))
            homepage "https://brew.sh"

            url "https://files.pythonhosted.org/packages/d6/5d/47f0d014022a106f235948924b17f54c9356a815a51086082eeef7f3747d/requests-2.25.1.tar.gz"
            sha256 TEST_SHA256

            bottle do
              root_url "https://brew.sh/bottles"
              sha256 all: "9befdad158e59763fb0622083974a6252878019702d8c961e1bec3a5f5305339"
            end
          end
        end

        it "emits both pkg:brew and upstream purl in externalRefs for source archive package" do
          expect(sbom.to_spdx_sbom[:packages]).to include(
            hash_including(
              SPDXID:       "SPDXRef-Archive-formula.5f.name-src",
              externalRefs: [{
                referenceCategory: "PACKAGE-MANAGER",
                referenceLocator:  "pkg:brew/homebrew/core/formula_name@2.25.1",
                referenceType:     "purl",
              }, {
                referenceCategory: "PACKAGE-MANAGER",
                referenceLocator:  "pkg:pypi/requests@2.25.1",
                referenceType:     "purl",
              }],
            ),
          )
        end
      end

      it "omits host-specific packages when bottling" do
        spdx = sbom.to_spdx_sbom(bottling: true)
        package_ids = spdx[:packages].map { |package| package[:SPDXID] }

        expect(package_ids).to contain_exactly(
          "SPDXRef-Archive-formula.5f.name-src",
          "SPDXRef-Patch-formula.5f.name-0",
        )
        expect(spdx[:relationships].flat_map do |relation|
          [relation[:spdxElementId], relation[:relatedSpdxElement]]
        end).to all(
          satisfy do |spdx_id|
            package_ids.include?(spdx_id) || spdx_id == "SPDXRef-File-formula.5f.name"
          end,
        )
      end

      it "emits host-specific packages in a pour supplement" do
        package_ids = sbom.to_spdx_supplement.fetch("packages").map { |package| package.fetch(:SPDXID) }

        expect(package_ids).to include(
          "SPDXRef-Compiler",
          "SPDXRef-Stdlib",
          "SPDXRef-Package-SPDXRef-beanstalkd-1.2e.1",
          "SPDXRef-Package-SPDXRef-zlib-1.2e.1",
        )
        expect(package_ids).not_to include(
          "SPDXRef-Archive-formula.5f.name-src",
          "SPDXRef-Patch-formula.5f.name-0",
        )
      end

      it "builds a GitHub Packages manifest annotation supplement" do
        annotation = described_class.github_packages_sbom_supplement_annotation(
          {
            "documentDescribes" => ["SPDXRef-Compiler"],
            "packages"          => [{ "SPDXID" => "SPDXRef-Compiler" }],
            "relationships"     => [],
          },
          formula_full_name: "formula_name",
          formula_name:      "formula_name",
          version:           Version.new("0.1"),
          tar_gz_sha256:     TEST_SHA256,
          root_url:          "https://ghcr.io/v2/homebrew/core",
          license:           "MIT",
          created_date:      "2026-05-10T00:00:00Z",
        )
        raise "missing annotation" if annotation.nil?

        supplement = JSON.parse(annotation)
        bottle_package = supplement.fetch("packages").find do |package|
          package.fetch("SPDXID") == "SPDXRef-Bottle-formula.5f.name"
        end

        expect(bottle_package).to include(
          "checksums"        => [{ "algorithm" => "SHA256", "checksumValue" => TEST_SHA256 }],
          "downloadLocation" => "https://ghcr.io/v2/homebrew/core/formula_name/blobs/sha256:#{TEST_SHA256}",
        )
      end

      it "updates only pour-time creation metadata" do
        spdxfile = mktmpdir/SBOM::FILENAME
        spdxfile.write(JSON.pretty_generate(sbom.to_spdx_sbom))
        original_spdx = JSON.parse(spdxfile.read)

        described_class.update_pour_metadata(spdxfile, homebrew_version: "1.2.3", time: 1_720_189_863)

        updated_spdx = JSON.parse(spdxfile.read)
        expect(updated_spdx.fetch("creationInfo")).to eq(
          "created"  => "2024-07-05T14:31:03Z",
          "creators" => ["Tool: https://github.com/Homebrew/brew@1.2.3"],
        )
        expect(updated_spdx.except("creationInfo")).to eq(original_spdx.except("creationInfo"))
      end

      it "merges pour supplements without validating full SBOMs" do
        spdxfile = mktmpdir/SBOM::FILENAME
        spdxfile.write(JSON.pretty_generate(
                         "creationInfo"      => {},
                         "documentDescribes" => [],
                         "packages"          => [],
                         "relationships"     => [],
                       ))
        supplement = {
          "documentDescribes" => ["SPDXRef-Compiler"],
          "packages"          => [{ "SPDXID" => "SPDXRef-Compiler" }],
          "relationships"     => [{ "spdxElementId" => "SPDXRef-Compiler" }],
        }

        described_class.update_pour_metadata(spdxfile, homebrew_version: "1.2.3", time: 1_720_189_863,
                                                       supplement:)

        updated_spdx = JSON.parse(spdxfile.read)
        expect(updated_spdx.fetch("documentDescribes")).to eq(supplement.fetch("documentDescribes"))
        expect(updated_spdx.fetch("packages")).to eq(supplement.fetch("packages"))
        expect(updated_spdx.fetch("relationships")).to eq(supplement.fetch("relationships"))
      end

      it "skips malformed pour metadata SBOMs" do
        spdxfile = mktmpdir/SBOM::FILENAME
        spdxfile.write("{")

        expect do
          described_class.update_pour_metadata(spdxfile, homebrew_version: "1.2.3", time: 1_720_189_863)
        end.not_to raise_error
        expect(spdxfile.read).to eq("{")
      end

      it "skips pour metadata SBOMs without creation info objects" do
        spdxfile = mktmpdir/SBOM::FILENAME
        spdxfile.write(JSON.pretty_generate("creationInfo" => []))
        original_spdx = spdxfile.read

        expect do
          described_class.update_pour_metadata(spdxfile, homebrew_version: "1.2.3", time: 1_720_189_863)
        end.not_to raise_error
        expect(spdxfile.read).to eq(original_spdx)
      end
    end

    context "with an invalid SBOM" do
      before do
        allow(sbom).to receive(:to_spdx_sbom).and_return({}) # fake an empty SBOM
      end

      it "returns false" do
        expect(sbom.schema_validation_errors).not_to be_empty
      end
    end
  end

  describe ".github_packages_sbom_supplement_annotation" do
    test_each([false, true]) do |tagged|
      it "preserves the bottle IDs referenced by stored supplements (tagged: #{tagged})" do
        bottle_ids = %w[SPDXRef-Bottle-openssl@3 SPDXRef-Bottle-openssl.40.3]
        supplements = bottle_ids.map do |bottle_id|
          {
            "documentDescribes" => ["SPDXRef-Stdlib"],
            "packages"          => [{ "SPDXID" => "SPDXRef-Stdlib" }],
            "relationships"     => [{
              "spdxElementId"      => "SPDXRef-Stdlib",
              "relationshipType"   => "DEPENDENCY_OF",
              "relatedSpdxElement" => bottle_id,
            }],
          }
        end
        supplement = if tagged
          { "tags" => { "arm64_tahoe" => supplements.fetch(0), "sonoma" => supplements.fetch(1) } }
        else
          supplements.fetch(0)
        end
        annotation = described_class.github_packages_sbom_supplement_annotation(
          supplement,
          formula_full_name: "openssl@3",
          formula_name:      "openssl@3",
          version:           Version.new("3.5.0"),
          tar_gz_sha256:     TEST_SHA256,
          root_url:          "https://ghcr.io/v2/homebrew/core",
          license:           "Apache-2.0",
          created_date:      "2026-09-29T00:00:00Z",
        )
        raise "missing annotation" if annotation.nil?

        parsed = JSON.parse(annotation)
        results = tagged ? parsed.fetch("tags").values : [parsed]

        expect(results.map do |result|
          [result.fetch("packages").last.fetch("SPDXID"),
           result.fetch("documentDescribes").last,
           result.fetch("relationships").first.fetch("relatedSpdxElement")]
        end).to eq(bottle_ids.first(tagged ? 2 : 1).map { |id| [id, id, id] })
      end
    end
  end

  describe ".spdx_id" do
    it "escapes punctuation using SPDX identifier characters" do
      expect(%w[foo gcc@13 gtk+ foo_bar foo.40.bar foo/bar].map do |name|
        described_class.spdx_id("Archive-#{name}-src")
      end).to eq(%w[
        SPDXRef-Archive-foo-src
        SPDXRef-Archive-gcc.40.13-src
        SPDXRef-Archive-gtk.2b.-src
        SPDXRef-Archive-foo.5f.bar-src
        SPDXRef-Archive-foo.2e.40.2e.bar-src
        SPDXRef-Archive-foo.2f.bar-src
      ])
    end

    it "keeps names and literal escape sequences distinct" do
      names = %w[gcc@13 gcc.40.13 gcc-13 foo_bar foo.5f.bar gtk+ gtk.2b. foo/bar foo-bar]

      expect(names.map { |name| described_class.spdx_id("Archive-#{name}-src") }.uniq.length).to eq(names.length)
    end
  end

  describe ".brew_purl" do
    it "percent-encodes @ in versioned formula names" do
      expect(described_class.brew_purl("homebrew/core/python@3.12", "3.12.8"))
        .to eq("pkg:brew/homebrew/core/python%403.12@3.12.8")
    end

    it "omits the namespace for a bare formula name" do
      expect(described_class.brew_purl("zlib", "1.3.1")).to eq("pkg:brew/zlib@1.3.1")
    end

    it "omits the version segment when version is nil" do
      expect(described_class.brew_purl("homebrew/core/foo", nil)).to eq("pkg:brew/homebrew/core/foo")
    end
  end
end
