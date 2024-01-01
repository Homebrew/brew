# frozen_string_literal: true

describe Cask::CaskLoader::FromURILoader do
  alias_matcher :be_able_to_load, :be_can_load

  describe "::can_load?" do
    it "returns true when given an URI" do
      expect(described_class).to be_able_to_load(URI("https://brew.sh/"))
    end

    it "returns true when given a String which can be parsed to a URI" do
      expect(described_class).to be_able_to_load("https://brew.sh/")
    end

    it "returns false when given a String with Cask contents containing a URL" do
      expect(described_class).not_to be_able_to_load <<~RUBY
        cask 'token' do
          url 'https://brew.sh/'
        end
      RUBY
    end
  end
end
