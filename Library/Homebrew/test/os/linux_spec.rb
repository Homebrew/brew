# typed: false
# frozen_string_literal: true

require "locale"
require "os/linux"

RSpec.describe OS::Linux do
  around do |example|
    had_cached_kernel_version = OS.instance_variable_defined?(:@kernel_version)
    cached_kernel_version = OS.instance_variable_get(:@kernel_version) if had_cached_kernel_version
    # OS.kernel_version is memoized, so isolate these examples from the host kernel cache.
    OS.remove_instance_variable(:@kernel_version) if had_cached_kernel_version
    example.run
  ensure
    if had_cached_kernel_version
      OS.instance_variable_set(:@kernel_version, cached_kernel_version)
    elsif OS.instance_variable_defined?(:@kernel_version)
      OS.remove_instance_variable(:@kernel_version)
    end
  end

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
      # The host running the tests may itself be WSL, so make the non-WSL case explicit.
      allow(OS).to receive(:kernel_version).and_return("6.8.0-1000-generic")
      expect(described_class.wsl?).to be(false)
    end

    it "returns true for a WSL kernel" do
      # Exercise WSL detection without depending on the current kernel.
      allow(OS).to receive(:kernel_version).and_return("5.15.153.1-microsoft-standard-WSL2")
      expect(described_class.wsl?).to be(true)
    end
  end

  describe "::'wsl_version'", :needs_linux do
    it "returns a null version outside WSL" do
      # The host running the tests may itself be WSL, so make the non-WSL case explicit.
      allow(OS).to receive(:kernel_version).and_return("6.8.0-1000-generic")
      expect(described_class.wsl_version).to match(Version::NULL)
    end

    it "returns the WSL version" do
      # Exercise WSL version parsing without depending on the current kernel.
      allow(OS).to receive(:kernel_version).and_return("5.15.153.1-microsoft-standard-WSL2")
      expect(described_class.wsl_version).to eq(Version.new("2 (Microsoft Store)"))
    end
  end
end
