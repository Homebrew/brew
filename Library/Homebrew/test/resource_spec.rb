# typed: true
# frozen_string_literal: true

require "resource"
require "bottle"
require "github_packages"
require "livecheck"

RSpec.describe Resource do
  subject(:resource) { described_class.new("test") }

  let(:livecheck_resource) do
    described_class.new do
      url "https://brew.sh/foo-1.0.tar.gz"
      sha256 "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

      livecheck do
        url "https://brew.sh/test/releases"
        regex(/foo[._-]v?(\d+(?:\.\d+)+)\.t/i)
      end
    end
  end

  describe "#url" do
    it "sets the URL" do
      resource.url("foo")
      expect(resource.url).to eq("foo")
    end

    it "can set the URL with specifications" do
      resource.url("foo", branch: "master")
      expect(resource.url).to eq("foo")
      expect(resource.specs).to eq(branch: "master")
    end

    it "can set the URL with a custom download strategy class" do
      strategy = Class.new(AbstractDownloadStrategy)
      resource.url("foo", using: strategy)
      expect(resource.url).to eq("foo")
      expect(resource.download_strategy).to eq(strategy)
    end

    it "can set the URL with specifications and a custom download strategy class" do
      strategy = Class.new(AbstractDownloadStrategy)
      resource.url("foo", using: strategy, branch: "master")
      expect(resource.url).to eq("foo")
      expect(resource.specs).to eq(branch: "master")
      expect(resource.download_strategy).to eq(strategy)
    end

    it "can set the URL with a custom download strategy symbol" do
      resource.url("foo", using: :git)
      expect(resource.url).to eq("foo")
      expect(resource.download_strategy).to eq(GitDownloadStrategy)
    end

    it "raises an error if the download strategy class is unknown" do
      expect { resource.url("foo", using: Class.new) }.to raise_error(TypeError)
    end

    it "does not mutate the specifications hash" do
      specs = { using: :git, branch: "master" }
      resource.url("foo", **specs)
      expect(resource.specs).to eq(branch: "master")
      expect(resource.using).to eq(:git)
      expect(specs).to eq(using: :git, branch: "master")
    end
  end

  describe "#livecheck" do
    specify "when `livecheck` block is set" do
      expect(livecheck_resource.livecheck.url).to eq("https://brew.sh/test/releases")
      expect(livecheck_resource.livecheck.regex).to eq(/foo[._-]v?(\d+(?:\.\d+)+)\.t/i)
    end
  end

  describe "#livecheck_defined?" do
    specify do
      expect(resource.livecheck_defined?).to be false
      expect(livecheck_resource.livecheck_defined?).to be true
    end
  end

  describe "#version" do
    it "sets the version" do
      resource.version("1.0")
      expect(resource.version).to eq(Version.parse("1.0"))
      expect(resource.version).not_to be_detected_from_url
    end

    it "can detect the version from a URL" do
      resource.url("https://brew.sh/foo-1.0.tar.gz")
      expect(resource.version).to eq(Version.parse("1.0"))
      expect(resource.version).to be_detected_from_url
    end

    it "can set the version with a scheme" do
      klass = Class.new(Version)
      resource.version klass.new("1.0")
      expect(resource.version).to eq(Version.parse("1.0"))
      expect(resource.version).to be_a(klass)
    end

    it "can set the version from a tag" do
      resource.url("https://brew.sh/foo-1.0.tar.gz", tag: "v1.0.2")
      expect(resource.version).to eq(Version.parse("1.0.2"))
      expect(resource.version).to be_detected_from_url
    end

    it "rejects non-string versions" do
      expect { resource.version(1) }.to raise_error(TypeError)
      expect { resource.version(2.0) }.to raise_error(TypeError)
      expect { resource.version(Object.new) }.to raise_error(TypeError)
    end

    it "returns nil if unset" do
      expect(resource.version).to be_nil
    end
  end

  describe "#mirrors" do
    it "is empty by defaults" do
      expect(resource.mirrors).to be_empty
    end

    it "returns an array of mirrors added with #mirror" do
      resource.mirror("foo")
      resource.mirror("bar")
      expect(resource.mirrors).to eq(%w[foo bar])
    end
  end

  describe "#checksum" do
    it "returns nil if unset" do
      expect(resource.checksum).to be_nil
    end

    it "returns the checksum set with #sha256" do
      resource.sha256(TEST_SHA256)
      expect(resource.checksum).to eq(Checksum.new(TEST_SHA256))
    end
  end

  describe "#download_strategy" do
    it "returns the download strategy" do
      strategy = Class.new(AbstractDownloadStrategy)
      expect(DownloadStrategyDetector)
        .to receive(:detect).with("foo", nil).and_return(strategy)
      resource.url("foo")
      expect(resource.download_strategy).to eq(strategy)
    end
  end

  describe "#fetch" do
    let(:url) do
      ENV["HOMEBREW_PRIVATE_TOKEN"] = "glpat-secret"
      ENV.clear_sensitive_environment_for_eval! do
        "https://example.com/foo.tar.gz?private_token=#{ENV.fetch("HOMEBREW_PRIVATE_TOKEN", nil)}"
      end
    end
    let(:headers) do
      {
        "accept-ranges"  => "bytes",
        "content-length" => "37182",
      }
    end

    before do
      resource.url(url)
      allow(resource.downloader).to receive(:curl_headers).with(any_args)
                                                          .and_return({ responses: [{ headers: }] })
    end

    after do
      ENV.delete("HOMEBREW_PRIVATE_TOKEN")
      resource.clear_cache
    end

    it "expands deferred environment placeholders while downloading" do
      expect(url).to include(EnvSensitive::DEFERRED_PLACEHOLDER_PREFIX)
      expect(resource.downloader).to receive(:system_command)
        .with(
          /curl/,
          hash_including(args: array_including("https://example.com/foo.tar.gz?private_token=glpat-secret")),
        )
        .at_least(:once)
        .and_return(instance_double(SystemCommand::Result, success?: true, stdout: "", assert_success!: nil))

      resource.downloader.temporary_path.dirname.mkpath
      FileUtils.touch resource.downloader.temporary_path
      resource.fetch(verify_download_integrity: false)
    end

    it "does not expand placeholders for custom curl download strategies" do
      expect(url).to include(EnvSensitive::DEFERRED_PLACEHOLDER_PREFIX)
      resource.url(url, using: Class.new(CurlDownloadStrategy))
      allow(resource.downloader).to receive(:curl_headers).with(any_args)
                                                          .and_return({ responses: [{ headers: }] })

      expect(resource.downloader).to receive(:system_command)
        .with(
          /curl/,
          hash_including(args: array_including(url)),
        )
        .at_least(:once)
        .and_return(instance_double(SystemCommand::Result, success?: true, stdout: "", assert_success!: nil))

      resource.downloader.temporary_path.dirname.mkpath
      FileUtils.touch resource.downloader.temporary_path
      resource.fetch(verify_download_integrity: false)
    end
  end

  describe "#stage" do
    let(:last_modified) { Time.utc(2026, 5, 6, 13, 43, 5) }
    let(:tarball) { TEST_FIXTURE_DIR/"tarballs/testball-0.1.tbz" }
    let(:url) { "https://files.pythonhosted.org/packages/ab/cd/efg/testball-0.1.tbz" }

    before do
      resource.url(url)
      resource.sha256(tarball.sha256)
      allow(resource.downloader).to receive(:resolve_url_basename_time_file_size)
        .and_return([url, tarball.basename.to_s, last_modified, tarball.size, "application/x-bzip2", false])
      allow(resource.downloader).to receive(:_fetch) do
        resource.downloader.temporary_path.dirname.mkpath
        FileUtils.cp tarball, resource.downloader.temporary_path
        FileUtils.touch resource.downloader.temporary_path, mtime: last_modified
      end
    end

    after { resource.clear_cache }

    it "records the PyPI last modified time when staged files are older" do
      resource.stage(mktmpdir)

      expect(resource.source_modified_time).to eq(last_modified)
    end
  end

  describe "#owner" do
    let(:owner) { described_class.new("test-owner") }

    it "sets the owner" do
      resource.owner = owner
      expect(resource.owner).to eq(owner)
    end

    it "sets its owner to be the patches' owner" do
      resource.patch(:p1) do
        T.bind(self, Resource::Patch)
        url "file:///my.patch"
      end
      resource.owner = owner
      resource.patches.each do |p|
        expect(p.resource.owner).to eq(owner)
      end
    end
  end

  describe "#patch" do
    it "adds a patch" do
      resource.patch(:p1, :DATA)
      expect(resource.patches.count).to eq(1)
      expect(resource.patches.first.strip).to eq(:p1)
    end
  end

  describe Resource::BottleManifest do
    describe "#sbom_supplement" do
      it "returns the current platform supplement from an all bottle manifest" do
        bottle_resource = Resource.new("testball")
        bottle_resource.version("1.0")
        bottle_resource.sha256(TEST_SHA256)

        bottle = instance_double(
          Bottle,
          name:     "testball",
          rebuild:  0,
          resource: bottle_resource,
          tag:      Utils::Bottles.tag(:all),
        )
        manifest = described_class.new(bottle)

        current_tag_supplement = { "packages" => [{ "SPDXID" => "SPDXRef-current" }] }
        manifest_json = {
          "manifests" => [
            {
              "annotations" => {
                "org.opencontainers.image.ref.name" => "1.0.all",
                "sh.brew.bottle.digest"             => TEST_SHA256,
                "sh.brew.sbom.supplement"           => {
                  "tags" => {
                    Utils::Bottles.tag.to_s => current_tag_supplement,
                    "other"                 => { "packages" => [{ "SPDXID" => "SPDXRef-other" }] },
                  },
                }.to_json,
              },
            },
          ],
        }
        cached_download = mktmpdir/"manifest.json"
        cached_download.write(JSON.generate(manifest_json))
        allow(manifest).to receive(:cached_download).and_return(cached_download)

        expect(manifest.sbom_supplement).to eq(current_tag_supplement)
      end
    end
  end

  specify "#verify_download_integrity_missing" do
    fn = Pathname.new("test")

    allow(fn).to receive(:file?).and_return(true)
    expect(fn).to receive(:verify_checksum).and_raise(ChecksumMissingError)
    expect(fn).to receive(:sha256)

    resource.verify_download_integrity(fn)
  end

  specify "#verify_download_integrity_mismatch" do
    fn = instance_double(Pathname, file?: true, basename: "foo")
    checksum = resource.sha256(TEST_SHA256)

    expect(fn).to receive(:verify_checksum)
      .with(checksum)
      .and_raise(ChecksumMismatchError.new(fn, checksum, Checksum.new(Digest::SHA256.new.hexdigest)))

    expect do
      resource.verify_download_integrity(fn)
    end.to raise_error(ChecksumMismatchError)
  end
end
