# frozen_string_literal: true

require "patch"

RSpec.describe Patch do
  describe "#create" do
    context "with a simple patch" do
      subject(:patch) { described_class.create(:p2, nil) }

      specify(:aggregate_failures) do
        expect(subject).to be_a ExternalPatch # rubocop:todo RSpec/NamedSubject
        expect(subject).to be_external # rubocop:todo RSpec/NamedSubject
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
end
