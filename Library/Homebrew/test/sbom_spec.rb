# frozen_string_literal: true

require "sbom"

RSpec.describe SBOM, :needs_network do
  describe "#valid?" do
    it "returns true if a minimal SBOM is valid" do
      f = formula { url "foo-1.0" }
      sbom = described_class.create(f, Tab.new)
      expect(sbom).to be_valid
    end

    it "returns true if a maximal SBOM is valid" do
      f = formula do
        homepage "https://brew.sh"

        url "https://brew.sh/test-0.1.tbz"
        sha256 TEST_SHA256

        patch do
          url "patch_macos"
        end

        bottle do
          sha256 all:   "9befdad158e59763fb0622083974a6252878019702d8c961e1bec3a5f5305339"
        end

        # some random dependencies to test with
        depends_on "cmake" => :build
        depends_on "beanstalkd"

        uses_from_macos "python" => :build
        uses_from_macos "zlib"
      end

      beanstalkd = formula "beanstalkd" do
        url "one-1.1"

        bottle do
          sha256 all:   "ac4c0330b70dae06eaa8065bfbea78dda277699d1ae8002478017a1bd9cf1908"
        end
      end

      zlib = formula "zlib" do
        url "two-1.1"

        bottle do
          sha256 all:   "6a4642964fe5c4d1cc8cd3507541736d5b984e34a303a814ef550d4f2f8242f9"
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
      expect(Tab).to receive(:formula_runtime_deps_hash).and_return(runtime_deps_hash)
      tab = Tab.create(f, DevelopmentTools.default_compiler, :libcxx)

      expect(Formulary).to receive(:factory).with("beanstalkd").and_return(beanstalkd)
      expect(Formulary).to receive(:factory).with("zlib").and_return(zlib)

      sbom = described_class.create(f, tab)
      expect(sbom).to be_valid
    end
  end
end
