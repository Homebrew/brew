# typed: true
# frozen_string_literal: true

require "patch"

RSpec.describe Patch do
  describe "#create" do
    context "with a simple patch" do
      subject(:patch) { described_class.create(:p2, nil) }

      specify(:aggregate_failures) do
        expect(patch).to be_a ExternalPatch
        expect(patch).to be_external
      end

      it(:strip) { expect(patch.strip).to eq(:p2) }
    end

    context "with a string patch" do
      subject(:patch) { described_class.create(:p0, "foo") }

      it { is_expected.to be_a StringPatch }
      it(:strip) { expect(patch.strip).to eq(:p0) }
    end

    context "with a string patch without strip" do
      subject(:patch) { described_class.create("foo", nil) }

      it { is_expected.to be_a StringPatch }
      it(:strip) { expect(patch.strip).to eq(:p1) }
    end

    context "with a data patch" do
      subject(:patch) { described_class.create(:p0, :DATA) }

      it { is_expected.to be_a DATAPatch }
      it(:strip) { expect(patch.strip).to eq(:p0) }
    end

    context "with a data patch without strip" do
      subject(:patch) { described_class.create(:DATA, nil) }

      it { is_expected.to be_a DATAPatch }
      it(:strip) { expect(patch.strip).to eq(:p1) }
    end

    context "with a local file patch" do
      subject(:patch) { described_class.create(:p0, nil) { file "Patches/foo.diff" } }

      specify(:aggregate_failures) do
        expect(patch).to be_a LocalPatch
        expect(patch).not_to be_external
      end

      it(:strip) { expect(patch.strip).to eq(:p0) }
      it(:inspect) { expect(patch.inspect).to eq('#<LocalPatch: :p0 "Patches/foo.diff">') }
    end

    it "rejects blank local file patch paths" do
      expect do
        described_class.create(:p1, nil) { file "" }
      end.to raise_error(ArgumentError, "Patch file must be a relative path within the repository.")
    end

    it "rejects current directory local file patch paths" do
      expect do
        described_class.create(:p1, nil) { file "." }
      end.to raise_error(ArgumentError, "Patch file must be a relative path within the repository.")
    end

    it "rejects parent directory local file patch paths" do
      expect do
        described_class.create(:p1, nil) { file ".." }
      end.to raise_error(ArgumentError, "Patch file must be a relative path within the repository.")
    end

    it "rejects local file patch paths ending in a slash" do
      expect do
        described_class.create(:p1, nil) { file "Patches/" }
      end.to raise_error(ArgumentError, "Patch file must be a relative path within the repository.")
    end

    it "rejects local file patches outside the repository" do
      expect do
        described_class.create(:p1, nil) { file "../foo.diff" }
      end.to raise_error(ArgumentError, "Patch file must be a relative path within the repository.")
    end

    it "rejects absolute local file patches" do
      expect do
        described_class.create(:p1, nil) { file "/tmp/foo.diff" }
      end.to raise_error(ArgumentError, "Patch file must be a relative path within the repository.")
    end

    it "rejects local file patches with URLs" do
      expect do
        described_class.create(:p1, nil) do
          file "Patches/foo.diff"
          url "https://brew.sh/foo.diff"
        end
      end.to raise_error(ArgumentError, "Patch cannot have both `file` and `url`.")
    end

    it "rejects local file patches with sha256" do
      expect do
        described_class.create(:p1, nil) do
          file "Patches/foo.diff"
          sha256 "63376b8fdd6613a91976106d9376069274191860cd58f039b29ff16de1925621"
        end
      end.to raise_error(ArgumentError, "Patch cannot use `sha256` with `file`.")
    end

    it "accepts local file patches with directory" do
      patch = described_class.create(:p1, nil) do
        file "Patches/foo.diff"
        directory "subdir"
      end

      expect(patch).to be_a LocalPatch
      expect(T.cast(patch, LocalPatch).directory).to eq("subdir")
    end

    it "rejects local file patches with apply" do
      expect do
        described_class.create(:p1, nil) do
          file "Patches/foo.diff"
          apply "foo.diff"
        end
      end.to raise_error(ArgumentError, "Patch cannot use `apply` with `file`.")
    end
  end

  describe ".extract_cves" do
    it "extracts and normalises CVE identifiers from strings" do
      result = described_class.extract_cves(
        "patches/any/CVE-2024-2961.patch",
        "patches/28-cve-2022-0529-and-cve-2022-0530.patch",
        "patches/any/CVE-2024-33601_33602.patch",
        "https://example.com/fix.diff",
      )
      expect(result).to eq(%w[CVE-2024-2961 CVE-2022-0529 CVE-2022-0530 CVE-2024-33601])
    end

    it "returns an empty array when nothing matches" do
      expect(described_class.extract_cves("foo", "bar.patch")).to eq([])
    end
  end

  describe ".resolves_type" do
    it "classifies CVE, GHSA and OSV identifiers as security and everything else as defect" do
      expect(described_class.resolves_type("CVE-2024-1234")).to eq("security")
      expect(described_class.resolves_type("GHSA-xr7r-f8xq-vfvv")).to eq("security")
      expect(described_class.resolves_type("OSV-2023-298")).to eq("security")
      expect(described_class.resolves_type("https://github.com/foo/bar/issues/1")).to eq("defect")
    end
  end

  describe ".ensure_targets_within!" do
    it "allows targets that stay within the source tree" do
      mktmpdir do |base|
        (base/"src").mkpath
        (base/"src/foo.c").write("old\n")
        patch = <<~EOS
          --- a/src/foo.c
          +++ b/src/foo.c
          @@ -1 +1 @@
          -old
          +new
        EOS

        expect { described_class.ensure_targets_within!(patch, strip: :p1, base:) }.not_to raise_error
      end
    end

    it "allows /dev/null headers for added or deleted files" do
      mktmpdir do |base|
        patch = <<~EOS
          --- /dev/null
          +++ b/new.c
          @@ -0,0 +1 @@
          +new
        EOS

        expect { described_class.ensure_targets_within!(patch, strip: :p1, base:) }.not_to raise_error
      end
    end

    it "allows a context diff whose selected target stays within the source tree" do
      mktmpdir do |base|
        (base/"lib/sh").mkpath
        (base/"lib/sh/foo.c").write("old\n")
        patch = <<~EOS
          *** ../pkg-1.0-patched/lib/sh/foo.c	2024-01-01
          --- lib/sh/foo.c	2024-01-01
          ***************
          *** 1 ****
          ! old
          --- 1 ----
          ! new
        EOS

        expect { described_class.ensure_targets_within!(patch, strip: :p0, base:) }.not_to raise_error
      end
    end

    it "rejects an Index header that escapes via `..`", :needs_macos do
      mktmpdir do |base|
        patch = <<~EOS
          Index: a/../escape.txt
          ===================================================================
          @@ -0,0 +1 @@
          +owned
        EOS

        expect { described_class.ensure_targets_within!(patch, strip: :p1, base:) }
          .to raise_error(/escapes the staged source tree/)
      end
    end
  end

  describe "#resolves" do
    it "merges explicit resolves with CVEs inferred from url and apply paths" do
      patch = T.cast(described_class.create(:p1, nil) do
        url "https://example.com/CVE-2024-1111.patch"
        apply "patches/cve-2024-2222.patch"
        resolves "CVE-2024-3333"
      end, ExternalPatch)
      expect(patch.resolves).to eq(["CVE-2024-3333", "CVE-2024-1111", "CVE-2024-2222"])
    end

    it "carries explicit resolves through to a local file patch and infers from the file path" do
      patch = T.cast(described_class.create(:p1, nil) do
        file "Patches/CVE-2024-1234.diff"
        resolves "CVE-2024-5678"
      end, LocalPatch)
      expect(patch.resolves).to eq(["CVE-2024-5678", "CVE-2024-1234"])
    end
  end

  describe "#type" do
    it "stores a valid type on an external patch" do
      patch = T.cast(described_class.create(:p1, nil) do
        url "https://example.com/foo.diff"
        type :backport
      end, ExternalPatch)
      expect(patch.type).to eq(:backport)
    end

    it "carries type through to a local file patch" do
      patch = T.cast(described_class.create(:p1, nil) do
        file "Patches/foo.diff"
        type :unofficial
      end, LocalPatch)
      expect(patch.type).to eq(:unofficial)
    end

    it "rejects invalid types" do
      expect do
        described_class.create(:p1, nil) do
          url "https://example.com/foo.diff"
          type :hotfix
        end
      end.to raise_error(ArgumentError, /Patch type must be one of/)
    end
  end

  describe "#patch_files" do
    subject(:patch) { described_class.create(:p2, nil) }

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
    subject(:patch) { described_class.new(:p1) { url "file:///my.patch" } }

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

  describe StringPatch do
    it "applies a patch whose target stays within the source tree" do
      patch = described_class.new(:p1, <<~EOS)
        --- a/foo
        +++ b/foo
        @@ -1 +1 @@
        -old
        +new
      EOS
      mktmpdir do |dir|
        (dir/"source").mkpath
        (dir/"source/foo").write("old\n")
        Dir.chdir(dir/"source") { patch.apply }

        expect((dir/"source/foo").read).to eq("new\n")
      end
    end

    it "refuses to apply a patch whose target escapes the source tree" do
      patch = described_class.new(:p1, <<~EOS)
        Index: a/../evil
        ===================================================================
        @@ -0,0 +1 @@
        +owned
      EOS
      mktmpdir do |dir|
        (dir/"source").mkpath
        Dir.chdir(dir/"source") do
          expect { patch.apply }.to raise_error(StandardError)
        end
        expect(dir/"evil").not_to exist
      end
    end

    it "does not let a Perforce target escape the source tree" do
      patch = described_class.new(:p1, <<~EOS)
        ==== a/../evil ====
        @@ -0,0 +1 @@
        +owned
      EOS
      mktmpdir do |dir|
        (dir/"source").mkpath
        Dir.chdir(dir/"source") do
          expect { patch.apply }.to raise_error(StandardError)
        end
        expect(dir/"evil").not_to exist
      end
    end

    it "does not let a standard target escape the source tree" do
      patch = described_class.new(:p1, <<~EOS)
        --- a/../evil
        +++ b/../evil
        @@ -0,0 +1 @@
        +owned
      EOS
      mktmpdir do |dir|
        (dir/"source").mkpath
        Dir.chdir(dir/"source") do
          expect { patch.apply }.to raise_error(StandardError)
        end
        expect(dir/"evil").not_to exist
      end
    end

    it "does not let an absolute target escape the source tree" do
      mktmpdir do |dir|
        (dir/"source").mkpath
        escape = dir/"evil"
        patch = described_class.new(:p0, <<~EOS)
          Index: #{escape}
          ===================================================================
          @@ -0,0 +1 @@
          +owned
        EOS

        Dir.chdir(dir/"source") do
          expect { patch.apply }.to raise_error(StandardError)
        end
        expect(escape).not_to exist
      end
    end

    it "does not let one escaping target in a multi-file patch escape the source tree" do
      patch = described_class.new(:p1, <<~EOS)
        --- a/decoy.c
        +++ b/decoy.c
        @@ -1 +1 @@
        -old
        +new
        Index: a/../evil
        ===================================================================
        @@ -0,0 +1 @@
        +owned
      EOS
      mktmpdir do |dir|
        (dir/"source").mkpath
        (dir/"source/decoy.c").write("old\n")
        Dir.chdir(dir/"source") do
          expect { patch.apply }.to raise_error(StandardError)
        end
        expect(dir/"evil").not_to exist
      end
    end
  end
end
