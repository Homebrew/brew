# frozen_string_literal: true

require "livecheck/strategy"

RSpec.describe Homebrew::Livecheck::Strategy::Cpan do
  subject(:cpan) { described_class }

  let(:cpan_urls) do
    {
      no_subdirectory:       "https://cpan.metacpan.org/authors/id/H/HO/HOMEBREW/Brew-v1.2.3.tar.gz",
      with_subdirectory:     "https://cpan.metacpan.org/authors/id/H/HO/HOMEBREW/brew/brew-v1.2.3.tar.gz",
      no_subdirectory_www:   "https://www.cpan.org/authors/id/H/HO/HOMEBREW/Brew-v1.2.3.tar.gz",
      with_subdirectory_www: "https://www.cpan.org/authors/id/H/HO/HOMEBREW/brew/brew-v1.2.3.tar.gz",
    }
  end
  let(:non_cpan_url) { "https://brew.sh/test" }

  let(:generated) do
    {
      no_subdirectory:   {
        url:   "https://www.cpan.org/authors/id/H/HO/HOMEBREW/",
        regex: /href=.*?Brew[._-]v?(\d+(?:\.\d+)*)\.t/i,
      },
      with_subdirectory: {
        url:   "https://www.cpan.org/authors/id/H/HO/HOMEBREW/brew/",
        regex: /href=.*?brew[._-]v?(\d+(?:\.\d+)*)\.t/i,
      },
    }
  end

  # CPAN doesn't specify a DOCTYPE, so it's also omitted here.
  let(:content) do
    <<~EOS
      <html>
      <head>
        <title>Index of /authors/id/H/HO/HOMEBREW/</title>
      </head>
      <body bgcolor="white">
        <h1>Index of /authors/id/H/HO/HOMEBREW/</h1>
        <hr>
        <pre>
          <a href="../">../</a>
          <a href="Brew-1.2.1.meta">Brew-1.2.1.meta</a>                                 01-Jan-2022 01:21               23456
          <a href="Brew-1.2.1.readme">Brew-1.2.1.readme</a>                               01-Jan-2022 01:21                2345
          <a href="Brew-1.2.1.tar.gz">Brew-1.2.1.tar.gz</a>                               01-Jan-2022 01:21             2345678
          <a href="Brew-1.2.2.meta">Brew-1.2.2.meta</a>                                 02-Jan-2022 01:22               34567
          <a href="Brew-1.2.2.readme">Brew-1.2.2.readme</a>                               02-Jan-2022 01:22                3456
          <a href="Brew-1.2.2.tar.gz">Brew-1.2.2.tar.gz</a>                               02-Jan-2022 01:22             3456789
          <a href="Brew-1.2.3.meta">Brew-1.2.3.meta</a>                                 03-Jan-2022 01:23               45678
          <a href="Brew-1.2.3.readme">Brew-1.2.3.readme</a>                               03-Jan-2022 01:23                4567
          <a href="Brew-1.2.3.tar.gz">Brew-1.2.3.tar.gz</a>                               03-Jan-2022 01:23             4567890
          <a href="CHECKSUMS">CHECKSUMS</a>                                          04-Jan-2022 01:24               12345
        </pre>
        <hr>
      </body>
      </html>

    EOS
  end

  let(:matches) { ["1.2.3", "1.2.2", "1.2.1"] }

  describe "::match?" do
    it "returns true for a CPAN URL" do
      expect(cpan.match?(cpan_urls[:no_subdirectory])).to be true
      expect(cpan.match?(cpan_urls[:with_subdirectory])).to be true
      expect(cpan.match?(cpan_urls[:no_subdirectory_www])).to be true
      expect(cpan.match?(cpan_urls[:with_subdirectory_www])).to be true
    end

    it "returns false for a non-CPAN URL" do
      expect(cpan.match?(non_cpan_url)).to be false
    end
  end

  describe "::generate_input_values" do
    it "returns a hash containing url and regex for a CPAN URL" do
      expect(cpan.generate_input_values(cpan_urls[:no_subdirectory])).to eq(generated[:no_subdirectory])
      expect(cpan.generate_input_values(cpan_urls[:with_subdirectory])).to eq(generated[:with_subdirectory])
      expect(cpan.generate_input_values(cpan_urls[:no_subdirectory_www])).to eq(generated[:no_subdirectory])
      expect(cpan.generate_input_values(cpan_urls[:with_subdirectory_www])).to eq(generated[:with_subdirectory])
    end

    it "returns an empty hash for a non-CPAN URL" do
      expect(cpan.generate_input_values(non_cpan_url)).to eq({})
    end
  end

  describe "::find_versions" do
    let(:match_data) do
      cached = {
        matches: matches.to_h { |v| [v, Version.new(v)] },
        regex:   generated[:no_subdirectory][:regex],
        url:     generated[:no_subdirectory][:url],
        cached:  true,
      }

      {
        cached:,
        cached_default: cached.merge({ matches: {} }),
      }
    end

    it "finds versions in provided content" do
      expect(cpan.find_versions(url: cpan_urls[:no_subdirectory], content:))
        .to eq(match_data[:cached])

      # This `strategy` block is unnecessary but it's intended to test using a
      # generated regex in a `strategy` block.
      expect(cpan.find_versions(url: cpan_urls[:no_subdirectory], content:) do |page, regex|
        page.scan(regex).map(&:first)
      end).to eq(match_data[:cached])
    end

    it "returns default match_data when content is blank" do
      expect(cpan.find_versions(url: cpan_urls[:no_subdirectory], content: ""))
        .to eq(match_data[:cached_default])
    end
  end
end
