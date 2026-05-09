# typed: false
# frozen_string_literal: true

require "download_strategy"

RSpec.describe PyPIDownloadStrategy do
  subject(:strategy) { described_class.new(url, "foo", "1.2.3") }

  let(:url) { "https://files.pythonhosted.org/packages/ab/cd/efg/foo-1.2.3.tar.gz" }
  let(:last_modified) { Time.utc(2026, 5, 6, 13, 43, 5) }

  before do
    allow(Homebrew::EnvConfig).to receive(:artifact_domain).and_return(nil)
    allow(strategy).to receive(:resolve_url_basename_time_file_size)
      .and_return([url, "foo-1.2.3.tar.gz", last_modified, 1024, "application/gzip", false])
    allow(strategy).to receive(:_fetch)
    strategy.clear_cache
    strategy.temporary_path.dirname.mkpath
    FileUtils.touch strategy.temporary_path
  end

  describe "#source_modified_time" do
    it "uses the PyPI last modified time when archive contents are older" do
      strategy.fetch

      mktmpdir("mtime").cd do
        FileUtils.touch "foo.py", mtime: Time.utc(2020, 2, 2)

        expect(strategy.source_modified_time).to eq(last_modified)
      end
    end
  end
end
