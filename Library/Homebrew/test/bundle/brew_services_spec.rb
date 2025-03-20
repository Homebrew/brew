# frozen_string_literal: true

require "bundle"

RSpec.describe Homebrew::Bundle::BrewServices do
  describe ".started_services" do
    before do
      described_class.reset!
    end

    it "returns started services" do
      allow(Utils).to receive(:safe_popen_read).and_return <<~EOS
        nginx  started  homebrew.mxcl.nginx.plist
        apache stopped  homebrew.mxcl.apache.plist
        mysql  started  homebrew.mxcl.mysql.plist
      EOS
      expect(described_class.started_services).to contain_exactly("nginx", "mysql")
    end
  end

  context "when brew-services is installed" do
    context "when the service is stopped" do
      it "when the service is started" do
        allow(described_class).to receive(:started_services).and_return(%w[nginx])
        expect(Homebrew::Bundle).to receive(:system).with(HOMEBREW_BREW_FILE, "services", "stop", "nginx",
                                                          verbose: false).and_return(true)
        expect(described_class.stop("nginx")).to be(true)
        expect(described_class.started_services).not_to include("nginx")
      end

      it "when the service is already stopped" do
        allow(described_class).to receive(:started_services).and_return(%w[])
        expect(Homebrew::Bundle).not_to receive(:system).with(HOMEBREW_BREW_FILE, "services", "stop", "nginx",
                                                              verbose: false)
        expect(described_class.stop("nginx")).to be(true)
        expect(described_class.started_services).not_to include("nginx")
      end
    end

    it "starts the service" do
      allow(described_class).to receive(:started_services).and_return([])
      expect(Homebrew::Bundle).to receive(:system).with(HOMEBREW_BREW_FILE, "services", "start", "nginx",
                                                        verbose: false).and_return(true)
      expect(described_class.start("nginx")).to be(true)
      expect(described_class.started_services).to include("nginx")
    end

    it "restarts the service" do
      allow(described_class).to receive(:started_services).and_return([])
      expect(Homebrew::Bundle).to receive(:system).with(HOMEBREW_BREW_FILE, "services", "restart", "nginx",
                                                        verbose: false).and_return(true)
      expect(described_class.restart("nginx")).to be(true)
      expect(described_class.started_services).to include("nginx")
    end
  end
end
