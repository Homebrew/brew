# typed: true
# frozen_string_literal: true

require "services/cli"
require "services/system"
require "services/formula_wrapper"
require "test/support/helper/services"

RSpec.describe Homebrew::Services::Cli do
  include Test::Helper::Services

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
        495     0   sh.brew.node_exporter
        1234    34  homebrew.mxcl.postgresql@14
      EOS
      expect(services_cli.running).to eq([
        "homebrew.mxcl.php",
        "sh.brew.node_exporter",
        "homebrew.mxcl.postgresql@14",
      ])
    end

    it "systemD - returns the currently running services" do
      allow(Homebrew::Services::System).to receive(:launchctl?).and_return(false)
      allow(Homebrew::Services::System::Systemctl).to receive(:popen_read).and_return <<~EOS
        sh.brew.php.service      loaded active running Homebrew PHP service
        homebrew.redis.service   loaded active running Homebrew Redis service
        systemd-udevd.service    loaded active running Rule-based Manager for Device Events and Files
        udisks2.service          loaded active running Disk Manager
        user@1000.service        loaded active running User Manager for UID 1000
      EOS
      expect(services_cli.running).to eq(["sh.brew.php", "homebrew.redis"])
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
        name:                 "example_service",
        service_name:         "sh.brew.example_service",
        active_service_name:  "sh.brew.example_service",
        pid?:                 true,
        dest:                 Pathname("this_path_does_not_exist"),
        keep_alive?:          false,
        loaded_service_names: [],
      )
      allow(service).to receive(:reset_cache!)
      allow(Homebrew::Services::System).to receive_messages(launchctl?: false, systemctl?: true)
      expect(Homebrew::Services::System::Systemctl).to receive(:quiet_run)
        .with("stop", "sh.brew.example_service")
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
      active_timer = path/"sh.brew.name.timer"
      stale_timer = path/"sh.brew.stale.timer"
      active_timer.write("timer")
      stale_timer.write("timer")
      allow(Homebrew::Services::System).to receive(:path).and_return(path)
      allow(services_cli).to receive(:running).and_return(["sh.brew.name"])

      expect do
        expect(services_cli.remove_unused_service_files).to eq([stale_timer.to_s])
      end.to output("Removing unused service file: #{stale_timer}\n").to_stdout
      expect(active_timer).to exist
      expect(stale_timer).not_to exist
    end

    it "keeps systemd service files for an active timer" do
      path = mktmpdir
      service_file = path/"homebrew.name.service"
      timer_file = path/"homebrew.name.timer"
      service_file.write("service")
      timer_file.write("timer")
      allow(Homebrew::Services::System).to receive_messages(launchctl?: false, path:, systemctl?: true)
      allow(Homebrew::Services::System::Systemctl).to receive(:quiet_run)
        .with("status", "homebrew.name.timer").and_return(true)
      allow(services_cli).to receive(:running).and_return([])

      expect([services_cli.remove_unused_service_files, service_file.exist?, timer_file.exist?])
        .to eq([[], true, true])
    end

    it "removes unused canonical macOS service files" do
      path = mktmpdir
      active_service = path/"sh.brew.name.plist"
      stale_service = path/"sh.brew.stale.plist"
      active_service.write("service")
      stale_service.write("service")
      allow(Homebrew::Services::System).to receive(:path).and_return(path)
      allow(services_cli).to receive(:running).and_return(["sh.brew.name"])

      expect do
        expect(services_cli.remove_unused_service_files).to eq([stale_service.to_s])
      end.to output("Removing unused service file: #{stale_service}\n").to_stdout
      expect(active_service).to exist
      expect(stale_service).not_to exist
    end

    it "keeps a loaded macOS service file whose internal label differs from its filename" do
      path = mktmpdir
      active_service = path/"sh.brew.name.plist"
      active_service.write <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>Label</key>
          <string>homebrew.mxcl.name</string>
        </dict>
        </plist>
      XML
      allow(Homebrew::Services::System).to receive_messages(launchctl?: true, path:)
      allow(services_cli).to receive(:running).and_return(["homebrew.mxcl.name"])

      expect(services_cli.remove_unused_service_files).to be_empty
      expect(active_service).to exist
    end

    it "keeps a loaded macOS service file with an arbitrary internal label" do
      path = mktmpdir
      active_service = path/"sh.brew.name.plist"
      active_service.write <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>Label</key>
          <string>org.example.package</string>
        </dict>
        </plist>
      XML
      allow(Homebrew::Services::System).to receive_messages(launchctl?: true, path:)
      allow(services_cli).to receive(:running).and_return([])
      expect(Homebrew::Services::System).to receive(:launchctl_service_running?)
        .with("org.example.package").and_return(true)

      expect(services_cli.remove_unused_service_files).to be_empty
      expect(active_service).to exist
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
      allow(Homebrew::Services::System).to receive(:launchctl?).and_return(false)
      expected_output = "Service `example_service` already running, " \
                        "use `brew services restart example_service` to restart.\n"
      service = instance_double(
        service_string,
        name:                "example_service",
        service_name:        "sh.brew.example_service",
        active_service_name: "sh.brew.example_service",
        pid?:                true,
      )
      expect do
        services_cli.run([service])
      end.to output(expected_output).to_stdout
    end

    it "does not run a service already loaded with the compatible macOS label" do
      allow(Homebrew::Services::System).to receive(:launchctl?).and_return(true)
      service = instance_double(
        service_string,
        name:                    "name",
        service_name:            "sh.brew.name",
        service_file_generated?: true,
        service_names:           ["sh.brew.name", "homebrew.mxcl.name"],
        loaded_service_names:    ["homebrew.mxcl.name"],
        pid?:                    false,
      )
      expect(services_cli).not_to receive(:service_load)

      expect do
        services_cli.run([service])
      end.to output(/already loaded as `homebrew.mxcl.name`/).to_stdout
    end

    it "reports a pending migration for a generated service loaded with the legacy systemd label" do
      allow(Homebrew::Services::System).to receive_messages(launchctl?: false, systemctl?: true)
      service = instance_double(
        service_string,
        name:                    "name",
        service_name:            "sh.brew.name",
        service_file_generated?: true,
        service_names:           ["sh.brew.name", "homebrew.name"],
        active_service_name:     "homebrew.name",
        loaded_service_names:    ["homebrew.name"],
        pid?:                    true,
      )
      expect(services_cli).not_to receive(:service_load)

      expect do
        services_cli.run([service])
      end.to output(/already loaded as `homebrew\.name`.*migration is pending/).to_stdout
    end

    it "reports a pending migration for a stopped legacy systemd service" do
      allow(Homebrew::Services::System).to receive_messages(launchctl?: false, systemctl?: true)
      service = instance_double(
        service_string,
        name:                    "name",
        service_name:            "sh.brew.name",
        service_file_generated?: true,
        service_names:           ["sh.brew.name", "homebrew.name"],
        loaded_service_names:    ["homebrew.name"],
        pid?:                    false,
      )
      expect(services_cli).not_to receive(:service_load)

      expect do
        services_cli.run([service])
      end.to output(/already loaded as `homebrew\.name`.*migration is pending/).to_stdout
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
      allow(Homebrew::Services::System).to receive(:launchctl?).and_return(false)
      expected_output = "Service `example_service` already started, " \
                        "use `brew services restart example_service` to restart.\n"
      service = instance_double(
        service_string,
        name:                "example_service",
        service_name:        "sh.brew.example_service",
        active_service_name: "sh.brew.example_service",
        pid?:                true,
      )
      expect do
        services_cli.start([service])
      end.to output(expected_output).to_stdout
    end

    context "when deciding whether to load target service" do
      let(:service) do
        instance_double(
          Homebrew::Services::FormulaWrapper,
          name:                 "name",
          service_name:         "sh.brew.name",
          loaded_service_names: [],
          pid?:                 false,
          installed?:           true,
          service_file:         instance_double(Pathname, exist?: true),
          source_service_file:  instance_double(Pathname, exist?: true),
        )
      end

      before do
        allow(services_cli).to receive(:install_service_file)
      end

      it "reports a pending migration for a running service using the legacy label" do
        allow(Homebrew::Services::System).to receive(:launchctl?).and_return(true)
        allow(service).to receive_messages(
          active_service_name:     "homebrew.mxcl.name",
          loaded_service_names:    ["homebrew.mxcl.name"],
          service_file_generated?: true,
          service_names:           ["sh.brew.name", "homebrew.mxcl.name"],
          pid?:                    true,
        )
        expect(services_cli).not_to receive(:install_service_file)

        expected_output = "Service `name` is already loaded as `homebrew.mxcl.name`; " \
                          "a service label migration is pending. Use `brew services restart name` " \
                          "to migrate to `sh.brew.name`.\n"
        expect do
          services_cli.start([service])
        end.to output(expected_output).to_stdout
      end

      it "does not promise to migrate a package-provided legacy label" do
        allow(Homebrew::Services::System).to receive(:launchctl?).and_return(true)
        allow(service).to receive_messages(
          active_service_name:     "homebrew.mxcl.name",
          loaded_service_names:    ["homebrew.mxcl.name"],
          service_file_generated?: false,
          service_names:           ["sh.brew.name", "homebrew.mxcl.name"],
          pid?:                    true,
        )
        expect(services_cli).not_to receive(:install_service_file)

        expected_output = "Service `name` already started (label: homebrew.mxcl.name), " \
                          "use `brew services restart name` to restart.\n"
        expect do
          services_cli.start([service])
        end.to output(expected_output).to_stdout
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

    it "stops compatible systemd timers before services when kept" do
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
        name:                 "name",
        service_name:         "sh.brew.name",
        service_names:        ["sh.brew.name", "homebrew.name"],
        loaded_service_names: ["homebrew.name"],
        timed?:               true,
        pid?:                 false,
      )
      allow(service).to receive(:loaded?).and_return(true, false)
      allow(service).to receive(:reset_cache!)

      expect do
        services_cli.stop([service], keep: true)
      end.to output(/Successfully stopped `name`/).to_stdout
    end

    it "stops and removes timed systemd timer files" do
      allow(Homebrew::Services::System).to receive(:systemctl?).and_return(true)
      expect(Homebrew::Services::System::Systemctl).to receive(:quiet_run)
        .with("disable", "--now", "sh.brew.name.timer")
        .and_return(true)
      expect(Homebrew::Services::System::Systemctl).to receive(:quiet_run)
        .with("disable", "--now", "sh.brew.name")
        .and_return(true)
      expect(Homebrew::Services::System::Systemctl).to receive(:run).with("daemon-reload")

      dest_dir = mktmpdir
      service_dest = dest_dir/"sh.brew.name.service"
      timer_dest = dest_dir/"sh.brew.name.timer"
      service_dest.write("service")
      timer_dest.write("timer")
      service = instance_double(
        Homebrew::Services::FormulaWrapper,
        name:                 "name",
        service_name:         "sh.brew.name",
        service_names:        ["sh.brew.name", "homebrew.name"],
        loaded_service_names: ["sh.brew.name"],
        destinations:         [service_dest],
        timed?:               true,
        timer_destinations:   [timer_dest],
        pid?:                 false,
      )
      allow(service).to receive(:loaded?).and_return(true, false)
      allow(service).to receive(:reset_cache!)

      expect do
        services_cli.stop([service])
      end.to output(/Successfully stopped `name`/).to_stdout
      expect(timer_dest).not_to exist
    end

    it "stops and removes the compatible systemd service label" do
      allow(Homebrew::Services::System).to receive_messages(launchctl?: false, systemctl?: true)
      expect(Homebrew::Services::System::Systemctl).to receive(:quiet_run)
        .with("disable", "--now", "homebrew.name").and_return(true)
      expect(Homebrew::Services::System::Systemctl).to receive(:quiet_run)
        .with("disable", "sh.brew.name.service").and_return(true)
      expect(Homebrew::Services::System::Systemctl).to receive(:run).with("daemon-reload")

      dest_dir = mktmpdir
      destinations = [dest_dir/"sh.brew.name.service", dest_dir/"homebrew.name.service"]
      destinations.each { |destination| destination.write("service") }
      service = instance_double(
        Homebrew::Services::FormulaWrapper,
        name:                 "name",
        service_name:         "sh.brew.name",
        service_names:        ["sh.brew.name", "homebrew.name"],
        loaded_service_names: ["homebrew.name"],
        destinations:,
        timed?:               false,
        pid?:                 false,
      )
      allow(service).to receive(:loaded?).and_return(true, false)
      allow(service).to receive(:reset_cache!)

      expect do
        services_cli.stop([service])
      end.to output(/Successfully stopped `name` \(label: homebrew\.name\)/).to_stdout
      expect(destinations).not_to include(an_object_satisfying(&:exist?))
    end

    it "preserves a compatible systemd service file when stopping fails" do
      allow(Homebrew::Services::System).to receive_messages(launchctl?: false, systemctl?: true)
      expect(Homebrew::Services::System::Systemctl).to receive(:quiet_run)
        .with("disable", "--now", "homebrew.name").and_return(false)
      expect(Homebrew::Services::System::Systemctl).not_to receive(:run)

      destination = mktmpdir/"homebrew.name.service"
      destination.write("service")
      service = instance_double(
        Homebrew::Services::FormulaWrapper,
        name:                 "name",
        service_name:         "sh.brew.name",
        service_names:        ["sh.brew.name", "homebrew.name"],
        loaded_service_names: ["homebrew.name"],
        destinations:         [destination],
        timed?:               false,
        pid?:                 false,
      )
      allow(service).to receive(:loaded?).and_return(true)
      allow(service).to receive(:reset_cache!)

      expect do
        services_cli.stop([service])
      end.to output(/Unable to stop `name` \(label: homebrew\.name\)/).to_stderr
      expect(destination).to exist
    end

    it "cleans up after an accepted asynchronous systemd stop" do
      allow(Homebrew::Services::System).to receive_messages(launchctl?: false, systemctl?: true)
      expect(Homebrew::Services::System::Systemctl).to receive(:quiet_run)
        .with("--no-block", "disable", "--now", "homebrew.name").and_return(true)
      expect(Homebrew::Services::System::Systemctl).to receive(:run).with("--no-block", "daemon-reload")

      destination = mktmpdir/"homebrew.name.service"
      destination.write("service")
      service = instance_double(
        Homebrew::Services::FormulaWrapper,
        name:                 "name",
        service_name:         "sh.brew.name",
        service_names:        ["sh.brew.name", "homebrew.name"],
        loaded_service_names: ["homebrew.name"],
        destinations:         [destination],
        timed?:               false,
        pid?:                 true,
      )
      allow(service).to receive(:loaded?).and_return(true)
      allow(service).to receive(:reset_cache!)

      expect do
        services_cli.stop([service], no_wait: true)
      end.to output(/Successfully stopped `name` \(label: homebrew\.name\)/).to_stdout
      expect(destination).not_to exist
    end

    it "stops a compatible systemd service whose timer is inactive" do
      allow(Homebrew::Services::System).to receive_messages(launchctl?: false, systemctl?: true)
      expect(Homebrew::Services::System::Systemctl).to receive(:quiet_run)
        .with("stop", "homebrew.name.timer").ordered.and_return(true)
      expect(Homebrew::Services::System::Systemctl).to receive(:quiet_run)
        .with("stop", "homebrew.name").ordered.and_return(true)
      service = instance_double(
        Homebrew::Services::FormulaWrapper,
        name:                  "name",
        service_name:          "sh.brew.name",
        service_names:         ["sh.brew.name", "homebrew.name"],
        active_service_name:   "homebrew.name",
        loaded_service_names:  [],
        service_file_present?: false,
        timed?:                true,
      )
      allow(service).to receive(:loaded?).and_return(false)
      allow(service).to receive(:pid?).and_return(true, false)
      allow(service).to receive(:reset_cache!)

      expect do
        services_cli.stop([service], keep: true)
      end.to output(/Successfully stopped `name` \(label: homebrew\.name\)/).to_stdout
    end

    it "stops and removes both compatible macOS service labels" do
      allow(Homebrew::Services::System).to receive_messages(
        launchctl?:               true,
        systemctl?:               false,
        launchctl:                Pathname("/bin/launchctl"),
        candidate_domain_targets: ["gui/501"],
      )
      allow(Homebrew::Services::System).to receive(:launchctl_service_running?)
        .with("sh.brew.name").and_return(true, false)
      allow(Homebrew::Services::System).to receive(:launchctl_service_running?)
        .with("homebrew.mxcl.name").and_return(true, false)
      expect(SystemCommand).to receive(:quiet_system)
        .with(Pathname("/bin/launchctl"), "bootout", "gui/501/sh.brew.name")
      expect(SystemCommand).to receive(:quiet_system)
        .with(Pathname("/bin/launchctl"), "bootout", "gui/501/homebrew.mxcl.name")

      dest_dir = mktmpdir
      destinations = [dest_dir/"sh.brew.name.plist", dest_dir/"homebrew.mxcl.name.plist"]
      destinations.each { |destination| destination.write("service") }
      service = instance_double(
        Homebrew::Services::FormulaWrapper,
        name:                 "name",
        service_name:         "sh.brew.name",
        service_names:        ["sh.brew.name", "homebrew.mxcl.name"],
        loaded_service_names: ["sh.brew.name", "homebrew.mxcl.name"],
        destinations:,
        pid?:                 false,
      )
      allow(service).to receive(:loaded?).and_return(true, false)
      allow(service).to receive(:reset_cache!)

      expect do
        services_cli.stop([service], no_wait: true)
      end.to output(/Successfully stopped `name`/).to_stdout
      expect(destinations).not_to include(an_object_satisfying(&:exist?))
    end

    it "reports and preserves a package plist when its label remains loaded" do
      allow(Homebrew::Services::System).to receive_messages(
        launchctl?:                 true,
        systemctl?:                 false,
        launchctl:                  Pathname("/bin/launchctl"),
        candidate_domain_targets:   ["gui/501"],
        launchctl_service_running?: true,
      )
      allow(SystemCommand).to receive(:quiet_system).and_return(false)

      destination = mktmpdir/"sh.brew.name.plist"
      destination.write("service")
      service = instance_double(
        Homebrew::Services::FormulaWrapper,
        name:                 "name",
        service_name:         "sh.brew.name",
        service_names:        ["sh.brew.name", "homebrew.mxcl.name"],
        loaded_service_names: ["org.example.package"],
        destinations:         [destination],
        pid?:                 false,
      )
      allow(service).to receive(:loaded?) { destination.exist? }
      allow(service).to receive(:reset_cache!)

      expect do
        services_cli.stop([service], no_wait: true)
      end.to output(/Unable to stop `name` \(label: org\.example\.package\)/).to_stderr
      expect(destination).to exist
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

    it "reports the compatible macOS label that was killed and stops after success" do
      service = instance_double(
        service_string,
        name:                 "name",
        service_name:         "sh.brew.name",
        keep_alive?:          false,
        loaded_service_names: ["homebrew.mxcl.name"],
      )
      allow(service).to receive(:pid?).and_return(true, false)
      allow(service).to receive(:reset_cache!)
      allow(Homebrew::Services::System).to receive_messages(
        launchctl:                  "/bin/launchctl",
        launchctl?:                 true,
        launchctl_service_running?: true,
        systemctl?:                 false,
      )
      expect(SystemCommand).to receive(:quiet_system)
        .with("/bin/launchctl", "stop", "homebrew.mxcl.name").once.and_return(true)

      expect do
        services_cli.kill([service])
      end.to output(/Successfully killed `name` \(label: homebrew\.mxcl\.name\)/).to_stdout
    end

    it "reports the compatible systemd label that was killed" do
      service = instance_double(
        service_string,
        name:                 "name",
        service_name:         "sh.brew.name",
        keep_alive?:          false,
        loaded_service_names: ["homebrew.name"],
      )
      allow(service).to receive(:pid?).and_return(true, false)
      allow(service).to receive(:reset_cache!)
      allow(Homebrew::Services::System).to receive_messages(launchctl?: false, systemctl?: true)
      expect(Homebrew::Services::System::Systemctl).to receive(:quiet_run)
        .with("stop", "homebrew.name").and_return(true)

      expect do
        services_cli.kill([service])
      end.to output(/Successfully killed `name` \(label: homebrew\.name\)/).to_stdout
    end

    it "kills a compatible systemd service whose timer is inactive" do
      service = instance_double(
        service_string,
        name:                 "name",
        service_name:         "sh.brew.name",
        active_service_name:  "homebrew.name",
        keep_alive?:          false,
        loaded_service_names: [],
      )
      allow(service).to receive(:pid?).and_return(true, false)
      allow(service).to receive(:reset_cache!)
      allow(Homebrew::Services::System).to receive_messages(launchctl?: false, systemctl?: true)
      expect(Homebrew::Services::System::Systemctl).to receive(:quiet_run)
        .with("stop", "homebrew.name").and_return(true)

      expect do
        services_cli.kill([service])
      end.to output(/Successfully killed `name` \(label: homebrew\.name\)/).to_stdout
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
        name:                "name",
        installed?:          true,
        service_file:        instance_double(Pathname, exist?: false),
        source_service_file: instance_double(Pathname, exist?: false),
      )
      expect do
        services_cli.install_service_file(service, nil)
      end.to raise_error(
        UsageError,
        "Invalid usage: Formula `name` has not implemented #plist, #service or provided a locatable service file.",
      )
    end

    it "removes compatible macOS service files before installing" do
      allow(Homebrew::Services::System).to receive_messages(launchctl?: true, systemctl?: false)

      source_dir = mktmpdir
      dest_dir = mktmpdir
      service_file = source_dir/"homebrew.mxcl.name.plist"
      primary_dest = dest_dir/"sh.brew.name.plist"
      compatible_dest = dest_dir/"homebrew.mxcl.name.plist"
      service_file.write("service")
      primary_dest.write("old service")
      compatible_dest.write("compatible service")
      service = instance_double(
        Homebrew::Services::FormulaWrapper,
        name:                "name",
        service_name:        "sh.brew.name",
        installed?:          true,
        source_service_file: service_file,
        service_contents:    "service",
        dest:                primary_dest,
        destinations:        [primary_dest, compatible_dest],
        dest_dir:,
      )

      services_cli.install_service_file(service, nil)

      expect([primary_dest.read, compatible_dest.exist?]).to eq(["service", false])
    end

    it "disables compatible systemd service files before replacing them" do
      allow(Homebrew::Services::System).to receive_messages(launchctl?: false, systemctl?: true)
      allow(Homebrew::Services::System::Systemctl).to receive(:quiet_run).and_return(true)
      expect(Homebrew::Services::System::Systemctl).to receive(:quiet_run)
        .with("disable", "homebrew.name.service")
      allow(Homebrew::Services::System::Systemctl).to receive(:run).with("daemon-reload")

      source_dir = mktmpdir
      dest_dir = mktmpdir
      service_file = source_dir/"homebrew.name.service"
      primary_dest = dest_dir/"sh.brew.name.service"
      compatible_dest = dest_dir/"homebrew.name.service"
      service_file.write("service")
      primary_dest.write("old service")
      compatible_dest.write("compatible service")
      service = instance_double(
        Homebrew::Services::FormulaWrapper,
        name:                "name",
        service_name:        "sh.brew.name",
        installed?:          true,
        source_service_file: service_file,
        service_contents:    "service",
        dest:                primary_dest,
        destinations:        [primary_dest, compatible_dest],
        dest_dir:,
        timed?:              false,
      )

      services_cli.install_service_file(service, nil)

      expect([primary_dest.read, compatible_dest.exist?]).to eq(["service", false])
    end

    it "installs timed systemd timer files" do
      allow(Homebrew::Services::System).to receive(:systemctl?).and_return(true)
      expect(Homebrew::Services::System::Systemctl).to receive(:quiet_run)
        .with("disable", "homebrew.name.timer").and_return(true)
      allow(Homebrew::Services::System::Systemctl).to receive(:run).with("daemon-reload")

      source_dir = mktmpdir
      dest_dir = mktmpdir
      service_file = source_dir/"sh.brew.name.service"
      timer_file = source_dir/"sh.brew.name.timer"
      compatible_timer_dest = dest_dir/"homebrew.name.timer"
      service_file.write("service")
      timer_file.write("legacy timer")
      compatible_timer_dest.write("old timer")
      service = instance_double(
        Homebrew::Services::FormulaWrapper,
        name:                "name",
        service_name:        "sh.brew.name",
        installed?:          true,
        service_file:,
        source_service_file: service_file,
        service_contents:    "service",
        dest:                dest_dir/service_file.basename,
        destinations:        [dest_dir/service_file.basename],
        dest_dir:,
        timed?:              true,
        timer_file:,
        timer_contents:      "timer",
        timer_dest:          dest_dir/timer_file.basename,
        timer_destinations:  [dest_dir/timer_file.basename, compatible_timer_dest],
      )

      services_cli.install_service_file(service, nil)

      expect([service.timer_dest.read, compatible_timer_dest.exist?]).to eq(["timer", false])
    end

    context "when given `--sudo-service-user`" do
      let(:dest_dir) { mktmpdir }
      let(:plist_xml) do
        <<~XML
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
      end
      let(:service) do
        source_dir = mktmpdir
        service_file = source_dir/"homebrew.test.plist"
        service_file.write(plist_xml)
        instance_double(
          Homebrew::Services::FormulaWrapper,
          name:                "name",
          service_name:        "homebrew.test",
          installed?:          true,
          service_file:,
          source_service_file: service_file,
          service_contents:    plist_xml,
          dest:                dest_dir/"homebrew.test.plist",
          destinations:        [dest_dir/"homebrew.test.plist"],
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
      reset_services_memoization!
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
      reset_services_memoization!
    end

    it "checks non-enabling run" do
      with_env(PATH: bindir.to_s) do
        services_cli.launchctl_load(
          instance_double(Homebrew::Services::FormulaWrapper, service_name: "name"),
          file:   "a",
          enable: false,
        )
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

    it "enables the label declared by a package-provided plist" do
      service_file = bindir/"package.plist"
      service_file.write <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>Label</key>
          <string>org.example.package</string>
        </dict>
        </plist>
      XML

      loaded_name = with_env(PATH: bindir.to_s) do
        services_cli.launchctl_load(
          instance_double(Homebrew::Services::FormulaWrapper, service_name: "sh.brew.package"),
          file:   service_file,
          enable: true,
        )
      end

      expect([loaded_name, log.read]).to eq([
        "org.example.package",
        <<~EOS,
          enable #{Homebrew::Services::System.domain_target}/org.example.package
          bootstrap #{Homebrew::Services::System.domain_target} #{service_file}
        EOS
      ])
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
            name:                "name",
            service_name:        "service.name",
            service_startup?:    false,
            source_service_file: instance_double(Pathname, exist?: false),
            path_dirs:           [],
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
      expect(described_class).to receive(:launchctl_load).once.and_return("service.name")
      expect do
        services_cli.service_load(
          instance_double(
            Homebrew::Services::FormulaWrapper,
            name:                    "name",
            service_name:            "service.name",
            service_startup?:        false,
            service_file_generated?: false,
            source_service_file:     instance_double(Pathname, exist?: false),
            path_dirs:               [],
          ),
          nil,
          enable: false,
        )
      end.to output("==> Successfully ran `name` (label: service.name)\n").to_stdout
    end

    it "runs a compatible macOS source service file" do
      allow(Homebrew::Services::System).to receive_messages(launchctl?: true, root?: false, systemctl?: false)

      service_file = mktmpdir/"sh.brew.name.plist"
      source_service_file = mktmpdir/"homebrew.mxcl.name.plist"
      source_service_file.write("service")
      service = instance_double(
        Homebrew::Services::FormulaWrapper,
        name:                    "name",
        service_name:            "sh.brew.name",
        service_startup?:        false,
        service_file_generated?: false,
        service_file:,
        source_service_file:,
        path_dirs:               [],
      )
      expect(services_cli).to receive(:launchctl_load)
        .with(service, file: source_service_file, enable: false)
        .and_return("sh.brew.name")

      expect do
        services_cli.service_load(service, nil, enable: false)
      end.to output("==> Successfully ran `name` (label: sh.brew.name)\n").to_stdout
    end

    it "runs an unchanged generated macOS service from its source file" do
      allow(Homebrew::Services::System).to receive_messages(launchctl?: true, root?: false, systemctl?: false)

      source_service_file = mktmpdir/"sh.brew.name.plist"
      source_service_file.write("generated service")
      service = instance_double(
        Homebrew::Services::FormulaWrapper,
        name:                    "name",
        service_name:            "sh.brew.name",
        service_startup?:        false,
        service_file_generated?: true,
        service_contents:        "generated service",
        source_service_file:,
        path_dirs:               [],
      )
      loaded_file = mktmpdir/"not-loaded"
      allow(services_cli).to receive(:launchctl_load) do |_target, file:, **_options|
        loaded_file = Pathname(file)
        "sh.brew.name"
      end

      services_cli.service_load(service, nil, enable: false)

      expect(loaded_file).to eq(source_service_file)
    end

    it "runs a generated macOS service with user environment overrides" do
      allow(Homebrew::Services::System).to receive_messages(launchctl?: true, root?: false, systemctl?: false)

      source_service_file = mktmpdir/"sh.brew.name.plist"
      source_service_file.write("source service")
      service = instance_double(
        Homebrew::Services::FormulaWrapper,
        name:                    "name",
        service_name:            "sh.brew.name",
        service_startup?:        false,
        service_file_generated?: true,
        service_contents:        "generated service with overrides",
        source_service_file:,
        path_dirs:               [],
      )
      loaded_contents = ""
      loaded_file = mktmpdir/"not-loaded"
      allow(services_cli).to receive(:launchctl_load) do |_target, file:, **_options|
        loaded_file = Pathname(file)
        loaded_contents = loaded_file.read
        "sh.brew.name"
      end

      services_cli.service_load(service, nil, enable: false)

      expect([loaded_contents, loaded_file.extname, loaded_file.exist?])
        .to eq(["generated service with overrides", ".plist", false])
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
        expect(path_dirs).to all(be_a_directory)
        "service.name"
      end

      expect do
        services_cli.service_load(
          instance_double(
            Homebrew::Services::FormulaWrapper,
            name:                    "name",
            service_name:            "service.name",
            service_startup?:        false,
            service_file_generated?: false,
            source_service_file:     instance_double(Pathname, exist?: false),
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
