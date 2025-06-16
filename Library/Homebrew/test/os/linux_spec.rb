# frozen_string_literal: true

require "locale"
require "os/linux"

RSpec.describe OS::Linux do
  describe "::languages", :needs_linux do
    it "returns a list of all languages" do
      expect(described_class.languages).not_to be_empty
    end
  end

  describe "::language", :needs_linux do
    it "returns the first item from #languages" do
      expect(described_class.language).to eq(described_class.languages.first)
    end
  end

  describe "::'os_version'", :needs_linux do
    it "returns the OS version" do
      expect(described_class.os_version).not_to be_empty
    end
  end

  describe "::'wsl?'" do
    it "returns the WSL state" do
      expect(described_class.wsl?).to be(false)
    end
  end

  describe "::'wsl_version'", :needs_linux do
    it "returns the WSL version" do
      expect(described_class.wsl_version).to match(Version::NULL)
    end
  end
end
