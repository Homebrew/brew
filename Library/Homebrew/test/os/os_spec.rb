# frozen_string_literal: true

describe OS do
  describe "::kernel_version" do
    it "is not NULL" do
      expect(described_class.kernel_version).not_to be_null
    end
  end

  describe "::kernel_name" do
    it "returns Linux on Linux", :needs_linux do
      expect(described_class.kernel_name).to eq "Linux"
    end

    it "returns Darwin on macOS", :needs_macos do
      expect(described_class.kernel_name).to eq "Darwin"
    end
  end
end
