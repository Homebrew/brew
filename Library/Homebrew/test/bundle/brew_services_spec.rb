# typed: true
# frozen_string_literal: true

require "bundle"
require "bundle/brew_services"

RSpec.describe Homebrew::Bundle::Brew::Services do
  describe ".started_services" do
    before do
      described_class.reset!
    end

    it "returns started services", :needs_daemon_manager do
      allow(Utils).to receive(:safe_popen_read).and_return <<~JSON
        [
          {
            "name": "nginx",
            "status": "started"
          },
          {
            "name": "apache",
            "status": "stopped"
          },
          {
            "name": "mysql",
            "status": "started"
          }
        ]
      JSON
      expect(described_class.started_services).to contain_exactly("nginx", "mysql")
    end

    it "returns empty array when no services exist", :needs_daemon_manager do
      allow(Utils).to receive(:safe_popen_read).and_return("[]\n")
      expect(described_class.started_services).to eq([])
    end

    it "returns the missing daemon manager fallback when no daemon manager is available" do
      allow(Homebrew::Services::System).to receive_messages(launchctl?: false, systemctl?: false)
      allow(described_class).to receive(:started_services_without_daemon_manager).and_return([])

      expect(described_class.started_services).to eq([])
    end

    it "exits with error on macOS when no daemon manager is available", :needs_macos do
      allow(Homebrew::Services::System).to receive_messages(launchctl?: false, systemctl?: false)
      expect do
        described_class.started_services
      end.to raise_error(SystemExit)
        .and output(/supported only on macOS or Linux/).to_stderr
    end
  end

  describe ".started_services_without_daemon_manager" do
    it "warns and returns an empty array on Linux", :needs_linux do
      expect do
        expect(described_class.started_services_without_daemon_manager).to eq([])
      end.to output(/Skipping `brew services list` due to missing systemctl/).to_stderr
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

  describe "#installed_and_up_to_date?" do
    subject(:services) { described_class.new }

    before do
      described_class.reset!
      allow(described_class).to receive(:started_services).and_return(%w[mailhog])
      allow(services).to receive(:formula_needs_to_start?).and_return(true)
      allow(Homebrew::Bundle::Brew).to receive(:formula_oldnames).and_return({})
    end

    it "matches a tap-qualified formula by base name" do
      entry = instance_double(Homebrew::Bundle::Dsl::Entry, name:    "some-tap/tap/mailhog",
                                                            options: { restart_service: true })
      expect(services.installed_and_up_to_date?(entry)).to be(true)
    end

    it "matches a non-tap-qualified formula by name" do
      entry = instance_double(Homebrew::Bundle::Dsl::Entry, name: "mailhog", options: { restart_service: true })
      expect(services.installed_and_up_to_date?(entry)).to be(true)
    end

    it "returns false when service is not started" do
      entry = instance_double(Homebrew::Bundle::Dsl::Entry, name:    "some-tap/tap/nginx",
                                                            options: { restart_service: true })
      expect(services.installed_and_up_to_date?(entry)).to be(false)
    end
  end

  describe ".versioned_service_file" do
    subject(:foo) do
      instance_double(
        Formula,
        name:          "fooformula",
        version:       "1.0",
        rack:          HOMEBREW_CELLAR/"fooformula",
        plist_name:    "sh.brew.fooformula",
        plist_names:   ["sh.brew.fooformula", "homebrew.mxcl.fooformula"],
        service_name:  "sh.brew.fooformula",
        service_names: ["sh.brew.fooformula", "homebrew.fooformula"],
      )
    end

    shared_examples "returns the versioned service file" do |name, extension|
      it "returns the versioned service file" do
        expect(Formula).to receive(:[]).with(subject.name).and_return(subject)
        expect(Homebrew::Bundle).to receive(:formula_versions_from_env).with(subject.name).and_return(subject.version)

        prefix = subject.rack/"1.0"
        prefix.mkpath
        service_file = prefix/"#{subject.public_send(name)}.#{extension}"
        service_file.write("service")

        expect(described_class.versioned_service_file(subject.name)).to eq(service_file)
      end
    end

    context "with launchctl" do
      before do
        allow(Homebrew::Services::System).to receive(:launchctl?).and_return(true)
      end

      include_examples "returns the versioned service file", :plist_name, "plist"

      it "returns the compatible versioned service file" do
        expect(Formula).to receive(:[]).with(foo.name).and_return(foo)
        expect(Homebrew::Bundle).to receive(:formula_versions_from_env).with(foo.name).and_return(foo.version)

        prefix = foo.rack/foo.version
        prefix.mkpath
        service_file = prefix/"homebrew.mxcl.fooformula.plist"
        (prefix/"sh.brew.fooformula.plist").unlink if (prefix/"sh.brew.fooformula.plist").exist?
        service_file.write("service")

        expect(described_class.versioned_service_file(foo.name)).to eq(service_file)
      end
    end

    context "with systemd" do
      before do
        allow(Homebrew::Services::System).to receive(:launchctl?).and_return(false)
      end

      include_examples "returns the versioned service file", :service_name, "service"

      it "returns the compatible versioned service file" do
        expect(Formula).to receive(:[]).with(foo.name).and_return(foo)
        expect(Homebrew::Bundle).to receive(:formula_versions_from_env).with(foo.name).and_return(foo.version)

        prefix = foo.rack/foo.version
        prefix.mkpath
        service_file = prefix/"homebrew.fooformula.service"
        service_file.write("service")

        expect(described_class.versioned_service_file(foo.name)).to eq(service_file)
      end
    end
  end
end
