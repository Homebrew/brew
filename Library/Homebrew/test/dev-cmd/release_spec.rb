# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/release"

RSpec.describe Homebrew::DevCmd::Release do
  it_behaves_like "parseable arguments"

  describe "release lookup helpers" do
    let(:command) { described_class.new([]) }
    let(:releases) do
      [
        {
          "id"         => 1,
          "name"       => "1.2.3",
          "created_at" => "2025-01-01T00:00:00Z",
          "html_url"   => "https://github.com/Homebrew/brew/releases/tag/1.2.3",
        },
        {
          "id"         => 2,
          "name"       => "1.2.3",
          "created_at" => "2025-01-02T00:00:00Z",
          "html_url"   => "https://github.com/Homebrew/brew/releases/tag/1.2.3-2",
        },
        {
          "id"         => 3,
          "name"       => "1.2.2",
          "created_at" => "2024-12-31T00:00:00Z",
          "html_url"   => "https://github.com/Homebrew/brew/releases/tag/1.2.2",
        },
        {
          "id"         => 4,
          "name"       => nil,
          "tag_name"   => "1.2.3",
          "created_at" => "2025-01-03T00:00:00Z",
          "html_url"   => "https://github.com/Homebrew/brew/releases/tag/1.2.3-3",
        },
      ]
    end

    before do
      allow(GitHub::API).to receive(:open_rest).and_return(releases)
    end

    it "filters releases by name or tag name" do
      matching = command.send(:matching_releases, "1.2.3")
      expect(matching.map { |release| release["id"] }).to eq([1, 2, 4])
    end

    it "selects the latest matching release by creation time" do
      latest = command.send(:latest_matching_release, "1.2.3")
      expect(latest["id"]).to eq(4)
    end
  end
end
