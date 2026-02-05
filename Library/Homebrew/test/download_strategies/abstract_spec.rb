# frozen_string_literal: true

require "download_strategy"

RSpec.describe AbstractDownloadStrategy do
  subject(:strategy) { Class.new(described_class).new(url, name, version, **specs) }

  let(:specs) { {} }
  let(:name) { "foo" }
  let(:url) { "https://example.com/foo.tar.gz" }
  let(:version) { nil }
  let(:args) { %w[foo bar baz] }

  specify "#source_modified_time" do
    mktmpdir("mtime").cd do
      FileUtils.touch "foo", mtime: Time.now - 10
      FileUtils.touch "bar", mtime: Time.now - 100
      FileUtils.ln_s "not-exist", "baz"
      expect(strategy.source_modified_time).to eq(File.mtime("foo"))
    end
  end
end
