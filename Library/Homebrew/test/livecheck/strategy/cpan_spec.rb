# frozen_string_literal: true

require "livecheck/strategy"

describe Homebrew::Livecheck::Strategy::Cpan do
  subject(:cpan) { described_class }

  let(:cpan_urls) do
    {
      no_subdirectory:   "https://cpan.metacpan.org/authors/id/H/HO/HOMEBREW/Brew-v1.2.3.tar.gz",
      with_subdirectory: "https://cpan.metacpan.org/authors/id/H/HO/HOMEBREW/brew/brew-v1.2.3.tar.gz",
    }
  end
  let(:non_cpan_url) { "https://brew.sh/test" }

  let(:generated) do
    {
      no_subdirectory:   {
        url:   "https://cpan.metacpan.org/authors/id/H/HO/HOMEBREW/",
        regex: /href=.*?Brew[._-]v?(\d+(?:\.\d+)*)\.t/i,
      },
      with_subdirectory: {
        url:   "https://cpan.metacpan.org/authors/id/H/HO/HOMEBREW/brew/",
        regex: /href=.*?brew[._-]v?(\d+(?:\.\d+)*)\.t/i,
      },
    }
  end

  describe "::match?" do
    it "returns true for a CPAN URL" do
      expect(cpan.match?(cpan_urls[:no_subdirectory])).to be true
      expect(cpan.match?(cpan_urls[:with_subdirectory])).to be true
    end

    it "returns false for a non-CPAN URL" do
      expect(cpan.match?(non_cpan_url)).to be false
    end
  end

  describe "::generate_input_values" do
    it "returns a hash containing url and regex for a CPAN URL" do
      expect(cpan.generate_input_values(cpan_urls[:no_subdirectory])).to eq(generated[:no_subdirectory])
      expect(cpan.generate_input_values(cpan_urls[:with_subdirectory])).to eq(generated[:with_subdirectory])
    end

    it "returns an empty hash for a non-CPAN URL" do
      expect(cpan.generate_input_values(non_cpan_url)).to eq({})
    end
  end
end
