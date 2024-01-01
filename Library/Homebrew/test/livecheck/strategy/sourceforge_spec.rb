# frozen_string_literal: true

require "livecheck/strategy/sourceforge"

describe Homebrew::Livecheck::Strategy::Sourceforge do
  subject(:sourceforge) { described_class }

  let(:sourceforge_urls) do
    {
      typical:       "https://downloads.sourceforge.net/project/abc/def-1.2.3.tar.gz",
      rss:           "https://sourceforge.net/projects/abc/rss",
      rss_with_path: "https://sourceforge.net/projects/abc/rss?path=/def",
    }
  end
  let(:non_sourceforge_url) { "https://brew.sh/test" }

  let(:generated) do
    {
      typical: {
        url:   "https://sourceforge.net/projects/abc/rss",
        regex: %r{url=.*?/abc/files/.*?[-_/](\d+(?:[-.]\d+)+)[-_/%.]}i,
      },
      rss:     {
        regex: %r{url=.*?/abc/files/.*?[-_/](\d+(?:[-.]\d+)+)[-_/%.]}i,
      },
    }
  end

  describe "::match?" do
    it "returns true for a SourceForge URL" do
      expect(sourceforge.match?(sourceforge_urls[:typical])).to be true
      expect(sourceforge.match?(sourceforge_urls[:rss])).to be true
      expect(sourceforge.match?(sourceforge_urls[:rss_with_path])).to be true
    end

    it "returns false for a non-SourceForge URL" do
      expect(sourceforge.match?(non_sourceforge_url)).to be false
    end
  end

  describe "::generate_input_values" do
    it "returns a hash containing url and regex for an Apache URL" do
      expect(sourceforge.generate_input_values(sourceforge_urls[:typical])).to eq(generated[:typical])
      expect(sourceforge.generate_input_values(sourceforge_urls[:rss])).to eq(generated[:rss])
      expect(sourceforge.generate_input_values(sourceforge_urls[:rss_with_path])).to eq(generated[:rss])
    end

    it "returns an empty hash for a non-Apache URL" do
      expect(sourceforge.generate_input_values(non_sourceforge_url)).to eq({})
    end
  end
end
