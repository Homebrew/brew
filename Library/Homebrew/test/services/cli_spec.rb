# typed: true
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

  describe "#remove_unused_service_files" do
    it "removes unused timer files" do
      path = mktmpdir
      active_timer = path/"homebrew.name.timer"
      stale_timer = path/"homebrew.stale.timer"
      active_timer.write("timer")
      stale_timer.write("timer")
      allow(Homebrew::Services::System).to receive(:path).and_return(path)
      allow(services_cli).to receive(:running).and_return(["homebrew.name"])

      expect do
        expect(services_cli.remove_unused_service_files).to eq([stale_timer.to_s])
      end.to output("Removing unused service file: #{stale_timer}\n").to_stdout
      expect(active_timer).to exist
      expect(stale_timer).not_to exist
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

    context "when deciding whether to load target service" do
      let(:service) do
        instance_double(
          Homebrew::Services::FormulaWrapper,
          name:         "name",
          pid?:         false,
          installed?:   true,
          service_file: instance_double(Pathname, exist?: true),
        )
      end

      before do
        allow(services_cli).to receive(:install_service_file)
      end

      it "loads service for root" do
        allow(Homebrew::Services::System).to receive(:root?).and_return(true)
        allow(services_cli).to receive(:take_root_ownership?).and_return(true)
        expect(services_cli).to receive(:service_load).with(service, nil, enable: true)
        services_cli.start([service])
      end

      it "loads service for non-root user" do
        allow(Homebrew::Services::System).to receive(:root?).and_return(false)
        allow(services_cli).to receive(:take_root_ownership?).and_return(false)
        expect(services_cli).to receive(:service_load).with(service, nil, enable: true)
        services_cli.start([service])
      end

      it "loads service for root when given `--sudo-service-user`" do
        allow(Homebrew::Services::System).to receive(:root?).and_return(true)
        allow(services_cli).to receive_messages(sudo_service_user: "_serviced", take_root_ownership?: false)
        expect(services_cli).to receive(:service_load).with(service, nil, enable: true)
        services_cli.start([service])
      end

      it "does not load service for non-root user when given `--sudo-service-user`" do
        allow(Homebrew::Services::System).to receive(:root?).and_return(false)
        allow(services_cli).to receive_messages(sudo_service_user: "_serviced", take_root_ownership?: false)
        expect(services_cli).not_to receive(:service_load)
        services_cli.start([service])
      end
    end
  end

  describe "#stop" do
    it "checks empty targets cause no error" do
      expect(Homebrew::Services::System).not_to receive(:root?)
      services_cli.stop([])
    end

    it "stops timed systemd timers before services when kept" do
      allow(Homebrew::Services::System).to receive(:systemctl?).and_return(true)
      expect(Homebrew::Services::System::Systemctl).to receive(:quiet_run)
        .with("stop", "homebrew.name.timer")
        .ordered
        .and_return(true)
      expect(Homebrew::Services::System::Systemctl).to receive(:quiet_run)
        .with("stop", "homebrew.name")
        .ordered
        .and_return(true)
      service = instance_double(
        Homebrew::Services::FormulaWrapper,
        name:         "name",
        service_name: "homebrew.name",
        timed?:       true,
        timer_name:   "homebrew.name.timer",
        pid?:         false,
      )
      allow(service).to receive(:loaded?).and_return(true, false)

      expect do
        services_cli.stop([service], keep: true)
      end.to output(/Successfully stopped `name`/).to_stdout
    end

    it "stops and removes timed systemd timer files" do
      allow(Homebrew::Services::System).to receive(:systemctl?).and_return(true)
      expect(Homebrew::Services::System::Systemctl).to receive(:quiet_run)
        .with("disable", "--now", "homebrew.name.timer")
        .and_return(true)
      expect(Homebrew::Services::System::Systemctl).to receive(:quiet_run)
        .with("disable", "--now", "homebrew.name")
        .and_return(true)
      expect(Homebrew::Services::System::Systemctl).to receive(:run).with("daemon-reload")

      dest_dir = mktmpdir
      service_dest = dest_dir/"homebrew.name.service"
      timer_dest = dest_dir/"homebrew.name.timer"
      service_dest.write("service")
      timer_dest.write("timer")
      service = instance_double(
        Homebrew::Services::FormulaWrapper,
        name:         "name",
        service_name: "homebrew.name",
        dest:         service_dest,
        timed?:       true,
        timer_name:   "homebrew.name.timer",
        timer_dest:,
        pid?:         false,
      )
      allow(service).to receive(:loaded?).and_return(true, false)

      expect do
        services_cli.stop([service])
      end.to output(/Successfully stopped `name`/).to_stdout
      expect(timer_dest).not_to exist
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

  describe "#take_root_ownership?" do
    it "returns false when given non-root user" do
      allow(Homebrew::Services::System).to receive(:root?).and_return(false)
      service = instance_double(Homebrew::Services::FormulaWrapper)
      expect(services_cli.take_root_ownership?(service)).to be(false)
    end

    it "returns false when given `--sudo-service-user`" do
      allow(Homebrew::Services::System).to receive(:root?).and_return(true)
      allow(services_cli).to receive(:sudo_service_user).and_return("_serviced")
      service = instance_double(Homebrew::Services::FormulaWrapper)
      expect(services_cli.take_root_ownership?(service)).to be(false)
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

    it "installs timed systemd timer files" do
      allow(Homebrew::Services::System).to receive(:systemctl?).and_return(true)
      allow(Homebrew::Services::System::Systemctl).to receive(:run).with("daemon-reload")

      source_dir = mktmpdir
      dest_dir = mktmpdir
      service_file = source_dir/"homebrew.name.service"
      timer_file = source_dir/"homebrew.name.timer"
      service_file.write("service")
      timer_file.write("timer")
      service = instance_double(
        Homebrew::Services::FormulaWrapper,
        name:         "name",
        service_name: "homebrew.name",
        installed?:   true,
        service_file:,
        dest:         dest_dir/service_file.basename,
        dest_dir:,
        timed?:       true,
        timer_file:,
        timer_dest:   dest_dir/timer_file.basename,
      )

      services_cli.install_service_file(service, nil)

      expect(service.timer_dest.read).to eq("timer")
    end

    context "when given `--sudo-service-user`" do
      let(:dest_dir) { mktmpdir }
      let(:service) do
        source_dir = mktmpdir
        service_file = source_dir/"homebrew.test.plist"
        service_file.write <<~XML
          <?xml version="1.0" encoding="UTF-8"?>
          <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
          <plist version="1.0">
          <dict>
            <key>Label</key>
            <string>homebrew.test</string>
            <key>ProgramArguments</key>
            <array>
              <string>/opt/homebrew/opt/test/bin/test</string>
            </array>
          </dict>
          </plist>
        XML
        instance_double(
          Homebrew::Services::FormulaWrapper,
          name:         "name",
          service_name: "homebrew.test",
          installed?:   true,
          service_file:,
          dest:         dest_dir/"homebrew.test.plist",
          dest_dir:,
        )
      end

      before do
        allow(Homebrew::Services::System).to receive_messages(launchctl?: true, systemctl?: false)
        allow(services_cli).to receive(:sudo_service_user).and_return("_serviced")
      end

      it "prints the given username" do
        expect do
          services_cli.install_service_file(service, nil)
        end.to output(/Setting username in homebrew\.test to: _serviced/).to_stdout
      end

      it "sets username in the generated plist" do
        services_cli.install_service_file(service, nil)
        expect(service.dest.read).to include("<key>UserName</key>", "<string>_serviced</string>")
      end
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

    it "checks enabling timed run" do
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
        --user start name.timer
        --user enable name.timer
      EOS
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

    it "warns root for login without `--sudo-service-user`" do
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
          enable: true,
        )
      end.to output(/`name` must be run as non-root to start at user login!/).to_stderr
    end

    it "does not warn root for login when given `--sudo-service-user`" do
      expect(Homebrew::Services::System).to receive(:launchctl?).once.and_return(false)
      expect(Homebrew::Services::System).to receive(:systemctl?).once.and_return(false)
      expect(Homebrew::Services::System).to receive(:root?).twice.and_return(true)
      allow(services_cli).to receive(:sudo_service_user).and_return("_serviced")
      allow(Homebrew::Services::System).to receive(:user_exists?).with("_serviced").and_return(true)
      expect do
        services_cli.service_load(
          instance_double(
            Homebrew::Services::FormulaWrapper,
            name:             "name",
            service_name:     "service.name",
            service_startup?: false,
          ),
          nil,
          enable: true,
        )
      end.not_to output(/must be run as non-root to start at user login!/).to_stderr
    end

    it "errors then exits when given a `--sudo-service-user` which does not exist" do
      allow(services_cli).to receive(:sudo_service_user).and_return("not_a_real_user")
      expect(Homebrew::Services::System).to receive(:user_exists?).with("not_a_real_user").and_return(false)
      expect do
        services_cli.service_load(
          instance_double(
            Homebrew::Services::FormulaWrapper,
            name:             "name",
            service_name:     "service.name",
            service_startup?: false,
          ),
          nil,
          enable: true,
        )
      end.to output(/Error: Cannot start `name` as `not_a_real_user` is not a user!/).to_stderr
                                                                                     .and raise_error(SystemExit)
    end

    it "continues loading when given a `--sudo-service-user` which exists" do
      expect(Homebrew::Services::System).to receive(:launchctl?).once.and_return(false)
      expect(Homebrew::Services::System).to receive(:systemctl?).once.and_return(false)
      expect(Homebrew::Services::System).to receive(:root?).twice.and_return(true)
      allow(services_cli).to receive(:sudo_service_user).and_return("_serviced")
      expect(Homebrew::Services::System).to receive(:user_exists?).with("_serviced").and_return(true)
      expect do
        services_cli.service_load(
          instance_double(
            Homebrew::Services::FormulaWrapper,
            name:             "name",
            service_name:     "service.name",
            service_startup?: false,
            service_file:     instance_double(Pathname, exist?: false),
            path_dirs:        [],
          ),
          nil,
          enable: true,
        )
      end.to output("==> Successfully started `name` (label: service.name)\n").to_stdout
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
            path_dirs:        [],
          ),
          nil,
          enable: false,
        )
      end.to output("==> Successfully ran `name` (label: service.name)\n").to_stdout
    end

    it "creates service path directories before loading" do
      expect(Homebrew::Services::System).to receive(:launchctl?).once.and_return(true)
      expect(Homebrew::Services::System).not_to receive(:systemctl?)
      expect(Homebrew::Services::System).to receive(:root?).twice.and_return(false)

      path_dirs = [
        mktmpdir/"var/run",
        mktmpdir/"var/log",
      ]
      expect(described_class).to receive(:launchctl_load).once do
        path_dirs.each { expect(it).to be_a_directory }
      end

      expect do
        services_cli.service_load(
          instance_double(
            Homebrew::Services::FormulaWrapper,
            name:             "name",
            service_name:     "service.name",
            service_startup?: false,
            service_file:     instance_double(Pathname, exist?: false),
            path_dirs:,
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
            dest:             instance_double(Pathname, exist?: true),
            timed?:           false,
            path_dirs:        [],
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
            dest:             instance_double(Pathname, exist?: true),
            timed?:           false,
            path_dirs:        [],
          ),
          nil,
          enable: true,
        )
      end.to output("==> Successfully started `name` (label: service.name)\n").to_stdout
    end
  end
end
