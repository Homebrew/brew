# frozen_string_literal: true

require "livecheck/strategy"

describe Homebrew::Livecheck::Strategy::Pypi do
  subject(:pypi) { described_class }

  let(:pypi_url) { "https://files.pythonhosted.org/packages/ab/cd/efg/example-1.2.3.tar.gz" }
  let(:non_pypi_url) { "https://brew.sh/test" }

  let(:generated) do
    {
      url:   "https://pypi.org/project/example/#files",
      regex: %r{href=.*?/packages.*?/example[._-]v?(\d+(?:\.\d+)*(?:[._-]post\d+)?)\.t}i,
    }
  end

  describe "::match?" do
    it "returns true for a PyPI URL" do
      expect(pypi.match?(pypi_url)).to be true
    end

    it "returns false for a non-PyPI URL" do
      expect(pypi.match?(non_pypi_url)).to be false
    end
  end

  describe "::generate_input_values" do
    it "returns a hash containing url and regex for an PyPI URL" do
      expect(pypi.generate_input_values(pypi_url)).to eq(generated)
    end

    it "returns an empty hash for a non-PyPI URL" do
      expect(pypi.generate_input_values(non_pypi_url)).to eq({})
    end
  end
end
