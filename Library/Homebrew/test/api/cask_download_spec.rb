# typed: strict
# frozen_string_literal: true

require "api/cask_download"

RSpec.describe Homebrew::API::CaskDownload do
  describe "::download" do
    it "preserves rename operations so staging can perform them" do
      cask_struct = Homebrew::API::CaskStruct.from_hash({
        "sha256"   => "abc123",
        "version"  => "1.0.0",
        "url_args" => ["https://example.com/file.zip"],
        "renames"  => [["Test *.pkg", "Test.pkg"]],
      })

      download = described_class.download(token: "test-cask", cask_struct:)
      renames = download&.cask&.rename

      expect(renames&.map(&:pairs)).to eq([{ from: "Test *.pkg", to: "Test.pkg" }])
    end
  end
end
