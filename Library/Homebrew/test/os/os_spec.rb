# typed: true
# frozen_string_literal: true

RSpec.describe OS do
  let(:klass) { OS }

  describe "::kernel_version" do
    it "is not NULL" do
      expect(klass.kernel_version).not_to be_null
    end
  end

  describe "::kernel_name" do
    it "returns Linux on Linux", :needs_linux do
      expect(klass.kernel_name).to eq "Linux"
    end

    it "returns Darwin on macOS", :needs_macos do
      expect(klass.kernel_name).to eq "Darwin"
    end
  end
end
