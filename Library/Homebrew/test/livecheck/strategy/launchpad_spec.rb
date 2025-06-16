# frozen_string_literal: true

require "livecheck/strategy/launchpad"

RSpec.describe Homebrew::Livecheck::Strategy::Launchpad do
  subject(:launchpad) { described_class }

  let(:launchpad_urls) do
    {
      version_dir:    "https://launchpad.net/abc/1.2/1.2.3/+download/abc-1.2.3.tar.gz",
      trunk:          "https://launchpad.net/abc/trunk/1.2.3/+download/abc-1.2.3.tar.gz",
      code_subdomain: "https://code.launchpad.net/abc/1.2/1.2.3/+download/abc-1.2.3.tar.gz",
    }
  end
  let(:non_launchpad_url) { "https://brew.sh/test" }

  let(:generated) do
    {
      url: "https://launchpad.net/abc/",
    }
  end

  describe "::match?" do
    it "returns true for a Launchpad URL" do
      expect(launchpad.match?(launchpad_urls[:version_dir])).to be true
      expect(launchpad.match?(launchpad_urls[:trunk])).to be true
      expect(launchpad.match?(launchpad_urls[:code_subdomain])).to be true
    end

    it "returns false for a non-Launchpad URL" do
      expect(launchpad.match?(non_launchpad_url)).to be false
    end
  end

  describe "::generate_input_values" do
    it "returns a hash containing url and regex for an Launchpad URL" do
      expect(launchpad.generate_input_values(launchpad_urls[:version_dir])).to eq(generated)
      expect(launchpad.generate_input_values(launchpad_urls[:trunk])).to eq(generated)
      expect(launchpad.generate_input_values(launchpad_urls[:code_subdomain])).to eq(generated)
    end

    it "returns an empty hash for a non-Launchpad URL" do
      expect(launchpad.generate_input_values(non_launchpad_url)).to eq({})
    end
  end
end
