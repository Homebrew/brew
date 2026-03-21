# frozen_string_literal: true

require "cask/url"

RSpec.describe Cask::URL do
  describe "#github_server_url" do
    it "is nil when not provided" do
      url = described_class.new("https://github.com/homebrew/brew/archive/1.0.tar.gz")
      expect(url.github_server_url).to be_nil
    end

    it "stores the provided GitHub server URL" do
      url = described_class.new("https://github.example.com/org/repo.git",
                                using:             :github_git,
                                github_server_url: "https://github.example.com")
      expect(url.github_server_url).to eq("https://github.example.com")
    end

    it "includes github_server_url in specs when set" do
      url = described_class.new("https://github.example.com/org/repo.git",
                                github_server_url: "https://github.example.com")
      expect(url.specs[:github_server_url]).to eq("https://github.example.com")
    end

    it "does not include github_server_url in specs when nil" do
      url = described_class.new("https://github.com/homebrew/brew/archive/1.0.tar.gz")
      expect(url.specs).not_to have_key(:github_server_url)
    end
  end
end
