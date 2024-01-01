# frozen_string_literal: true

require "resource"
require "livecheck"

describe Resource do
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
    specify "when livecheck block is set" do
      expect(livecheck_resource.livecheck.url).to eq("https://brew.sh/test/releases")
      expect(livecheck_resource.livecheck.regex).to eq(/foo[._-]v?(\d+(?:\.\d+)+)\.t/i)
    end
  end

  describe "#livecheckable?" do
    it "returns false if livecheck block is not set in resource" do
      expect(resource.livecheckable?).to be false
    end

    specify "livecheck block defined in resources" do
      expect(livecheck_resource.livecheckable?).to be true
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

  describe "#owner" do
    it "sets the owner" do
      owner = Object.new
      resource.owner = owner
      expect(resource.owner).to eq(owner)
    end

    it "sets its owner to be the patches' owner" do
      resource.patch(:p1) { url "file:///my.patch" }
      owner = Object.new
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
      .and_raise(ChecksumMismatchError.new(fn, checksum, Object.new))

    expect do
      resource.verify_download_integrity(fn)
    end.to raise_error(ChecksumMismatchError)
  end
end
