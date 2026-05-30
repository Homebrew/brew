# typed: true
# frozen_string_literal: true

require "locale"
require "os/linux"

RSpec.describe OS::Linux do
  let(:klass) { OS::Linux }

  describe "::languages", :needs_linux do
    it "returns a list of all languages" do
      expect(klass.languages).not_to be_empty
    end
  end

  describe "::language", :needs_linux do
    it "returns the first item from #languages" do
      expect(klass.language).to eq(klass.languages.first)
    end
  end

  describe "::'os_version'", :needs_linux do
    it "returns the OS version" do
      expect(klass.os_version).not_to be_empty
    end
  end

  describe "::'wsl?'" do
    it "returns the WSL state" do
      expect(klass.wsl?).to be(false)
    end
  end

  describe "::'wsl_version'", :needs_linux do
    it "returns the WSL version" do
      expect(klass.wsl_version).to match(Version::NULL)
    end
  end
end
