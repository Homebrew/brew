# typed: strict
# frozen_string_literal: true

require "bottle_specification"
require "test/support/fixtures/testball_bottle"

RSpec.describe Bottle do
  sig { returns(UnpackStrategy::Tar) }
  def bottle_extractor
    instance_double(UnpackStrategy::Tar).tap do |strategy|
      allow(strategy).to receive(:extract_nestedly) { |to:, **| (to/"foo/1.2.3").mkpath }
    end
  end

  describe "#compatible_locations?" do
    it "fetches tab metadata before rejecting a padded bottle" do
      tag = Utils::Bottles::Tag.from_symbol(:arm64_tahoe)
      bottle_spec = BottleSpecification.new
      bottle_spec.sha256(tag.to_sym => "deadbeef" * 8)
      bottle = described_class.new(TestballBottle.new, bottle_spec, tag)
      stub_const("HOMEBREW_PREFIX", Pathname("/short"))
      stub_const("HOMEBREW_CELLAR", HOMEBREW_PREFIX/"Cellar")
      allow(bottle).to receive(:tab_attributes).and_return(
        {},
        { "built_prefix" => tag.padded_prefix, "padded_prefix" => true },
      )
      expect(bottle).to receive(:fetch_tab).with(quiet: true)

      expect(bottle.compatible_locations?).to be true
    end
  end

  describe "#filename" do
    it "renders the bottle filename" do
      bottle_spec = BottleSpecification.new
      bottle_spec.sha256(arm64_big_sur: "deadbeef" * 8)
      tag = Utils::Bottles::Tag.from_symbol :arm64_big_sur
      bottle = described_class.new(TestballBottle.new, bottle_spec, tag)

      expect(bottle.filename.to_s).to eq("testball_bottle--0.1.arm64_big_sur.bottle.tar.gz")
    end
  end

  describe "#downloaded_and_valid?" do
    it "trusts cached immutable GitHub Packages bottle blobs matching the expected checksum" do
      tag = Utils::Bottles::Tag.from_symbol(:arm64_big_sur)
      bottle_spec = BottleSpecification.new
      bottle_spec.root_url(HOMEBREW_BOTTLE_DEFAULT_DOMAIN)
      bottle_spec.sha256(
        cellar:        :any_skip_relocation,
        arm64_big_sur: "d7b9f4e8bf83608b71fe958a99f19f2e5e68bb2582965d32e41759c24f1aef97",
      )
      bottle = described_class.new(nil, bottle_spec, tag,
                                   name: "foo", pkg_version: PkgVersion.new(Version.new("1.2.3"), 0))

      bottle.cached_download.dirname.mkpath
      bottle.cached_download.write("cached")

      expect(bottle.resource).not_to receive(:verify_download_integrity)

      expect(bottle.downloaded_and_valid?).to be true
    end
  end

  describe "#stage" do
    around do |example|
      Dir.mktmpdir("bottle", HOMEBREW_TEMP) { |destination| Dir.chdir(destination) { example.run } }
    end

    it "rejects a bottle containing a neighbouring keg" do
      source = mktmpdir
      (source/"testball_bottle/0.1").mkpath
      (source/"neighbour/1").mkpath
      archive = mktmpdir/"bottle.tar.gz"
      system "tar", "-czf", archive.to_s, "-C", source.to_s, "testball_bottle", "neighbour"
      bottle_spec = BottleSpecification.new
      bottle_spec.sha256(arm64_big_sur: Digest::SHA256.file(archive).hexdigest)
      bottle = described_class.new(TestballBottle.new, bottle_spec, Utils::Bottles::Tag.from_symbol(:arm64_big_sur))
      bottle.cached_download.dirname.mkpath
      FileUtils.cp(archive, bottle.cached_download)

      expect { bottle.stage }.to raise_error(/Unexpected bottle contents/)
    ensure
      bottle&.clear_cache
    end

    it "verifies a cached bottle against its checksum and refetches on mismatch", :aggregate_failures do
      valid_content = "valid"
      bottle_spec = BottleSpecification.new
      bottle_spec.root_url(HOMEBREW_BOTTLE_DEFAULT_DOMAIN)
      bottle_spec.sha256(cellar: :any_skip_relocation, arm64_big_sur: Digest::SHA256.hexdigest(valid_content))
      bottle = described_class.new(nil, bottle_spec, Utils::Bottles::Tag.from_symbol(:arm64_big_sur),
                                   name: "foo", pkg_version: PkgVersion.new(Version.new("1.2.3"), 0))
      expect(bottle.downloader).not_to receive(:curl_headers)
      bottle.cached_download.dirname.mkpath
      bottle.cached_download.write("corrupt")
      allow(UnpackStrategy).to receive(:detect)
        .and_return(bottle_extractor)
      expect(bottle).to receive(:fetch) { bottle.cached_download.write(valid_content) }
      # The mismatched verification has already hashed the corrupt file, so
      # discarding it must not hash it a second time: once for the corrupt
      # file and once for the fresh download.
      expect(Digest::SHA256).to receive(:file).twice.and_call_original

      expect { bottle.stage }.to output(/Removing corrupt cached download/).to_stderr
    end

    it "removes the cached bottle when the refetched download also fails verification", :aggregate_failures do
      valid_content = "valid"
      bottle_spec = BottleSpecification.new
      bottle_spec.root_url(HOMEBREW_BOTTLE_DEFAULT_DOMAIN)
      expected_checksum = Checksum.new(Digest::SHA256.hexdigest(valid_content))
      bottle_spec.sha256(cellar: :any_skip_relocation, arm64_big_sur: expected_checksum.hexdigest)
      bottle = described_class.new(nil, bottle_spec, Utils::Bottles::Tag.from_symbol(:arm64_big_sur),
                                   name: "foo", pkg_version: PkgVersion.new(Version.new("1.2.3"), 0))
      expect(bottle.downloader).not_to receive(:curl_headers)
      bottle.cached_download.dirname.mkpath
      bottle.cached_download.write("corrupt")
      expect(bottle).to receive(:fetch) do
        bottle.cached_download.write("still corrupt")
        raise ChecksumMismatchError.new(bottle.cached_download, expected_checksum,
                                        Checksum.new(Digest::SHA256.hexdigest("still corrupt")))
      end

      expect do
        expect { bottle.stage }.to raise_error(ChecksumMismatchError)
      end.to output(/Removing corrupt cached download/).to_stderr
      expect(bottle.cached_download).not_to exist
    end

    it "does not extract a cached bottle until its checksum is verified" do
      valid_content = "valid"
      bottle_spec = BottleSpecification.new
      bottle_spec.root_url(HOMEBREW_BOTTLE_DEFAULT_DOMAIN)
      bottle_spec.sha256(cellar: :any_skip_relocation, arm64_big_sur: Digest::SHA256.hexdigest(valid_content))
      bottle = described_class.new(nil, bottle_spec, Utils::Bottles::Tag.from_symbol(:arm64_big_sur),
                                   name: "foo", pkg_version: PkgVersion.new(Version.new("1.2.3"), 0))
      bottle.cached_download.dirname.mkpath
      bottle.cached_download.write("mismatched")
      staged_content = []
      allow(UnpackStrategy).to receive(:detect) do |path, **|
        staged_content << path.read
        bottle_extractor
      end
      expect(bottle).to receive(:fetch) do
        bottle.cached_download.write(valid_content)
        bottle.verify_download_integrity(bottle.cached_download)
      end

      bottle.stage

      expect(staged_content).to eq([valid_content])
    ensure
      bottle&.clear_cache
    end

    it "extracts a verified private copy from the temporary Cellar" do
      valid_content = "valid"
      bottle_spec = BottleSpecification.new
      bottle_spec.root_url(HOMEBREW_BOTTLE_DEFAULT_DOMAIN)
      bottle_spec.sha256(cellar: :any_skip_relocation, arm64_big_sur: Digest::SHA256.hexdigest(valid_content))
      bottle = described_class.new(nil, bottle_spec, Utils::Bottles::Tag.from_symbol(:arm64_big_sur),
                                   name: "foo", pkg_version: PkgVersion.new(Version.new("1.2.3"), 0))
      bottle.cached_download.dirname.mkpath
      bottle.cached_download.write(valid_content)
      extracted = []
      allow(UnpackStrategy).to receive(:detect) do |path, **|
        extracted << [path.ascend.include?(HOMEBREW_TEMP_CELLAR), path == bottle.cached_download, path.read]
        bottle_extractor
      end

      bottle.stage

      expect(extracted).to eq([[true, false, valid_content]])
    ensure
      bottle&.clear_cache
    end
  end

  test_each([false, true]) do |queue|
    it "keeps bottle extraction intermediates in the temporary Cellar with queue=#{queue}" do
      archive = TEST_FIXTURE_DIR/"bottles/testball_bottle-0.1.yosemite.bottle.tar.gz"
      bottle_spec = BottleSpecification.new
      bottle_spec.sha256(cellar: :any_skip_relocation, arm64_big_sur: Digest::SHA256.file(archive).hexdigest)
      bottle = described_class.new(TestballBottle.new, bottle_spec, Utils::Bottles::Tag.from_symbol(:arm64_big_sur))
      bottle.cached_download.dirname.mkpath
      FileUtils.cp(archive, bottle.cached_download)
      destination = mktmpdir
      temporary_parents = []
      allow(Dir).to receive(:mktmpdir).and_wrap_original do |original, *args, &block|
        if args.first.to_s.start_with?("homebrew-unpack", "homebrew-tar")
          temporary_parents << Pathname(args.fetch(1))
        end
        original.call(*args, &block)
      end

      if queue
        bottle.stage_from_download_queue(bottle.cached_download, pour: true)
        keg = bottle.staged_path_from_download_queue
      else
        destination.cd { bottle.stage }
        keg = destination/"testball_bottle/0.1"
      end

      expect(
        protected_parents: temporary_parents.map { |parent| parent.ascend.include?(HOMEBREW_TEMP_CELLAR) },
        extracted:         (keg/"libexec/NOOP").file?,
        queued:            bottle.staged_from_download_queue?,
        snapshots:         HOMEBREW_TEMP_CELLAR.glob("verify-*"),
      ).to eq(protected_parents: [true, true], extracted: true, queued: queue, snapshots: [])
    ensure
      bottle&.purge_staged_from_download_queue
      bottle&.clear_cache
    end
  end

  describe "#stage_from_download_queue" do
    sig { params(checksum: String, content: String).returns(Bottle) }
    def cached_bottle(checksum, content)
      bottle_spec = BottleSpecification.new
      bottle_spec.root_url(HOMEBREW_BOTTLE_DEFAULT_DOMAIN)
      bottle_spec.sha256(cellar: :any_skip_relocation, arm64_big_sur: checksum)
      bottle = described_class.new(nil, bottle_spec, Utils::Bottles::Tag.from_symbol(:arm64_big_sur),
                                   name: "foo", pkg_version: PkgVersion.new(Version.new("1.2.3"), 0))
      bottle.cached_download.dirname.mkpath
      bottle.cached_download.write(content)
      bottle
    end

    it "replaces an existing marker and keg instead of trusting them" do
      staged_path = T.let(nil, T.nilable(Pathname))
      marker = T.let(nil, T.nilable(Pathname))
      valid_content = "valid"
      bottle = cached_bottle(Digest::SHA256.hexdigest(valid_content), valid_content)
      staged_path = bottle.staged_path_from_download_queue
      marker = bottle.staged_path_from_download_queue_marker
      staged_path.mkpath
      (staged_path/"planted").write("planted")
      FileUtils.ln_s(staged_path, marker)
      allow(UnpackStrategy).to receive(:detect).and_return(bottle_extractor)

      bottle.stage_from_download_queue(bottle.cached_download, pour: true)

      expect([(staged_path/"planted").exist?, marker.symlink? && marker.readlink == staged_path]).to eq([false, true])
    ensure
      FileUtils.rm_f(marker) if marker
      FileUtils.rm_r(staged_path) if staged_path&.directory?
      bottle&.clear_cache
    end

    it "accepts only a marker pointing at a real keg directory" do
      keg = T.let(nil, T.nilable(Pathname))
      marker = T.let(nil, T.nilable(Pathname))
      bottle = cached_bottle("0" * 64, "cached")
      keg = bottle.staged_path_from_download_queue
      marker = bottle.staged_path_from_download_queue_marker
      results = []
      keg.mkpath
      FileUtils.ln_s(keg, marker)
      results << bottle.staged_from_download_queue?
      FileUtils.rm(marker)
      FileUtils.ln_s(mktmpdir, marker)
      results << bottle.staged_from_download_queue?
      FileUtils.rm(marker)
      FileUtils.rm_r(keg)
      FileUtils.ln_s(mktmpdir, keg)
      FileUtils.ln_s(keg, marker)
      results << bottle.staged_from_download_queue?

      expect(results).to eq([true, false, false])
    ensure
      FileUtils.rm_f(marker) if marker
      FileUtils.rm_rf(keg) if keg
      bottle&.clear_cache
    end

    it "does not queue-stage a cached bottle until its checksum is verified" do
      valid_content = "valid"
      bottle = cached_bottle(Digest::SHA256.hexdigest(valid_content), "mismatched")
      unpack_strategy = bottle_extractor
      staged_content = []
      allow(UnpackStrategy).to receive(:detect) do |path, **|
        staged_content << path.read
        unpack_strategy
      end
      expect(bottle).to receive(:fetch) do
        bottle.cached_download.write(valid_content)
        bottle.verify_download_integrity(bottle.cached_download)
      end

      bottle.stage_from_download_queue(bottle.cached_download, pour: true)

      expect(staged_content).to eq([valid_content])
    ensure
      bottle&.clear_cache
    end

    it "downloads a corrupt cached bottle again and extracts it", :aggregate_failures do
      valid_content = "valid"
      bottle = cached_bottle(Digest::SHA256.hexdigest(valid_content), "corrupt")
      unpack_strategy = bottle_extractor
      extractions = 0
      allow(UnpackStrategy).to receive(:detect) do
        extractions += 1
        unpack_strategy
      end

      expect(bottle).to receive(:fetch) do
        bottle.cached_download.write(valid_content)
        bottle.verify_download_integrity(bottle.cached_download)
      end

      expect { bottle.stage_from_download_queue(bottle.cached_download, pour: true) }
        .to output(/Removing corrupt cached download/).to_stderr
      expect(extractions).to eq(1)
    end

    it "raises without extracting when the refetched download also fails verification", :aggregate_failures do
      expected_checksum = Checksum.new(Digest::SHA256.hexdigest("valid"))
      bottle = cached_bottle(expected_checksum.hexdigest, "mismatched")
      expect(UnpackStrategy).not_to receive(:detect)
      expect(bottle).to receive(:fetch) do
        bottle.cached_download.write("still mismatched")
        raise ChecksumMismatchError.new(bottle.cached_download, expected_checksum,
                                        Checksum.new(Digest::SHA256.hexdigest("still mismatched")))
      end

      expect do
        expect { bottle.stage_from_download_queue(bottle.cached_download, pour: true) }
          .to raise_error(ChecksumMismatchError)
      end.to output(/Removing corrupt cached download/).to_stderr
    ensure
      bottle&.clear_cache
    end

    it "keeps a cached bottle matching its checksum that fails to extract", :aggregate_failures do
      content = "valid but unextractable"
      bottle = cached_bottle(Digest::SHA256.hexdigest(content), content)
      allow(UnpackStrategy).to receive(:detect).and_raise("gzip decompression failed")

      expect(bottle).not_to receive(:fetch)

      expect { bottle.stage_from_download_queue(bottle.cached_download, pour: true) }
        .to raise_error(RuntimeError, "gzip decompression failed")
      expect(bottle.cached_download).to exist
    end
  end

  describe "#github_packages_manifest_resource" do
    sig { returns(String) }
    def bottle_domain = "https://mirror.example.com/homebrew-bottles"

    sig { params(root_url: String).returns(Bottle) }
    def test_bottle(root_url = bottle_domain)
      bottle_spec = BottleSpecification.new
      bottle_spec.root_url(root_url)
      bottle_spec.sha256(
        cellar:            :any_skip_relocation,
        Utils::Bottles.tag.to_sym => "d7b9f4e8bf83608b71fe958a99f19f2e5e68bb2582965d32e41759c24f1aef97",
      )
      described_class.new(nil, bottle_spec, Utils::Bottles.tag,
                          name: "foo", pkg_version: PkgVersion.new(Version.new("1.2.3"), 0))
    end

    before do
      ENV["HOMEBREW_BOTTLE_DOMAIN"] = bottle_domain
    end

    it "falls back to GHCR for a custom bottle domain" do
      bottle = test_bottle
      manifest_resource = bottle.github_packages_manifest_resource
      downloader = manifest_resource&.downloader
      raise "Expected a GitHub Packages download strategy" unless downloader.is_a?(CurlGitHubPackagesDownloadStrategy)

      expect([manifest_resource&.url, downloader.mirrors]).to eq([
        "#{bottle_domain}/foo/manifests/1.2.3",
        ["#{HOMEBREW_BOTTLE_DEFAULT_DOMAIN}/foo/manifests/1.2.3"],
      ])
    end

    it "keeps the bottle mirror when neither manifest URL is available", :aggregate_failures do
      bottle = test_bottle
      manifest_resource = bottle.github_packages_manifest_resource
      raise "Expected a bottle manifest resource" if manifest_resource.nil?

      allow(manifest_resource).to receive(:fetch)
        .and_raise(DownloadError.new(manifest_resource, RuntimeError.new("manifest missing")))

      expect { bottle.fetch_tab }.to raise_error(DownloadError)
      expect(bottle.url).to start_with(bottle_domain)
    end

    it "does not create a manifest resource for an unrelated flat bottle domain" do
      bottle = test_bottle("https://example.com/bottles")

      expect(bottle.github_packages_manifest_resource).to be_nil
    end
  end

  describe "#sbom_supplement" do
    it "reads the supplement from a valid bottle manifest" do
      bottle_spec = BottleSpecification.new
      bottle_spec.sha256(arm64_big_sur: "deadbeef" * 8)
      bottle = described_class.new(nil, bottle_spec, Utils::Bottles::Tag.from_symbol(:arm64_big_sur),
                                   name: "foo", pkg_version: PkgVersion.new(Version.new("1.2.3"), 0))
      supplement = { "packages" => [{ "SPDXID" => "SPDXRef-Compiler" }] }
      manifest_resource = instance_double(
        Resource::BottleManifest,
        downloaded_and_valid?: true,
        sbom_supplement:       supplement,
      )

      allow(bottle).to receive(:github_packages_manifest_resource).and_return(manifest_resource)

      expect(bottle.sbom_supplement).to eq(supplement)
    end
  end
end
