# typed: true
# frozen_string_literal: true

require "livecheck/strategy"

RSpec.describe Homebrew::Livecheck::Strategy::Crate do
  subject(:crate) { described_class }

  let(:crate_url) { "https://static.crates.io/crates/example/example-0.1.0.crate" }
  let(:non_crate_url) { "https://brew.sh/test" }
  # This only differs from the `DEFAULT_REGEX` so we can distinguish between a
  # provided regex and the default strategy regex in testing.
  let(:regex) { /v?(\d+(?:\.\d+)+)/i }
  let(:generated) do
    { url: "https://index.crates.io/ex/am/example" }
  end
  # This is a limited subset of a crate index response object, for the sake of
  # testing.
  let(:content) do
    <<~JSON
      {"name":"example","vers":"1.0.2","deps":[],"cksum":"101295d6a1a7041f119b598a52bab4ac4a3aed89493f22b338d74b3caf4f9abc","features":{},"yanked":false,"pubtime":"2023-12-06T19:55:15Z"}
      {"name":"example","vers":"1.1.0","deps":[],"cksum":"0b6a23e249717cd6d24a8f3fcd9639403948df1227fe303a106396597a68277e","features":{},"yanked":false,"pubtime":"2023-12-06T19:56:05Z"}
      {"name":"example","vers":"1.1.1","deps":[],"cksum":"14608893613d97a992770c78686f17d73b8d99ed5e920057c7b5fd50581924fc","features":{},"yanked":true,"pubtime":"2023-12-06T19:56:37Z"}
    JSON
  end
  let(:matches) { ["1.0.2", "1.1.0"] }

  describe "::match?" do
    it "returns true for a crate URL" do
      expect(crate.match?(crate_url)).to be true
    end

    it "returns false for a non-crate URL" do
      expect(crate.match?(non_crate_url)).to be false
    end
  end

  describe "::generate_input_values" do
    it "returns a hash containing url for a crate URL" do
      expect(crate.generate_input_values(crate_url)).to eq(generated)
    end

    it "returns an empty hash for a non-crate URL" do
      expect(crate.generate_input_values(non_crate_url)).to eq({})
    end

    it "handles 1-character package name" do
      expect(crate.generate_input_values("https://static.crates.io/crates/a/a-0.1.1.crate"))
        .to eq({ url: "https://index.crates.io/1/a" })
    end

    it "handles 2-character package name" do
      expect(crate.generate_input_values("https://static.crates.io/crates/cc/cc-1.11.0.crate"))
        .to eq({ url: "https://index.crates.io/2/cc" })
    end

    it "handles 3-character package name" do
      expect(crate.generate_input_values("https://static.crates.io/crates/syn/syn-3.0.9.crate"))
        .to eq({ url: "https://index.crates.io/3/s/syn" })
    end
  end

  describe "::find_versions" do
    let(:match_data) do
      base = {
        matches: matches.to_h { |v| [v, Version.new(v)] },
        regex:   nil,
        url:     generated[:url],
      }

      {
        fetched:        base.merge({ content: }),
        cached:         base.merge({ cached: true }),
        cached_default: base.merge({ matches: {}, cached: true }),
      }
    end

    it "finds versions in fetched content" do
      allow(Homebrew::Livecheck::Strategy).to receive(:page_content).and_return({ content: })

      expect(Homebrew::Livecheck::Strategy).to receive(:page_content)
        .at_least(:once)
        .with(generated[:url], options: Homebrew::Livecheck::Options.new)
      expect(crate.find_versions(url: crate_url, regex:))
        .to eq(match_data[:fetched].merge({ regex: }))
      expect(crate.find_versions(url: crate_url)).to eq(match_data[:fetched])
    end

    it "finds versions in fetched content using explicit user_agent" do
      allow(Homebrew::Livecheck::Strategy).to receive(:page_content).and_return({ content: })

      options = Homebrew::Livecheck::Options.new(user_agent: :curl)
      expect(Homebrew::Livecheck::Strategy).to receive(:page_content)
        .at_least(:once)
        .with(generated[:url], options:)
      expect(crate.find_versions(url: crate_url, options:))
        .to eq(match_data[:fetched])
    end

    it "finds versions in provided content" do
      expect(crate.find_versions(url: crate_url, regex:, content:))
        .to eq(match_data[:cached].merge({ regex: }))

      expect(crate.find_versions(url: crate_url, content:))
        .to eq(match_data[:cached])
    end

    it "finds versions in provided content using a block" do
      expect(crate.find_versions(url: crate_url, regex:, content:) do |json, regex|
        next if json["yanked"] == true
        next if (match = json["vers"]&.match(regex)).blank?

        match[1]
      end).to eq(match_data[:cached].merge({ regex: }))

      expect(crate.find_versions(url: crate_url, content:) do |json|
        next if json["yanked"] == true
        next if (match = json["vers"]&.match(regex)).blank?

        match[1]
      end).to eq(match_data[:cached])
    end

    it "returns default match_data when block doesn't return version information" do
      no_match_regex = /will_not_match/i

      expect(crate.find_versions(url: crate_url, content: '{"other":true}'))
        .to eq(match_data[:cached_default])
      expect(crate.find_versions(url: crate_url, content: '{"versions":[{}]}'))
        .to eq(match_data[:cached_default])
      expect(crate.find_versions(url: crate_url, regex: no_match_regex, content:))
        .to eq(match_data[:cached_default].merge({ regex: no_match_regex }))
    end

    it "returns default match_data when url is blank" do
      expect(crate.find_versions(url: ""))
        .to eq({ matches: {}, regex: nil, url: "" })
    end

    it "returns default match_data when content is blank" do
      expect(crate.find_versions(url: crate_url, content: "{}"))
        .to eq(match_data[:cached_default])
      expect(crate.find_versions(url: crate_url, content: ""))
        .to eq(match_data[:cached_default])
    end
  end
end
