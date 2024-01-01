# frozen_string_literal: true

require "livecheck/strategy/gnome"

describe Homebrew::Livecheck::Strategy::Gnome do
  subject(:gnome) { described_class }

  let(:gnome_url) { "https://download.gnome.org/sources/abc/1.2/abc-1.2.3.tar.xz" }
  let(:non_gnome_url) { "https://brew.sh/test" }

  let(:generated) do
    {
      url:   "https://download.gnome.org/sources/abc/cache.json",
      regex: /abc-(\d+(?:\.\d+)*)\.t/i,
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
end
