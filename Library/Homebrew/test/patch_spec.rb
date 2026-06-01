# typed: false
# frozen_string_literal: true

require "patch"

RSpec.describe Patch do
  let(:klass) { Patch }

  describe "#create" do
    context "with a simple patch" do
      subject(:patch) { klass.create(:p2, nil) }

      specify(:aggregate_failures) do
        expect(patch).to be_a ExternalPatch
        expect(patch).to be_external
      end

      it(:strip) { expect(patch.strip).to eq(:p2) }
    end

    context "with a string patch" do
      subject(:patch) { klass.create(:p0, "foo") }

      it { is_expected.to be_a StringPatch }
      it(:strip) { expect(patch.strip).to eq(:p0) }
    end

    context "with a string patch without strip" do
      subject(:patch) { klass.create("foo", nil) }

      it { is_expected.to be_a StringPatch }
      it(:strip) { expect(patch.strip).to eq(:p1) }
    end

    context "with a data patch" do
      subject(:patch) { klass.create(:p0, :DATA) }

      it { is_expected.to be_a DATAPatch }
      it(:strip) { expect(patch.strip).to eq(:p0) }
    end

    context "with a data patch without strip" do
      subject(:patch) { klass.create(:DATA, nil) }

      it { is_expected.to be_a DATAPatch }
      it(:strip) { expect(patch.strip).to eq(:p1) }
    end

    context "with a local file patch" do
      subject(:patch) { klass.create(:p0, nil) { file "Patches/foo.diff" } }

      specify(:aggregate_failures) do
        expect(patch).to be_a LocalPatch
        expect(patch).not_to be_external
      end

      it(:strip) { expect(patch.strip).to eq(:p0) }
      it(:inspect) { expect(patch.inspect).to eq('#<LocalPatch: :p0 "Patches/foo.diff">') }
    end

    it "rejects blank local file patch paths" do
      expect do
        klass.create(:p1, nil) { file "" }
      end.to raise_error(ArgumentError, "Patch file must be a relative path within the repository.")
    end

    it "rejects current directory local file patch paths" do
      expect do
        klass.create(:p1, nil) { file "." }
      end.to raise_error(ArgumentError, "Patch file must be a relative path within the repository.")
    end

    it "rejects parent directory local file patch paths" do
      expect do
        klass.create(:p1, nil) { file ".." }
      end.to raise_error(ArgumentError, "Patch file must be a relative path within the repository.")
    end

    it "rejects local file patch paths ending in a slash" do
      expect do
        klass.create(:p1, nil) { file "Patches/" }
      end.to raise_error(ArgumentError, "Patch file must be a relative path within the repository.")
    end

    it "rejects local file patches outside the repository" do
      expect do
        klass.create(:p1, nil) { file "../foo.diff" }
      end.to raise_error(ArgumentError, "Patch file must be a relative path within the repository.")
    end

    it "rejects absolute local file patches" do
      expect do
        klass.create(:p1, nil) { file "/tmp/foo.diff" }
      end.to raise_error(ArgumentError, "Patch file must be a relative path within the repository.")
    end

    it "rejects local file patches with URLs" do
      expect do
        klass.create(:p1, nil) do
          file "Patches/foo.diff"
          url "https://brew.sh/foo.diff"
        end
      end.to raise_error(ArgumentError, "Patch cannot have both `file` and `url`.")
    end

    it "rejects local file patches with sha256" do
      expect do
        klass.create(:p1, nil) do
          file "Patches/foo.diff"
          sha256 "63376b8fdd6613a91976106d9376069274191860cd58f039b29ff16de1925621"
        end
      end.to raise_error(ArgumentError, "Patch cannot use `sha256` with `file`.")
    end

    it "rejects local file patches with directory" do
      expect do
        klass.create(:p1, nil) do
          file "Patches/foo.diff"
          directory "subdir"
        end
      end.to raise_error(ArgumentError, "Patch cannot use `directory` with `file`.")
    end

    it "rejects local file patches with apply" do
      expect do
        klass.create(:p1, nil) do
          file "Patches/foo.diff"
          apply "foo.diff"
        end
      end.to raise_error(ArgumentError, "Patch cannot use `apply` with `file`.")
    end
  end

  describe ".extract_cves" do
    it "extracts and normalises CVE identifiers from strings" do
      result = klass.extract_cves(
        "patches/any/CVE-2024-2961.patch",
        "patches/28-cve-2022-0529-and-cve-2022-0530.patch",
        "patches/any/CVE-2024-33601_33602.patch",
        "https://example.com/fix.diff",
      )
      expect(result).to eq(%w[CVE-2024-2961 CVE-2022-0529 CVE-2022-0530 CVE-2024-33601])
    end

    it "returns an empty array when nothing matches" do
      expect(klass.extract_cves("foo", "bar.patch")).to eq([])
    end
  end

  describe ".resolves_type" do
    it "classifies CVE and GHSA identifiers as security and everything else as defect" do
      expect(klass.resolves_type("CVE-2024-1234")).to eq("security")
      expect(klass.resolves_type("GHSA-xr7r-f8xq-vfvv")).to eq("security")
      expect(klass.resolves_type("https://github.com/foo/bar/issues/1")).to eq("defect")
    end
  end

  describe "#resolves" do
    it "merges explicit resolves with CVEs inferred from url and apply paths" do
      patch = klass.create(:p1, nil) do
        url "https://example.com/CVE-2024-1111.patch"
        apply "patches/cve-2024-2222.patch"
        resolves "CVE-2024-3333"
      end
      expect(patch.resolves).to eq(["CVE-2024-3333", "CVE-2024-1111", "CVE-2024-2222"])
    end

    it "carries explicit resolves through to a local file patch and infers from the file path" do
      patch = klass.create(:p1, nil) do
        file "Patches/CVE-2024-1234.diff"
        resolves "CVE-2024-5678"
      end
      expect(patch.resolves).to eq(["CVE-2024-5678", "CVE-2024-1234"])
    end
  end

  describe "#type" do
    it "stores a valid type on an external patch" do
      patch = klass.create(:p1, nil) do
        url "https://example.com/foo.diff"
        type :backport
      end
      expect(patch.type).to eq(:backport)
    end

    it "carries type through to a local file patch" do
      patch = klass.create(:p1, nil) do
        file "Patches/foo.diff"
        type :unofficial
      end
      expect(patch.type).to eq(:unofficial)
    end

    it "rejects invalid types" do
      expect do
        klass.create(:p1, nil) do
          url "https://example.com/foo.diff"
          type :hotfix
        end
      end.to raise_error(ArgumentError, /Patch type must be one of/)
    end
  end

  describe "#patch_files" do
    subject(:patch) { klass.create(:p2, nil) }

    context "when the patch is empty" do
      it(:resource) { expect(patch.resource).to be_a Resource::Patch }

      specify(:aggregate_failures) do
        expect(patch.patch_files).to eq(patch.resource.patch_files)
        expect(patch.patch_files).to eq([])
      end
    end

    it "returns applied patch files" do
      patch.resource.apply("patch1.diff")
      expect(patch.patch_files).to eq(["patch1.diff"])

      patch.resource.apply("patch2.diff", "patch3.diff")
      expect(patch.patch_files).to eq(["patch1.diff", "patch2.diff", "patch3.diff"])

      patch.resource.apply(["patch4.diff", "patch5.diff"])
      expect(patch.patch_files.count).to eq(5)

      patch.resource.apply("patch4.diff", ["patch5.diff", "patch6.diff"], "patch7.diff")
      expect(patch.patch_files.count).to eq(7)
    end
  end

  describe ExternalPatch do
    subject(:patch) { klass.new(:p1) { url "file:///my.patch" } }

    let(:klass) { ExternalPatch }

    describe "#url" do
      it(:url) { expect(patch.url).to eq("file:///my.patch") }
    end

    describe "#inspect" do
      it(:inspect) { expect(patch.inspect).to eq('#<ExternalPatch: :p1 "file:///my.patch">') }
    end

    describe "#cached_download" do
      before do
        allow(patch.resource).to receive(:cached_download).and_return("/tmp/foo.tar.gz")
      end

      it(:cached_download) { expect(patch.cached_download).to eq("/tmp/foo.tar.gz") }
    end
  end
end
