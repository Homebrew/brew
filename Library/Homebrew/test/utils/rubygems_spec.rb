# frozen_string_literal: true

require "utils/rubygems"

RSpec.describe RubyGems do
  let(:rubygems_gem_url) do
    "https://rubygems.org/gems/concurrent-ruby-1.2.3.gem"
  end
  let(:rubygems_downloads_url) do
    "https://rubygems.org/downloads/treetop-1.6.12.gem"
  end
  let(:non_rubygems_url) do
    "https://github.com/example/gem/archive/v1.0.0.tar.gz"
  end

  describe RubyGems::Gem do
    let(:gem_from_rubygems_url) { described_class.new("concurrent-ruby", rubygems_gem_url) }
    let(:gem_from_downloads_url) { described_class.new("treetop", rubygems_downloads_url) }
    let(:gem_from_non_rubygems_url) { described_class.new("SomeGem", non_rubygems_url) }

    describe "initialize" do
      it "initializes resource name" do
        expect(gem_from_rubygems_url.name).to eq "concurrent-ruby"
      end

      it "extracts version from RubyGems gem URL" do
        expect(gem_from_rubygems_url.current_version).to eq "1.2.3"
      end

      it "extracts version from RubyGems downloads URL" do
        expect(gem_from_downloads_url.current_version).to eq "1.6.12"
      end

      it "handles complex version patterns" do
        complex_url = "https://rubygems.org/gems/rails-7.0.4.3.gem"
        complex_gem = described_class.new("rails", complex_url)
        expect(complex_gem.current_version).to eq "7.0.4.3"
      end
    end

    describe ".valid_rubygems_gem?" do
      it "is true for RubyGems gem URLs" do
        expect(gem_from_rubygems_url.valid_rubygems_gem?).to be true
      end

      it "is true for RubyGems downloads URLs" do
        expect(gem_from_downloads_url.valid_rubygems_gem?).to be true
      end

      it "is false for non-RubyGems URLs" do
        expect(gem_from_non_rubygems_url.valid_rubygems_gem?).to be false
      end
    end

    describe ".to_s" do
      it "returns resource name" do
        expect(gem_from_rubygems_url.to_s).to eq "concurrent-ruby"
      end
    end
  end
end
