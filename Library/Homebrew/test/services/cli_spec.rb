# typed: false
# frozen_string_literal: true

require "services/cli"
require "services/system"
require "services/formula_wrapper"

RSpec.describe Homebrew::Services::Cli do
  subject(:services_cli) { described_class }

  let(:service_string) { "service" }

  describe "#bin" do
    it "outputs command name" do
      expect(services_cli.bin).to eq("brew services")
    end
  end

  describe "#running" do
    it "macOS - returns the currently running services" do
      allow(Homebrew::Services::System).to receive_messages(launchctl?: true, systemctl?: false)
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
      allow(Homebrew::Services::System).to receive(:launchctl?).and_return(false)
      allow(Homebrew::Services::System::Systemctl).to receive(:popen_read).and_return <<~EOS
        homebrew.php.service     loaded active running Homebrew PHP service
        systemd-udevd.service    loaded active running Rule-based Manager for Device Events and Files
        udisks2.service          loaded active running Disk Manager
        user@1000.service        loaded active running User Manager for UID 1000
      EOS
      expect(services_cli.running).to eq(["homebrew.php.service"])
    end
  end

  describe "#check!" do
    it "checks the input does not exist" do
      expect do
        services_cli.check!([])
      end.to raise_error(UsageError,
                         "Invalid usage: Formula(e) missing, please provide a formula name or use `--all`.")
    end

    it "checks the input exists" do
      service = instance_double(Homebrew::Services::FormulaWrapper, name: "name", installed?: false)
      expect do
        services_cli.check!([service])
      end.not_to raise_error
    end
  end

  describe "#kill_orphaned_services" do
    it "skips unmanaged services" do
      allow(services_cli).to receive(:running).and_return(["example_service"])
      expect do
        services_cli.kill_orphaned_services
      end.to output("Warning: Service example_service not managed by `brew services` => skipping\n").to_stderr
    end

    it "tries but is unable to kill a non existing service" do
      service = instance_double(
        service_string,
        name:         "example_service",
        service_name: "homebrew.example_service",
        pid?:         true,
        dest:         Pathname("this_path_does_not_exist"),
        keep_alive?:  false,
      )
      allow(service).to receive(:reset_cache!)
      allow(Homebrew::Services::FormulaWrapper).to receive(:from).and_return(service)
      allow(services_cli).to receive(:running).and_return(["example_service"])
      expect do
        services_cli.kill_orphaned_services
      end.to output("Killing `example_service`... (might take a while)\n").to_stdout
    end
  end

  describe "#run" do
    it "checks missing file causes error" do
      expect(Homebrew::Services::System).not_to receive(:root?)
      service = instance_double(Homebrew::Services::FormulaWrapper, name: "service_name")
      expect do
        services_cli.start([service], "/non/existent/path")
      end.to raise_error(UsageError, "Invalid usage: Provided service file does not exist.")
    end

    it "checks empty targets cause no error" do
      expect(Homebrew::Services::System).not_to receive(:root?)
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
      expect(Homebrew::Services::System).not_to receive(:root?)
      service = instance_double(Homebrew::Services::FormulaWrapper, name: "service_name")
      expect do
        services_cli.start([service], "/hfdkjshksdjhfkjsdhf/fdsjghsdkjhb")
      end.to raise_error(UsageError, "Invalid usage: Provided service file does not exist.")
    end

    it "checks empty targets cause no error" do
      expect(Homebrew::Services::System).not_to receive(:root?)
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
      expect(Homebrew::Services::System).not_to receive(:root?)
      services_cli.stop([])
    end
  end

  describe "#kill" do
    it "checks empty targets cause no error" do
      expect(Homebrew::Services::System).not_to receive(:root?)
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
      service = instance_double(Homebrew::Services::FormulaWrapper, name: "name", installed?: false)
      expect do
        services_cli.install_service_file(service, nil)
      end.to raise_error(UsageError, "Invalid usage: Formula `name` is not installed.")
    end

    it "checks service file exists" do
      service = instance_double(
        Homebrew::Services::FormulaWrapper,
        name:         "name",
        installed?:   true,
        service_file: instance_double(Pathname, exist?: false),
      )
      expect do
        services_cli.install_service_file(service, nil)
      end.to raise_error(
        UsageError,
        "Invalid usage: Formula `name` has not implemented #plist, #service or provided a locatable service file.",
      )
    end
  end

  describe "#systemd_load" do
    let(:bindir) { mktmpdir }
    let(:log) { bindir/"systemctl.log" }

    before do
      (bindir/"systemctl").write <<~SH
        #!/bin/sh
        printf '%s\\n' "$*" >> "#{log}"
      SH
      (bindir/"systemctl").chmod 0755
      Homebrew::Services::System::Systemctl.reset_executable!
    end

    it "checks non-enabling run" do
      with_env(PATH: bindir.to_s) do
        services_cli.systemd_load(
          instance_double(Homebrew::Services::FormulaWrapper, service_name: "name", timed?: false),
          enable: false,
        )
      end

      expect(log.read).to eq("--user start name\n")
    end

    it "checks enabling run" do
      with_env(PATH: bindir.to_s) do
        services_cli.systemd_load(
          instance_double(Homebrew::Services::FormulaWrapper, service_name: "name", timed?: false),
          enable: true,
        )
      end

      expect(log.read).to eq <<~EOS
        --user start name
        --user enable name
      EOS
    end

    it "also starts and enables the timer when the service is timed" do
      with_env(PATH: bindir.to_s) do
        services_cli.systemd_load(
          instance_double(
            Homebrew::Services::FormulaWrapper,
            service_name: "name",
            timed?:       true,
            timer_name:   "name.timer",
          ),
          enable: true,
        )
      end

      expect(log.read).to eq <<~EOS
        --user start name
        --user enable name
        --user start name.timer
        --user enable name.timer
      EOS
    end

    it "starts but does not enable the timer when enable: false and the service is timed" do
      with_env(PATH: bindir.to_s) do
        services_cli.systemd_load(
          instance_double(
            Homebrew::Services::FormulaWrapper,
            service_name: "name",
            timed?:       true,
            timer_name:   "name.timer",
          ),
          enable: false,
        )
      end

      expect(log.read).to eq <<~EOS
        --user start name
        --user start name.timer
      EOS
    end
  end

  describe "#install_timer_file" do
    let(:tmp_root) { mktmpdir }
    let(:source_timer) { tmp_root/"homebrew.example_service.timer" }
    let(:dest_timer) { tmp_root/"dest"/"homebrew.example_service.timer" }

    before do
      source_timer.write("[Timer]\nOnCalendar=daily\n")
      dest_timer.parent.mkpath
    end

    it "copies the timer file from the Cellar to the dest_dir" do
      service = instance_double(
        Homebrew::Services::FormulaWrapper,
        name:       "example_service",
        timer_file: source_timer,
        dest_timer: dest_timer,
      )

      services_cli.install_timer_file(service)

      expect(dest_timer).to be_file
      expect(dest_timer.read).to eq("[Timer]\nOnCalendar=daily\n")
    end

    it "raises UsageError when the source timer file is missing" do
      missing_timer = tmp_root/"missing.timer"
      service = instance_double(
        Homebrew::Services::FormulaWrapper,
        name:       "example_service",
        timer_file: missing_timer,
        dest_timer: dest_timer,
      )

      expect do
        services_cli.install_timer_file(service)
      end.to raise_error(UsageError, /timed but no `\.timer` file was found/)

      expect(dest_timer).not_to exist
    end

    it "overwrites a stale destination timer file with the new contents" do
      dest_timer.write("[Timer]\nOnCalendar=hourly\n")
      service = instance_double(
        Homebrew::Services::FormulaWrapper,
        name:       "example_service",
        timer_file: source_timer,
        dest_timer: dest_timer,
      )

      services_cli.install_timer_file(service)

      expect(dest_timer.read).to eq("[Timer]\nOnCalendar=daily\n")
    end
  end

  describe "#stop with a timed service" do
    let(:bindir) { mktmpdir }
    let(:log) { bindir/"systemctl.log" }
    let(:tmp_root) { mktmpdir }
    let(:dest_service) { tmp_root/"homebrew.example_service.service" }
    let(:dest_timer) { tmp_root/"homebrew.example_service.timer" }

    before do
      (bindir/"systemctl").write <<~SH
        #!/bin/sh
        printf '%s\\n' "$*" >> "#{log}"
      SH
      (bindir/"systemctl").chmod 0755
      Homebrew::Services::System::Systemctl.reset_executable!
      allow(Homebrew::Services::System).to receive_messages(launchctl?: false, systemctl?: true)
      dest_service.write("svc")
      dest_timer.write("tmr")
    end

    it "disables --now the timer before the service and removes both files" do
      service = instance_double(
        Homebrew::Services::FormulaWrapper,
        name:         "example_service",
        service_name: "homebrew.example_service",
        timer_name:   "homebrew.example_service.timer",
        timed?:       true,
        loaded?:      true,
        pid?:         false,
        dest:         dest_service,
        dest_timer:   dest_timer,
      )

      with_env(PATH: bindir.to_s) do
        services_cli.stop([service])
      end

      systemctl_lines = log.read.lines.grep(/disable/)
      expect(systemctl_lines).to eq([
        "--user disable --now homebrew.example_service.timer\n",
        "--user disable --now homebrew.example_service\n",
      ])
      expect(dest_service).not_to exist
      expect(dest_timer).not_to exist
    end

    it "leaves the timer file in place when keep: true and stops the timer before the service" do
      service = instance_double(
        Homebrew::Services::FormulaWrapper,
        name:         "example_service",
        service_name: "homebrew.example_service",
        timer_name:   "homebrew.example_service.timer",
        timed?:       true,
        loaded?:      true,
        pid?:         false,
        dest:         dest_service,
        dest_timer:   dest_timer,
      )

      with_env(PATH: bindir.to_s) do
        services_cli.stop([service], keep: true)
      end

      systemctl_lines = log.read.lines.grep(/stop/)
      expect(systemctl_lines).to eq([
        "--user stop homebrew.example_service.timer\n",
        "--user stop homebrew.example_service\n",
      ])
      expect(log.read).not_to include("disable")
      expect(dest_service).to exist
      expect(dest_timer).to exist
    end

    it "removes a stale timer file when the service is no longer loaded" do
      service = instance_double(
        Homebrew::Services::FormulaWrapper,
        name:                  "example_service",
        service_name:          "homebrew.example_service",
        timer_name:            "homebrew.example_service.timer",
        timed?:                true,
        loaded?:               false,
        owner:                 nil,
        service_file_present?: false,
        dest:                  dest_service,
        dest_timer:            dest_timer,
      )

      with_env(PATH: bindir.to_s) do
        expect { services_cli.stop([service]) }.to output(/not started/).to_stderr
      end

      expect(dest_service).not_to exist
      expect(dest_timer).not_to exist
      expect(log).not_to exist
    end
  end

  describe "#launchctl_load" do
    let(:bindir) { mktmpdir }
    let(:log) { bindir/"launchctl.log" }

    before do
      (bindir/"launchctl").write <<~SH
        #!/bin/sh
        printf '%s\\n' "$*" >> "#{log}"
      SH
      (bindir/"launchctl").chmod 0755
      Homebrew::Services::System.reset_launchctl!
    end

    it "checks non-enabling run" do
      with_env(PATH: bindir.to_s) do
        services_cli.launchctl_load(instance_double(Homebrew::Services::FormulaWrapper), file: "a", enable: false)
      end

      expect(log.read).to eq("bootstrap #{Homebrew::Services::System.domain_target} a\n")
    end

    it "checks enabling run" do
      with_env(PATH: bindir.to_s) do
        services_cli.launchctl_load(instance_double(Homebrew::Services::FormulaWrapper, service_name: "name"),
                                    file:   "a",
                                    enable: true)
      end

      expect(log.read).to eq <<~EOS
        enable #{Homebrew::Services::System.domain_target}/name
        bootstrap #{Homebrew::Services::System.domain_target} a
      EOS
    end
  end

  describe "#service_load" do
    it "checks non-root for login" do
      expect(Homebrew::Services::System).to receive(:launchctl?).once.and_return(false)
      expect(Homebrew::Services::System).to receive(:systemctl?).once.and_return(false)
      expect(Homebrew::Services::System).to receive(:root?).once.and_return(true)

      expect do
        services_cli.service_load(
          instance_double(
            Homebrew::Services::FormulaWrapper,
            name:             "name",
            service_name:     "service.name",
            service_startup?: false,
          ),
          nil,
          enable: false,
        )
      end.to output("==> Successfully ran `name` (label: service.name)\n").to_stdout
    end

    it "checks root for startup" do
      expect(Homebrew::Services::System).to receive(:launchctl?).once.and_return(false)
      expect(Homebrew::Services::System).to receive(:systemctl?).once.and_return(false)
      expect(Homebrew::Services::System).to receive(:root?).twice.and_return(false)
      expect do
        services_cli.service_load(
          instance_double(
            Homebrew::Services::FormulaWrapper,
            name:             "name",
            service_name:     "service.name",
            service_startup?: true,
          ),
          nil,
          enable: false,
        )
      end.to output("==> Successfully ran `name` (label: service.name)\n").to_stdout
    end

    it "triggers launchctl" do
      expect(Homebrew::Services::System).to receive(:launchctl?).once.and_return(true)
      expect(Homebrew::Services::System).not_to receive(:systemctl?)
      expect(Homebrew::Services::System).to receive(:root?).twice.and_return(false)
      expect(described_class).to receive(:launchctl_load).once.and_return(true)
      expect do
        services_cli.service_load(
          instance_double(
            Homebrew::Services::FormulaWrapper,
            name:             "name",
            service_name:     "service.name",
            service_startup?: false,
            service_file:     instance_double(Pathname, exist?: false),
          ),
          nil,
          enable: false,
        )
      end.to output("==> Successfully ran `name` (label: service.name)\n").to_stdout
    end

    it "triggers systemctl" do
      expect(Homebrew::Services::System).to receive(:launchctl?).once.and_return(false)
      expect(Homebrew::Services::System).to receive(:systemctl?).once.and_return(true)
      expect(Homebrew::Services::System).to receive(:root?).twice.and_return(false)
      expect(Homebrew::Services::System::Systemctl).to receive(:run).once.and_return(true)
      expect do
        services_cli.service_load(
          instance_double(
            Homebrew::Services::FormulaWrapper,
            name:             "name",
            service_name:     "service.name",
            service_startup?: false,
            timed?:           false,
            dest:             instance_double(Pathname, exist?: true),
          ),
          nil,
          enable: false,
        )
      end.to output("==> Successfully ran `name` (label: service.name)\n").to_stdout
    end

    it "represents correct action" do
      expect(Homebrew::Services::System).to receive(:launchctl?).once.and_return(false)
      expect(Homebrew::Services::System).to receive(:systemctl?).once.and_return(true)
      expect(Homebrew::Services::System).to receive(:root?).twice.and_return(false)
      expect(Homebrew::Services::System::Systemctl).to receive(:run).twice.and_return(true)
      expect do
        services_cli.service_load(
          instance_double(
            Homebrew::Services::FormulaWrapper,
            name:             "name",
            service_name:     "service.name",
            service_startup?: false,
            timed?:           false,
            dest:             instance_double(Pathname, exist?: true),
          ),
          nil,
          enable: true,
        )
      end.to output("==> Successfully started `name` (label: service.name)\n").to_stdout
    end
  end
end
