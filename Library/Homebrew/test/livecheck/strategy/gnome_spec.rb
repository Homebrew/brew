# frozen_string_literal: true

require "livecheck/strategy"

RSpec.describe Homebrew::Livecheck::Strategy::Gnome do
  subject(:gnome) { described_class }

  let(:gnome_url) { "https://download.gnome.org/sources/abc/1.2/abc-1.2.3.tar.xz" }
  let(:non_gnome_url) { "https://brew.sh/test" }

  let(:generated) do
    {
      url:   "https://download.gnome.org/sources/abc/cache.json",
      regex: /abc-(\d+(?:\.\d+)*)\.t/i,
    }
  end

  let(:content) do
    <<~EOS
      [4, {"abc": {"40.1.0": {"news": "40.1/abc-40.1.0.news", "changes": "40.1/abc-40.1.0.changes", "tar.xz": "40.1/abc-40.1.0.tar.xz", "sha256sum": "40.1/abc-40.1.0.sha256sum"}, "1.2.90": {"news": "1.2/abc-1.2.90.news", "changes": "1.2/abc-1.2.90.changes", "tar.xz": "1.2/abc-1.2.90.tar.xz", "sha256sum": "1.2/abc-1.2.90.sha256sum"}, "1.2.4": {"news": "1.2/abc-1.2.4.news", "changes": "1.2/abc-1.2.4.changes", "tar.xz": "1.2/abc-1.2.4.tar.xz", "sha256sum": "1.2/abc-1.2.4.sha256sum"}, "1.2.3": {"news": "1.2/abc-1.2.3.news", "changes": "1.2/abc-1.2.3.changes", "tar.xz": "1.2/abc-1.2.3.tar.xz", "sha256sum": "1.2/abc-1.2.3.sha256sum"}, "1.1.0": {"news": "1.1/abc-1.1.0.news", "changes": "1.1/abc-1.1.0.changes", "tar.xz": "1.1/abc-1.1.0.tar.xz", "sha256sum": "1.1/abc-1.1.0.sha256sum"}, "1": {"news": "1/abc-1.news", "changes": "1/abc-1.changes", "tar.xz": "1/abc-1.tar.xz", "sha256sum": "1/abc-1.sha256sum"}}}, {"abc": ["1", "1.1.0", "1.2.3", "1.2.4", "1.2.90", "40.1.0"]}, {"1": ["LATEST-IS-1"], "1.1": ["LATEST-IS-1.1.0"], "1.2": ["LATEST-IS-1.2.4"], "40": ["LATEST-IS-40.1.0"], ".": ["cache.json"]}]

    EOS
  end

  let(:matches) do
    {
      all:     ["40.1.0", "1.2.90", "1.2.4", "1.2.3", "1.1.0", "1"],
      default: ["40.1.0", "1.2.4", "1.2.3", "1"],
    }
  end

  describe "::match?" do
    it "returns true for a GNOME URL" do
      expect(gnome.match?(gnome_url)).to be true
    end

    it "returns false for a non-GNOME URL" do
      expect(gnome.match?(non_gnome_url)).to be false
    end
  end

  describe "::generate_input_values" do
    it "returns a hash containing url and regex for a GNOME URL" do
      expect(gnome.generate_input_values(gnome_url)).to eq(generated)
    end

    it "returns an empty hash for a non-GNOME URL" do
      expect(gnome.generate_input_values(non_gnome_url)).to eq({})
    end
  end

  describe "::find_versions" do
    let(:match_data) do
      cached = {
        matches: matches[:default].to_h { |v| [v, Version.new(v)] },
        regex:   generated[:regex],
        url:     generated[:url],
        cached:  true,
      }

      {
        cached:,
        cached_default: cached.merge({ matches: {} }),
      }
    end

    it "finds versions in provided content" do
      expect(gnome.find_versions(url: gnome_url, content:))
        .to eq(match_data[:cached])

      # These `strategy` blocks are unnecessary but they are intended to test
      # using a regex in a `strategy` block.
      expect(gnome.find_versions(url: gnome_url, content:) do |page, regex|
        page.scan(regex).map(&:first)
      end).to eq(match_data[:cached])

      expect(gnome.find_versions(url: gnome_url, regex: generated[:regex], content:) do |page, regex|
        page.scan(regex).map(&:first)
      end).to eq(match_data[:cached].merge({ matches: matches[:all].to_h { |v| [v, Version.new(v)] } }))
    end

    it "returns default match_data when content is blank" do
      expect(gnome.find_versions(url: gnome_url, content: ""))
        .to eq(match_data[:cached_default])
    end
  end
end
