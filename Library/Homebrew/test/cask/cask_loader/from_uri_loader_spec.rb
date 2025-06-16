# frozen_string_literal: true

RSpec.describe Cask::CaskLoader::FromURILoader do
  describe "::try_new" do
    it "returns a loader when given an URI" do
      expect(described_class.try_new(URI("https://brew.sh/"))).not_to be_nil
    end

    it "returns a loader when given a string which can be parsed to a URI" do
      expect(described_class.try_new("https://brew.sh/")).not_to be_nil
    end

    it "returns nil when path loading is disabled" do
      ENV["HOMEBREW_FORBID_PACKAGES_FROM_PATHS"] = "1"
      expect(described_class.try_new(URI("file://#{TEST_FIXTURE_DIR}/cask/Casks/local-caffeine.rb"))).to be_nil
    end

    it "returns nil when given a string with Cask contents containing a URL" do
      expect(described_class.try_new(<<~RUBY)).to be_nil
        cask 'token' do
          url 'https://brew.sh/'
        end
      RUBY
    end
  end

  describe "::load" do
    it "raises an error when given an https URL" do
      loader = described_class.new("https://brew.sh/foo.rb")
      expect do
        loader.load(config: nil)
      end.to raise_error(UnsupportedInstallationMethod)
    end

    it "raises an error when given an ftp URL" do
      loader = described_class.new("ftp://brew.sh/foo.rb")
      expect do
        loader.load(config: nil)
      end.to raise_error(UnsupportedInstallationMethod)
    end

    it "raises an error when given an sftp URL" do
      loader = described_class.new("sftp://brew.sh/foo.rb")
      expect do
        loader.load(config: nil)
      end.to raise_error(UnsupportedInstallationMethod)
    end

    it "does not raise an error when given a file URL" do
      loader = described_class.new("file://#{TEST_FIXTURE_DIR}/cask/Casks/local-caffeine.rb")
      expect do
        loader.load(config: nil)
      end.not_to raise_error(UnsupportedInstallationMethod)
    end
  end
end
