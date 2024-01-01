# frozen_string_literal: true

require "patch"

describe Patch do
  describe "#create" do
    context "with a simple patch" do
      subject { described_class.create(:p2, nil) }

      it { is_expected.to be_a ExternalPatch }
      it { is_expected.to be_external }
      its(:strip) { is_expected.to eq(:p2) }
    end

    context "with a string patch" do
      subject { described_class.create(:p0, "foo") }

      it { is_expected.to be_a StringPatch }
      its(:strip) { is_expected.to eq(:p0) }
    end

    context "with a string patch without strip" do
      subject { described_class.create("foo", nil) }

      it { is_expected.to be_a StringPatch }
      its(:strip) { is_expected.to eq(:p1) }
    end

    context "with a data patch" do
      subject { described_class.create(:p0, :DATA) }

      it { is_expected.to be_a DATAPatch }
      its(:strip) { is_expected.to eq(:p0) }
    end

    context "with a data patch without strip" do
      subject { described_class.create(:DATA, nil) }

      it { is_expected.to be_a DATAPatch }
      its(:strip) { is_expected.to eq(:p1) }
    end

    it "raises an error for unknown values" do
      expect do
        described_class.create(Object.new)
      end.to raise_error(ArgumentError)

      expect do
        described_class.create(Object.new, Object.new)
      end.to raise_error(ArgumentError)
    end
  end

  describe "#patch_files" do
    subject(:patch) { described_class.create(:p2, nil) }

    context "when the patch is empty" do
      its(:resource) { is_expected.to be_a Resource::PatchResource }
      its(:patch_files) { is_expected.to eq(patch.resource.patch_files) }
      its(:patch_files) { is_expected.to eq([]) }
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

  describe EmbeddedPatch do
    describe "#new" do
      subject { described_class.new(:p1) }

      its(:inspect) { is_expected.to eq("#<EmbeddedPatch: :p1>") }
    end
  end

  describe ExternalPatch do
    subject(:patch) { described_class.new(:p1) { url "file:///my.patch" } }

    describe "#url" do
      its(:url) { is_expected.to eq("file:///my.patch") }
    end

    describe "#inspect" do
      its(:inspect) { is_expected.to eq('#<ExternalPatch: :p1 "file:///my.patch">') }
    end

    describe "#cached_download" do
      before do
        allow(patch.resource).to receive(:cached_download).and_return("/tmp/foo.tar.gz")
      end

      its(:cached_download) { is_expected.to eq("/tmp/foo.tar.gz") }
    end
  end
end
