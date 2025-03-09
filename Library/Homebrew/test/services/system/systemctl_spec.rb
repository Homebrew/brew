# frozen_string_literal: true

require "services/service"

RSpec.describe Service::System::Systemctl do
  describe ".scope" do
    it "outputs systemctl scope for user" do
      allow(Service::System).to receive(:root?).and_return(false)
      expect(described_class.scope).to eq("--user")
    end

    it "outputs systemctl scope for root" do
      allow(Service::System).to receive(:root?).and_return(true)
      expect(described_class.scope).to eq("--system")
    end
  end

  describe ".executable" do
    it "outputs systemctl command location", :needs_linux do
      expect(described_class.executable).to eq("/bin/systemctl")
    end
  end
end
