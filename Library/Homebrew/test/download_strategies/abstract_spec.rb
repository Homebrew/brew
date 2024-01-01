# frozen_string_literal: true

require "download_strategy"

describe AbstractDownloadStrategy do
  subject(:strategy) { described_class.new(url, name, version, **specs) }

  let(:specs) { {} }
  let(:name) { "foo" }
  let(:url) { "https://example.com/foo.tar.gz" }
  let(:version) { nil }
  let(:args) { %w[foo bar baz] }

  specify "#source_modified_time" do
    Mktemp.new("mtime") do
      FileUtils.touch "foo", mtime: Time.now - 10
      FileUtils.touch "bar", mtime: Time.now - 100
      FileUtils.ln_s "not-exist", "baz"
      expect(strategy.source_modified_time).to eq(File.mtime("foo"))
    end
  end

  context "when specs[:bottle]" do
    let(:specs) { { bottle: true } }

    it "extends Pourable" do
      expect(strategy).to be_a(AbstractDownloadStrategy::Pourable)
    end
  end

  context "without specs[:bottle]" do
    it "is does not extend Pourable" do
      expect(strategy).not_to be_a(AbstractDownloadStrategy::Pourable)
    end
  end
end
