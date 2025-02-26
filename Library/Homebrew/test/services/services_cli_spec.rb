# frozen_string_literal: true

require "services/service"

RSpec.describe Service::ServicesCli do
  subject(:services_cli) { described_class }

  let(:service_string) { "service" }

  describe "#bin" do
    it "outputs command name" do
      expect(services_cli.bin).to eq("brew services")
    end
  end

  describe "#running" do
    it "macOS - returns the currently running services" do
      allow(Service::System).to receive_messages(launchctl?: true, systemctl?: false)
      allow(Utils).to receive(:popen_read).and_return <<~EOS
        77513   50  homebrew.mxcl.php
        495     0   homebrew.mxcl.node_exporter
        1234    34  homebrew.mxcl.postgresql@14
      EOS
      expect(services_cli.running).to eq([
        "homebrew.mxcl.php",
        "homebrew.mxcl.node_exporter",
        "homebrew.mxcl.postgresql@14",
      ])
    end

    it "systemD - returns the currently running services" do
      allow(Service::System).to receive(:launchctl?).and_return(false)
      allow(Service::System::Systemctl).to receive(:popen_read).and_return <<~EOS
        homebrew.php.service     loaded active running Homebrew PHP service
        systemd-udevd.service    loaded active running Rule-based Manager for Device Events and Files
        udisks2.service          loaded active running Disk Manager
        user@1000.service        loaded active running User Manager for UID 1000
      EOS
      expect(services_cli.running).to eq(["homebrew.php.service"])
    end
  end

  describe "#check" do
    it "checks the input does not exist" do
      expect do
        services_cli.check([])
      end.to raise_error(UsageError,
                         a_string_including("Formula(e) missing, please provide a formula name or use --all"))
    end

    it "checks the input exists" do
      expect do
        services_cli.check("hello")
      end.not_to raise_error(UsageError,
                             a_string_including("Formula(e) missing, please provide a formula name or use --all"))
    end
  end

  describe "#kill_orphaned_services" do
    it "skips unmanaged services" do
      service = instance_double(service_string, name: "example_service")
      allow(services_cli).to receive(:running).and_return(["example_service"])
      allow(Service::FormulaWrapper).to receive(:from).and_return(service)
      expect do
        services_cli.kill_orphaned_services
      end.to output("Service example_service not managed by `brew services` => skipping\n").to_stdout
    end

    it "tries but is unable to kill a non existing service" do
      service = instance_double(
        service_string,
        name:        "example_service",
        pid?:        true,
        dest:        Pathname("this_path_does_not_exist"),
        keep_alive?: false,
      )
      allow(service).to receive(:service_name)
      allow(Service::FormulaWrapper).to receive(:from).and_return(service)
      allow(services_cli).to receive(:running).and_return(["example_service"])
      expect do
        services_cli.kill_orphaned_services
      end.to output(a_string_including("Killing `example_service`... (might take a while)")).to_stdout.and
      output(a_string_including("Unable to kill `example_service` (label: )")).to_stderr
    end
  end

  describe "#run" do
    it "checks empty targets cause no error" do
      expect(Service::System).not_to receive(:root?)
      services_cli.run([])
    end

    it "checks if target service is already running and suggests restart instead" do
      expected_output = "Service `example_service` already running, " \
                        "use `brew services restart example_service` to restart.\n"
      service = instance_double(service_string, name: "example_service", pid?: true)
      expect do
        services_cli.run([service])
      end.to output(expected_output).to_stdout
    end
  end

  describe "#start" do
    it "checks missing file causes error" do
      expect(Service::System).not_to receive(:root?)
      expect do
        services_cli.start(["service_name"], "/hfdkjshksdjhfkjsdhf/fdsjghsdkjhb")
      end.to raise_error(UsageError, a_string_including("Provided service file does not exist"))
    end

    it "checks empty targets cause no error" do
      expect(Service::System).not_to receive(:root?)
      services_cli.start([])
    end

    it "checks if target service has already been started and suggests restart instead" do
      expected_output = "Service `example_service` already started, " \
                        "use `brew services restart example_service` to restart.\n"
      service = instance_double(service_string, name: "example_service", pid?: true)
      expect do
        services_cli.start([service])
      end.to output(expected_output).to_stdout
    end
  end

  describe "#stop" do
    it "checks empty targets cause no error" do
      expect(Service::System).not_to receive(:root?)
      services_cli.stop([])
    end
  end

  describe "#kill" do
    it "checks empty targets cause no error" do
      expect(Service::System).not_to receive(:root?)
      services_cli.kill([])
    end

    it "prints a message if service is not running" do
      expected_output = "Service `example_service` is not started.\n"
      service = instance_double(service_string, name: "example_service", pid?: false)
      expect do
        services_cli.kill([service])
      end.to output(expected_output).to_stdout
    end

    it "prints a message if service is set to keep alive" do
      expected_output = "Service `example_service` is set to automatically restart and can't be killed.\n"
      service = instance_double(service_string, name: "example_service", pid?: true, keep_alive?: true)
      expect do
        services_cli.kill([service])
      end.to output(expected_output).to_stdout
    end
  end

  describe "#install_service_file" do
    it "checks service is installed" do
      service = instance_double(Service::FormulaWrapper, name: "name", installed?: false)
      expect do
        services_cli.install_service_file(service, nil)
      end.to raise_error(UsageError, a_string_including("Formula `name` is not installed"))
    end

    it "checks service file exists" do
      service = instance_double(
        Service::FormulaWrapper,
        name:         "name",
        installed?:   true,
        service_file: instance_double(Pathname, exist?: false),
      )
      expect do
        services_cli.install_service_file(service, nil)
      end.to raise_error(
        UsageError,
        a_string_including(
          "Formula `name` has not implemented #plist, #service or installed a locatable service file",
        ),
      )
    end
  end

  describe "#systemd_load", :needs_linux do
    it "checks non-enabling run" do
      expect(Service::System::Systemctl).to receive(:executable).once.and_return("/bin/systemctl")
      expect(Service::System::Systemctl).to receive(:scope).once.and_return("--user")
      services_cli.systemd_load(
        instance_double(Service::FormulaWrapper, service_name: "name"),
        enable: false,
      )
    end

    it "checks enabling run" do
      expect(Service::System::Systemctl).to receive(:executable).twice.and_return("/bin/systemctl")
      expect(Service::System::Systemctl).to receive(:scope).twice.and_return("--user")
      services_cli.systemd_load(
        instance_double(Service::FormulaWrapper, service_name: "name"),
        enable: true,
      )
    end
  end

  describe "#launchctl_load", :needs_macos do
    it "checks non-enabling run" do
      expect(Service::System).to receive(:domain_target).once.and_return("target")
      expect(Service::System).to receive(:launchctl).once.and_return("/bin/launchctl")
      services_cli.launchctl_load(instance_double(Service::FormulaWrapper), file: "a", enable: false)
    end

    it "checks enabling run" do
      expect(Service::System).to receive(:domain_target).twice.and_return("target")
      expect(Service::System).to receive(:launchctl).twice.and_return("/bin/launchctl")
      services_cli.launchctl_load(instance_double(Service::FormulaWrapper, service_name: "name"), file:   "a",
                                                                                                  enable: true)
    end
  end

  describe "#service_load" do
    it "checks non-root for login" do
      expect(Service::System).to receive(:launchctl?).once.and_return(false)
      expect(Service::System).to receive(:systemctl?).once.and_return(false)
      expect(Service::System).to receive(:root?).once.and_return(true)

      expect do
        services_cli.service_load(
          instance_double(Service::FormulaWrapper, name: "name", service_name: "service.name",
service_startup?: false), enable: false
        )
      end.to output(a_string_including("Successfully ran `name` (label: service.name)")).to_stdout.and
      output(a_string_including("name must be run as non-root to start at user login!")).to_stderr
    end

    it "checks root for startup" do
      expect(Service::System).to receive(:launchctl?).once.and_return(false)
      expect(Service::System).to receive(:systemctl?).once.and_return(false)
      expect(Service::System).to receive(:root?).twice.and_return(false)
      expect do
        services_cli.service_load(
          instance_double(Service::FormulaWrapper, name: "name", service_name: "service.name",
service_startup?: true),
          enable: false,
        )
      end.to output(a_string_including("Successfully ran `name` (label: service.name)")).to_stdout.and
      output(a_string_including("name must be run as root to start at system startup!")).to_stderr
    end

    it "triggers launchctl" do
      expect(Service::System).to receive(:domain_target).once.and_return("target")
      expect(Service::System).to receive(:launchctl?).once.and_return(true)
      expect(Service::System).to receive(:launchctl).once
      expect(Service::System).not_to receive(:systemctl?)
      expect(Service::System).to receive(:root?).twice.and_return(false)
      expect do
        services_cli.service_load(
          instance_double(Service::FormulaWrapper, name: "name", service_name: "service.name",
service_startup?: false), enable: false
        )
      end.to output("Successfully ran `name` (label: service.name)\n").to_stdout
    end

    it "triggers systemctl" do
      expect(Service::System).to receive(:launchctl?).once.and_return(false)
      expect(Service::System).to receive(:systemctl?).once.and_return(true)
      expect(Service::System).to receive(:root?).thrice.and_return(false)
      expect do
        services_cli.service_load(
          instance_double(
            Service::FormulaWrapper,
            name:             "name",
            service_name:     "service.name",
            service_startup?: false,
            dest:             instance_double(Pathname, exist?: true),
          ),
          enable: false,
        )
      end.to output("Successfully ran `name` (label: service.name)\n").to_stdout
    end

    it "represents correct action" do
      expect(Service::System).to receive(:launchctl?).once.and_return(false)
      expect(Service::System).to receive(:systemctl?).once.and_return(true)
      expect(Service::System).to receive(:root?).exactly(4).times.and_return(false)
      expect do
        services_cli.service_load(
          instance_double(
            Service::FormulaWrapper,
            name:             "name",
            service_name:     "service.name",
            service_startup?: false,
            dest:             instance_double(Pathname, exist?: true),
          ),
          enable: true,
        )
      end.to output("Successfully started `name` (label: service.name)\n").to_stdout
    end
  end
end
