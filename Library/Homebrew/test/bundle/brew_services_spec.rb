# frozen_string_literal: true

require "bundle"
require "bundle/brew_services"

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

    it "runs the service" do
      allow(described_class).to receive(:started_services).and_return([])
      expect(Homebrew::Bundle).to receive(:system).with(HOMEBREW_BREW_FILE, "services", "run", "nginx",
                                                        verbose: false).and_return(true)
      expect(described_class.run("nginx")).to be(true)
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

  describe ".versioned_service_file" do
    let(:foo) do
      instance_double(
        Formula,
        name:         "fooformula",
        version:      "1.0",
        rack:         HOMEBREW_CELLAR/"fooformula",
        plist_name:   "homebrew.mxcl.fooformula",
        service_name: "fooformula",
      )
    end

    shared_examples "returns the versioned service file" do
      it "returns the versioned service file" do
        expect(Formula).to receive(:[]).with(foo.name).and_return(foo)
        expect(Homebrew::Bundle).to receive(:formula_versions_from_env).with(foo.name).and_return(foo.version)

        prefix = foo.rack/"1.0"
        allow(FileTest).to receive(:directory?).and_call_original
        expect(FileTest).to receive(:directory?).with(prefix.to_s).and_return(true)

        service_file = prefix/service_basename
        allow(FileTest).to receive(:file?).and_call_original
        expect(FileTest).to receive(:file?).with(service_file.to_s).and_return(true)

        expect(described_class.versioned_service_file(foo.name)).to eq(service_file)
      end
    end

    context "with launchctl" do
      before do
        allow(Homebrew::Services::System).to receive(:launchctl?).and_return(true)
      end

      let(:service_basename) { "#{foo.plist_name}.plist" }

      include_examples "returns the versioned service file"
    end

    context "with systemd" do
      before do
        allow(Homebrew::Services::System).to receive(:launchctl?).and_return(false)
      end

      let(:service_basename) { "#{foo.service_name}.service" }

      include_examples "returns the versioned service file"
    end
  end
end
