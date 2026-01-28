# frozen_string_literal: true

require "services/system"
require "services/system/systemctl"

RSpec.describe Homebrew::Services::System::Systemctl do
  describe ".scope" do
    it "outputs systemctl scope for user" do
      allow(Homebrew::Services::System).to receive(:root?).and_return(false)
      expect(described_class.scope).to eq("--user")
    end

    it "outputs systemctl scope for root" do
      allow(Homebrew::Services::System).to receive(:root?).and_return(true)
      expect(described_class.scope).to eq("--system")
    end
  end

  describe ".executable" do
    it "outputs systemctl command location", :needs_linux do
      systemctl = Pathname("/bin/systemctl")
      expect(described_class).to receive(:which).and_return(systemctl)
      described_class.reset_executable!

      expect(described_class.executable).to eq(systemctl)
    end
  end
end
