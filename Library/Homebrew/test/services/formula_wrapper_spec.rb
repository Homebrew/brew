# typed: true
# frozen_string_literal: true

require "services/system"
require "services/formula_wrapper"
require "tempfile"

RSpec.describe Homebrew::Services::FormulaWrapper, :needs_daemon_manager do
  subject(:service) { described_class.new(formula) }

  let(:formula) do
    instance_double(Formula,
                    name:                   "mysql",
                    plist_name:             "sh.brew.mysql",
                    plist_names:            ["sh.brew.mysql"],
                    service_name:           "sh.brew.mysql",
                    service_names:          ["sh.brew.mysql", "homebrew.mysql"],
                    launchd_service_path:   Pathname.new("/usr/local/opt/mysql/sh.brew.mysql.plist"),
                    launchd_service_paths:  [Pathname.new("/usr/local/opt/mysql/sh.brew.mysql.plist")],
                    systemd_service_path:   Pathname.new("/usr/local/opt/mysql/sh.brew.mysql.service"),
                    systemd_service_paths:  [Pathname.new("/usr/local/opt/mysql/sh.brew.mysql.service"),
                                             Pathname.new("/usr/local/opt/mysql/homebrew.mysql.service")],
                    systemd_timer_path:     Pathname.new("/usr/local/opt/mysql/sh.brew.mysql.timer"),
                    systemd_timer_paths:    [Pathname.new("/usr/local/opt/mysql/sh.brew.mysql.timer"),
                                             Pathname.new("/usr/local/opt/mysql/homebrew.mysql.timer")],
                    opt_prefix:             Pathname.new("/usr/local/opt/mysql"),
                    any_version_installed?: true,
                    service?:               false)
  end
  let(:service_object) do
    instance_double(Homebrew::Service,
                    requires_root?: false,
                    timed?:         false,
                    keep_alive?:    false,
                    command:        "/bin/cmd",
                    manual_command: "/bin/cmd",
                    working_dir:    nil,
                    root_dir:       nil,
                    log_path:       nil,
                    error_log_path: nil,
                    interval:       nil,
                    cron:           nil)
  end

  before do
    allow(formula).to receive(:service).and_return(service_object)
    ENV["HOME"] = "/tmp_home"
  end

  describe ".service_file_label" do
    it "reads the label from a binary plist", :needs_macos do
      service_file = mktmpdir/"binary.plist"
      service_file.write <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>Label</key>
          <string>org.example.binary</string>
        </dict>
        </plist>
      XML
      SystemCommand.safe_system "/usr/bin/plutil", "-convert", "binary1", service_file

      expect(described_class.service_file_label(service_file)).to eq("org.example.binary")
    end
  end

  describe "#service_file" do
    it "macOS - outputs the full service file path" do
      allow(Homebrew::Services::System).to receive(:launchctl?).and_return(true)
      expect(service.service_file.to_s).to eq("/usr/local/opt/mysql/sh.brew.mysql.plist")
    end

    it "systemD - outputs the full service file path" do
      allow(Homebrew::Services::System).to receive_messages(launchctl?: false, systemctl?: true)
      expect(service.service_file.to_s).to eq("/usr/local/opt/mysql/sh.brew.mysql.service")
    end

    it "Other - raises an error" do
      allow(Homebrew::Services::System).to receive_messages(launchctl?: false, systemctl?: false)
      expect do
        service.service_file
      end.to raise_error(UsageError,
                         "Invalid usage: `brew services` is supported only on macOS or Linux (with systemd)!")
    end
  end

  describe "#source_service_file" do
    before do
      allow(Homebrew::Services::System).to receive(:launchctl?).and_return(true)
    end

    it "uses the compatible macOS service file when it is the only one present" do
      source_dir = mktmpdir
      service_files = [source_dir/"sh.brew.mysql.plist", source_dir/"homebrew.mxcl.mysql.plist"]
      service_files.last.write("service")
      allow(formula).to receive(:launchd_service_paths).and_return(service_files)

      expect(service.source_service_file).to eq(service_files.last)
    end

    it "prefers the canonical macOS service file" do
      source_dir = mktmpdir
      service_files = [source_dir/"sh.brew.mysql.plist", source_dir/"homebrew.mxcl.mysql.plist"]
      service_files.each { |file| file.write("service") }
      allow(formula).to receive(:launchd_service_paths).and_return(service_files)

      expect(service.source_service_file).to eq(service_files.first)
    end

    it "uses the compatible systemd service file when it is the only one present" do
      service_files = [mktmpdir/"sh.brew.mysql.service", mktmpdir/"homebrew.mysql.service"]
      service_files.last.write("service")
      allow(Homebrew::Services::System).to receive_messages(launchctl?: false, systemctl?: true)
      allow(formula).to receive(:systemd_service_paths).and_return(service_files)

      expect(service.source_service_file).to eq(service_files.last)
    end
  end

  describe "#timer_file" do
    it "uses the compatible systemd timer file when it is the only one present" do
      timer_files = [mktmpdir/"sh.brew.mysql.timer", mktmpdir/"homebrew.mysql.timer"]
      timer_files.last.write("timer")
      allow(Homebrew::Services::System).to receive_messages(launchctl?: false, systemctl?: true)
      allow(formula).to receive(:systemd_timer_paths).and_return(timer_files)

      expect([service.timer_file, service.timer_name]).to eq([timer_files.last, "sh.brew.mysql.timer"])
    end
  end

  describe "#name" do
    it "outputs formula name" do
      expect(service.name).to eq("mysql")
    end
  end

  describe "#service_contents" do
    it "macOS - generates the plist from the formula service block" do
      allow(Homebrew::Services::System).to receive(:launchctl?).and_return(true)
      allow(service).to receive(:service?).and_return(true)
      allow(service_object).to receive_messages(command?: true, to_plist: "plist contents")

      expect(service.service_contents).to eq("plist contents")
    end

    it "systemD - generates the unit from the formula service block" do
      allow(Homebrew::Services::System).to receive_messages(launchctl?: false, systemctl?: true)
      allow(service).to receive(:service?).and_return(true)
      allow(service_object).to receive_messages(command?: true, to_systemd_unit: "unit contents")

      expect(service.service_contents).to eq("unit contents")
    end

    it "reads the package-provided service file when the service block has no command" do
      service_file = mktmpdir/"custom.name.plist"
      service_file.write("package plist")
      allow(service).to receive_messages(service?: true, service_file:)
      allow(service_object).to receive(:command?).and_return(false)

      expect(service.service_contents).to eq("package plist")
    end

    it "reads the package-provided service file when the formula has no service block" do
      service_file = mktmpdir/"custom.name.plist"
      service_file.write("package plist")
      allow(service).to receive(:service_file).and_return(service_file)

      expect(service.service_contents).to eq("package plist")
    end
  end

  describe "#timer_contents" do
    it "generates a timer from the formula service block" do
      allow(service).to receive(:service?).and_return(true)
      allow(service_object).to receive_messages(command?: true, to_systemd_timer: "timer contents")

      expect(service.timer_contents).to eq("timer contents")
    end

    it "reads a package-provided timer file" do
      timer_file = mktmpdir/"homebrew.mysql.timer"
      timer_file.write("package timer")
      allow(service).to receive_messages(service?: false, timer_file:)

      expect(service.timer_contents).to eq("package timer")
    end

    it "rewrites a compatible package-provided timer unit for the destination label" do
      timer_file = mktmpdir/"homebrew.mysql.timer"
      timer_file.write("[Timer]\nUnit=homebrew.mysql.service\n")
      allow(service).to receive_messages(
        service?:      false,
        service_name:  "sh.brew.mysql",
        service_names: ["sh.brew.mysql", "homebrew.mysql"],
        timer_file:,
      )

      expect(service.timer_contents).to eq("[Timer]\nUnit=sh.brew.mysql.service\n")
    end

    it "preserves an unrelated package-provided timer unit" do
      timer_file = mktmpdir/"homebrew.mysql.timer"
      timer_file.write("[Timer]\nUnit=custom.mysql.service\n")
      allow(service).to receive_messages(service?: false, timer_file:)

      expect(service.timer_contents).to eq("[Timer]\nUnit=custom.mysql.service\n")
    end
  end

  describe "#service_name" do
    it "macOS - outputs the service name" do
      allow(Homebrew::Services::System).to receive(:launchctl?).and_return(true)
      expect(service.service_name).to eq("sh.brew.mysql")
    end

    it "systemD - outputs the service name" do
      allow(Homebrew::Services::System).to receive_messages(launchctl?: false, systemctl?: true)
      expect(service.service_name).to eq("sh.brew.mysql")
    end

    it "Other - raises an error" do
      allow(Homebrew::Services::System).to receive_messages(launchctl?: false, systemctl?: false)
      expect do
        service.service_name
      end.to raise_error(UsageError,
                         "Invalid usage: `brew services` is supported only on macOS or Linux (with systemd)!")
    end
  end

  describe "#service_names" do
    it "includes both compatible default macOS labels" do
      allow(Homebrew::Services::System).to receive(:launchctl?).and_return(true)
      allow(formula).to receive(:plist_names).and_return(["sh.brew.mysql", "homebrew.mxcl.mysql"])

      expect(service.service_names).to eq(["sh.brew.mysql", "homebrew.mxcl.mysql"])
    end

    it "includes both compatible default systemd labels" do
      allow(Homebrew::Services::System).to receive_messages(launchctl?: false, systemctl?: true)

      expect(service.service_names).to eq(["sh.brew.mysql", "homebrew.mysql"])
    end
  end

  describe "#dest_dir" do
    before do
      allow(Homebrew::Services::System).to receive_messages(launchctl?: false, systemctl?: false)
    end

    it "macOS - user - outputs the destination directory for the service file" do
      ENV["HOME"] = "/tmp_home"
      allow(Homebrew::Services::System).to receive_messages(root?: false, launchctl?: true)
      expect(service.dest_dir.to_s).to eq("/tmp_home/Library/LaunchAgents")
    end

    it "macOS - root - outputs the destination directory for the service file" do
      allow(Homebrew::Services::System).to receive_messages(launchctl?: true, root?: true)
      expect(service.dest_dir.to_s).to eq("/Library/LaunchDaemons")
    end

    it "systemD - user - outputs the destination directory for the service file" do
      ENV["HOME"] = "/tmp_home"
      allow(Homebrew::Services::System).to receive_messages(root?: false, launchctl?: false, systemctl?: true)
      expect(service.dest_dir.to_s).to eq("/tmp_home/.config/systemd/user")
    end

    it "systemD - root - outputs the destination directory for the service file" do
      allow(Homebrew::Services::System).to receive_messages(root?: true, launchctl?: false, systemctl?: true)
      expect(service.dest_dir.to_s).to eq("/usr/lib/systemd/system")
    end
  end

  describe "#dest" do
    before do
      ENV["HOME"] = "/tmp_home"
      allow(Homebrew::Services::System).to receive_messages(launchctl?: false, systemctl?: false)
    end

    it "macOS - outputs the destination for the service file" do
      allow(Homebrew::Services::System).to receive(:launchctl?).and_return(true)
      expect(service.dest.to_s).to eq("/tmp_home/Library/LaunchAgents/sh.brew.mysql.plist")
    end

    it "systemD - outputs the destination for the service file" do
      allow(Homebrew::Services::System).to receive(:systemctl?).and_return(true)
      expect(service.dest.to_s).to eq("/tmp_home/.config/systemd/user/sh.brew.mysql.service")
    end

    it "systemD - includes both compatible destinations" do
      allow(Homebrew::Services::System).to receive_messages(launchctl?: false, systemctl?: true)

      expect(service.destinations.map(&:to_s)).to eq([
        "/tmp_home/.config/systemd/user/sh.brew.mysql.service",
        "/tmp_home/.config/systemd/user/homebrew.mysql.service",
      ])
    end
  end

  describe "#timer_destinations" do
    it "includes both compatible systemd timer destinations" do
      allow(Homebrew::Services::System).to receive_messages(launchctl?: false, systemctl?: true)

      expect(service.timer_destinations.map(&:to_s)).to eq([
        "/tmp_home/.config/systemd/user/sh.brew.mysql.timer",
        "/tmp_home/.config/systemd/user/homebrew.mysql.timer",
      ])
    end
  end

  describe "#installed?" do
    it "outputs if the service formula is installed" do
      expect(service.installed?).to be(true)
    end
  end

  describe "#loaded?" do
    it "macOS - outputs if the service is loaded" do
      allow(Homebrew::Services::System).to receive_messages(launchctl?: true, systemctl?: false)
      allow(Utils).to receive(:safe_popen_read)
      expect(service.loaded?).to be(false)
    end

    it "finds a service loaded with the compatible macOS label" do
      allow(Homebrew::Services::System).to receive_messages(launchctl?: true, systemctl?: false)
      allow(formula).to receive(:plist_names).and_return(["sh.brew.mysql", "homebrew.mxcl.mysql"])
      allow(Homebrew::Services::System).to receive(:launchctl_find_service)
        .with("sh.brew.mysql").and_return(["", false, :launchctl_list])
      allow(Homebrew::Services::System).to receive(:launchctl_find_service)
        .with("homebrew.mxcl.mysql").and_return(["pid = 123", true, :launchctl_print])

      expect(service.loaded?).to be(true)
      expect(service.pid).to eq(123)
      expect(service.active_service_name).to eq("homebrew.mxcl.mysql")
    end

    it "finds a service loaded with a package-provided plist label" do
      source_dir = mktmpdir
      service_files = [source_dir/"sh.brew.mysql.plist", source_dir/"homebrew.mxcl.mysql.plist"]
      package_file = source_dir/"vendor.mysql.plist"
      package_file.write <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>Label</key>
          <string>org.example.mysql</string>
        </dict>
        </plist>
      XML
      allow(Homebrew::Services::System).to receive_messages(launchctl?: true, systemctl?: false)
      allow(formula).to receive(:launchd_service_paths).and_return(service_files)
      allow(Homebrew::Services::System).to receive(:launchctl_find_service)
        .with("sh.brew.mysql").and_return(["", false, :launchctl_list])
      allow(Homebrew::Services::System).to receive(:launchctl_find_service)
        .with("homebrew.mxcl.mysql").and_return(["", false, :launchctl_list])
      allow(Homebrew::Services::System).to receive(:launchctl_find_service)
        .with("org.example.mysql").and_return(["pid = 123", true, :launchctl_print])

      expect([service.loaded?, service.active_service_name]).to eq([true, "org.example.mysql"])
    end

    it "stops probing compatible labels after finding a running service" do
      allow(Homebrew::Services::System).to receive_messages(launchctl?: true, systemctl?: false)
      allow(formula).to receive(:plist_names).and_return(["sh.brew.mysql", "homebrew.mxcl.mysql"])
      expect(Homebrew::Services::System).to receive(:launchctl_find_service)
        .with("sh.brew.mysql").and_return(["pid = 123", true, :launchctl_print])
      expect(Homebrew::Services::System).not_to receive(:launchctl_find_service).with("homebrew.mxcl.mysql")

      expect(service.active_service_name).to eq("sh.brew.mysql")
    end

    it "prefers a running compatible label over an earlier loaded label" do
      allow(Homebrew::Services::System).to receive_messages(launchctl?: true, systemctl?: false)
      allow(formula).to receive(:plist_names).and_return(["sh.brew.mysql", "homebrew.mxcl.mysql"])
      allow(Homebrew::Services::System).to receive(:launchctl_find_service)
        .with("sh.brew.mysql").and_return(["last exit code = 0", true, :launchctl_print])
      allow(Homebrew::Services::System).to receive(:launchctl_find_service)
        .with("homebrew.mxcl.mysql").and_return(["pid = 123", true, :launchctl_print])

      expect(service.active_service_name).to eq("homebrew.mxcl.mysql")
    end

    it "systemD - outputs if the service is loaded" do
      allow(Homebrew::Services::System).to receive_messages(launchctl?: false, systemctl?: true)
      allow(Homebrew::Services::System::Systemctl).to receive(:quiet_run).and_return(false)
      allow(Utils).to receive(:safe_popen_read)
      expect(service.loaded?).to be(false)
    end

    it "systemD - checks timer status for timed services" do
      allow(Homebrew::Services::System).to receive_messages(launchctl?: false, systemctl?: true)
      allow(service).to receive(:timed?).and_return(true)
      expect(Homebrew::Services::System::Systemctl).to receive(:quiet_run)
        .with("status", "sh.brew.mysql.timer")
        .and_return(true)
      expect(Homebrew::Services::System::Systemctl).to receive(:quiet_run)
        .with("status", "homebrew.mysql.timer")
        .and_return(false)
      expect(Homebrew::Services::System::Systemctl).to receive(:quiet_run)
        .with("status", "homebrew.mysql.service")
        .and_return(false)

      expect(service.loaded?).to be(true)
    end

    it "finds a timed compatible systemd service running while its timer is inactive" do
      allow(Homebrew::Services::System).to receive_messages(launchctl?: false, systemctl?: true)
      allow(service).to receive(:timed?).and_return(true)
      allow(Homebrew::Services::System::Systemctl).to receive(:quiet_run).and_return(false)
      expect(Homebrew::Services::System::Systemctl).to receive(:quiet_run)
        .with("status", "homebrew.mysql.service").and_return(true)

      expect(service.loaded_service_names).to eq(["homebrew.mysql"])
    end

    it "finds a service loaded with the compatible systemd label" do
      allow(Homebrew::Services::System).to receive_messages(launchctl?: false, systemctl?: true)
      expect(Homebrew::Services::System::Systemctl).to receive(:quiet_run)
        .with("status", "sh.brew.mysql.service").and_return(false)
      expect(Homebrew::Services::System::Systemctl).to receive(:quiet_run)
        .with("status", "homebrew.mysql.service").and_return(true)

      expect(service.loaded_service_names).to eq(["homebrew.mysql"])
    end

    it "caches compatible systemd loaded-name probes" do
      allow(Homebrew::Services::System).to receive_messages(launchctl?: false, systemctl?: true)
      expect(Homebrew::Services::System::Systemctl).to receive(:quiet_run)
        .with("status", "sh.brew.mysql.service").once.and_return(false)
      expect(Homebrew::Services::System::Systemctl).to receive(:quiet_run)
        .with("status", "homebrew.mysql.service").once.and_return(true)

      expect([
        service.loaded?,
        service.loaded?(cached: true),
        service.loaded_service_names,
      ]).to eq([true, true, ["homebrew.mysql"]])
    end

    it "reports the active compatible systemd label" do
      allow(Homebrew::Services::System).to receive_messages(launchctl?: false, systemctl?: true)
      allow(Homebrew::Services::System::Systemctl).to receive(:popen_read)
        .with("status", "homebrew.mysql.service").and_return("Main PID: 123 (mysqld)")
      allow(service).to receive(:loaded_service_names).and_return(["homebrew.mysql"])

      expect(service.active_service_name).to eq("homebrew.mysql")
    end

    it "finds a running compatible systemd service when its timer is inactive" do
      allow(Homebrew::Services::System).to receive_messages(launchctl?: false, systemctl?: true)
      allow(service).to receive_messages(timed?: true, loaded_service_names: [])
      allow(Homebrew::Services::System::Systemctl).to receive(:popen_read)
        .with("status", "sh.brew.mysql.service").and_return("Active: inactive (dead)")
      allow(Homebrew::Services::System::Systemctl).to receive(:popen_read)
        .with("status", "homebrew.mysql.service").and_return("Main PID: 123 (mysqld)")

      expect(service.active_service_name).to eq("homebrew.mysql")
    end

    it "reports a failed legacy systemd service when the canonical unit is absent" do
      output = <<~EOS
        ● homebrew.mysql.service - Homebrew MySQL service
             Loaded: loaded (/tmp/homebrew.mysql.service; enabled)
             Active: failed (Result: exit-code)
            Process: 123 ExecStart=/bin/false (code=exited, status=1)
      EOS
      allow(Homebrew::Services::System).to receive_messages(launchctl?: false, systemctl?: true)
      allow(service).to receive(:loaded_service_names).and_return([])
      expect(Homebrew::Services::System::Systemctl).to receive(:popen_read)
        .with("status", "sh.brew.mysql.service").and_return("")
      expect(Homebrew::Services::System::Systemctl).to receive(:popen_read)
        .with("status", "homebrew.mysql.service").and_return(output)

      expect([
        service.active_service_name,
        service.exit_code,
        service.loaded_file,
      ]).to eq(["homebrew.mysql", 1, "/tmp/homebrew.mysql.service"])
    end

    it "Other - raises an error" do
      allow(Homebrew::Services::System).to receive_messages(launchctl?: false, systemctl?: false)
      expect do
        service.loaded?
      end.to raise_error(UsageError,
                         "Invalid usage: `brew services` is supported only on macOS or Linux (with systemd)!")
    end
  end

  describe "#owner" do
    it "reads the user from a launchd plist" do
      plist = mktmpdir/"homebrew.test.plist"
      plist.write <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0">
          <dict>
            <key>UserName</key>
            <string>_serviced</string>
          </dict>
        </plist>
      XML
      allow(Homebrew::Services::System).to receive(:launchctl?).and_return(true)
      allow(service).to receive(:dest).and_return(plist)

      expect(service.owner).to eq("_serviced")
    end

    it "prefers the active user service when a compatible root service also exists" do
      plist = mktmpdir/"sh.brew.mysql.plist"
      plist.write <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
          <dict>
            <key>Label</key>
            <string>sh.brew.mysql</string>
          </dict>
        </plist>
      XML
      allow(Homebrew::Services::System).to receive_messages(launchctl?: true, user: "user", user_path: plist.dirname)
      allow(service).to receive_messages(registered_destination:          plist,
                                         boot_path_service_file_present?: true,
                                         user_path_service_file_present?: true)

      expect(service.owner).to eq("user")
    end

    it "prefers the active root service when a compatible user service also exists" do
      plist = mktmpdir/"sh.brew.mysql.plist"
      plist.write <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
          <dict>
            <key>Label</key>
            <string>sh.brew.mysql</string>
          </dict>
        </plist>
      XML
      allow(Homebrew::Services::System).to receive_messages(boot_path: plist.dirname, launchctl?: true)
      allow(service).to receive_messages(registered_destination:          plist,
                                         boot_path_service_file_present?: true,
                                         user_path_service_file_present?: true)

      expect(service.owner).to eq("root")
    end

    it "root if file present" do
      allow(service).to receive(:boot_path_service_file_present?).and_return(true)
      expect(service.owner).to eq("root")
    end

    it "user if file present" do
      allow(service).to receive_messages(boot_path_service_file_present?: false,
                                         user_path_service_file_present?: true)
      allow(Homebrew::Services::System).to receive(:user).and_return("user")
      expect(service.owner).to eq("user")
    end

    it "nil if no file present" do
      allow(service).to receive_messages(boot_path_service_file_present?: false,
                                         user_path_service_file_present?: false)
      expect(service.owner).to be_nil
    end
  end

  describe "#service_file_present?" do
    it "macOS - outputs if the service file is present" do
      allow(Homebrew::Services::System).to receive_messages(launchctl?: true, systemctl?: false)
      expect(service.service_file_present?).to be(false)
    end

    it "macOS - outputs if the service file is present for root" do
      allow(Homebrew::Services::System).to receive_messages(launchctl?: true, systemctl?: false)
      expect(service.service_file_present?(type: :root)).to be(false)
    end

    it "macOS - outputs if the service file is present for user" do
      allow(Homebrew::Services::System).to receive_messages(launchctl?: true, systemctl?: false)
      expect(service.service_file_present?(type: :user)).to be(false)
    end
  end

  describe "#registered_destination" do
    it "prefers the service file matching the active compatible label" do
      allow(Homebrew::Services::System).to receive_messages(launchctl?: true, root?: false, systemctl?: false)
      allow(formula).to receive(:plist_names).and_return(["sh.brew.mysql", "homebrew.mxcl.mysql"])
      allow(Homebrew::Services::System).to receive(:launchctl_find_service)
        .with("sh.brew.mysql").and_return(["", false, :launchctl_list])
      allow(Homebrew::Services::System).to receive(:launchctl_find_service)
        .with("homebrew.mxcl.mysql").and_return(["pid = 123", true, :launchctl_print])
      allow(service).to receive(:dest_dir).and_return(mktmpdir)
      service.destinations.each { |destination| destination.write("service") }

      expect(service.registered_destination.basename.to_s).to eq("homebrew.mxcl.mysql.plist")
    end

    it "prefers the systemd service file matching the active compatible label" do
      allow(Homebrew::Services::System).to receive_messages(launchctl?: false, root?: false, systemctl?: true)
      allow(service).to receive_messages(active_service_name: "homebrew.mysql", dest_dir: mktmpdir)
      service.destinations.each { |destination| destination.write("service") }

      expect(service.registered_destination.basename.to_s).to eq("homebrew.mysql.service")
    end
  end

  describe ".from" do
    it "keeps the exact compatible label it discovers" do
      allow(Homebrew::Services::System).to receive(:launchctl?).and_return(true)
      allow(Formulary).to receive(:factory).with("mysql").and_return(formula)

      discovered_service = described_class.from("/tmp/sh.brew.mysql.plist")
      raise "Expected service to be discovered" unless discovered_service

      expect(discovered_service.service_names).to eq(["sh.brew.mysql"])
      expect(discovered_service.dest).to eq(Pathname("/tmp_home/Library/LaunchAgents/sh.brew.mysql.plist"))
    end

    it "keeps status discovery scoped to the exact label it discovers" do
      source_dir = mktmpdir
      service_files = [source_dir/"sh.brew.mysql.plist", source_dir/"homebrew.mxcl.mysql.plist"]
      service_files.zip(["sh.brew.mysql", "homebrew.mxcl.mysql"]).each do |file, label|
        file.write <<~XML
          <?xml version="1.0" encoding="UTF-8"?>
          <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
          <plist version="1.0">
          <dict>
            <key>Label</key>
            <string>#{label}</string>
          </dict>
          </plist>
        XML
      end
      allow(Homebrew::Services::System).to receive_messages(launchctl?: true, systemctl?: false)
      allow(formula).to receive(:launchd_service_paths).and_return(service_files)
      allow(Formulary).to receive(:factory).with("mysql").and_return(formula)
      expect(Homebrew::Services::System).to receive(:launchctl_service_running?)
        .with("sh.brew.mysql").and_return(false)
      expect(Homebrew::Services::System).not_to receive(:launchctl_service_running?)
        .with("homebrew.mxcl.mysql")

      discovered_service = described_class.from("sh.brew.mysql")
      raise "Expected service to be discovered" unless discovered_service

      expect(discovered_service.loaded_service_names).to be_empty
    end

    it "keeps the exact compatible systemd label it discovers" do
      allow(Homebrew::Services::System).to receive_messages(launchctl?: false, systemctl?: true)
      allow(Formulary).to receive(:factory).with("mysql").and_return(formula)

      discovered_service = described_class.from("/tmp/homebrew.mysql.service")
      raise "Expected service to be discovered" unless discovered_service

      expect(discovered_service.service_names).to eq(["homebrew.mysql"])
    end
  end

  describe "#owner?" do
    it "macOS - outputs the service file owner" do
      allow(Homebrew::Services::System).to receive_messages(launchctl?: true, systemctl?: false)
      expect(service.owner).to be_nil
    end
  end

  describe "#pid?" do
    it "outputs false because there is not PID" do
      allow(service).to receive(:pid).and_return(nil)
      expect(service.pid?).to be(false)
    end

    it "outputs false because there is a PID and it is zero" do
      allow(service).to receive(:pid).and_return(0)
      expect(service.pid?).to be(false)
    end

    it "outputs true because there is a PID and it is positive" do
      allow(service).to receive(:pid).and_return(12)
      expect(service.pid?).to be(true)
    end

    # This should never happen in practice, as PIDs cannot be negative.
    it "outputs false because there is a PID and it is negative" do
      allow(service).to receive(:pid).and_return(-1)
      expect(service.pid?).to be(false)
    end
  end

  describe "#pid", :needs_systemd do
    it "outputs nil because there is not pid" do
      expect(service.pid).to be_nil
    end
  end

  describe "#error?" do
    it "outputs false because there is no PID or exit code" do
      allow(service).to receive_messages(pid: nil, exit_code: nil)
      expect(service.error?).to be(false)
    end

    it "outputs false because there is a PID but no exit" do
      allow(service).to receive_messages(pid: 12, exit_code: nil)
      expect(service.error?).to be(false)
    end

    it "outputs false because there is a PID and a zero exit code" do
      allow(service).to receive_messages(pid: 12, exit_code: 0)
      expect(service.error?).to be(false)
    end

    it "outputs false because there is a PID and a positive exit code" do
      allow(service).to receive_messages(pid: 12, exit_code: 1)
      expect(service.error?).to be(false)
    end

    it "outputs false because there is no PID and a zero exit code" do
      allow(service).to receive_messages(pid: nil, exit_code: 0)
      expect(service.error?).to be(false)
    end

    it "outputs true because there is no PID and a positive exit code" do
      allow(service).to receive_messages(pid: nil, exit_code: 1)
      expect(service.error?).to be(true)
    end

    # This should never happen in practice, as exit codes cannot be negative.
    it "outputs true because there is no PID and a negative exit code" do
      allow(service).to receive_messages(pid: nil, exit_code: -1)
      expect(service.error?).to be(true)
    end
  end

  describe "#exit_code", :needs_systemd do
    it "outputs nil because there is no exit code" do
      expect(service.exit_code).to be_nil
    end
  end

  describe "#unknown_status?", :needs_systemd do
    it "outputs true because there is no PID" do
      expect(service.unknown_status?).to be(true)
    end
  end

  describe "#timed?" do
    it "returns true if timed service" do
      service_stub = instance_double(Homebrew::Service, timed?: true)
      allow(service).to receive_messages(service?: true, load_service: service_stub)
      allow(service_stub).to receive(:timed?).and_return(true)

      expect(service.timed?).to be(true)
    end

    it "returns false if no timed service" do
      service_stub = instance_double(Homebrew::Service, timed?: false)

      allow(service).to receive(:service?).once.and_return(true)
      allow(service).to receive(:load_service).once.and_return(service_stub)
      allow(service_stub).to receive(:timed?).and_return(false)

      expect(service.timed?).to be(false)
    end

    it "returns false if no service" do
      allow(service).to receive(:service?).once.and_return(false)

      expect(service.timed?).to be(false)
    end
  end

  describe "#keep_alive?" do
    it "returns true if service needs to stay alive" do
      service_stub = instance_double(Homebrew::Service, keep_alive?: true)

      allow(service).to receive(:service?).once.and_return(true)
      allow(service).to receive(:load_service).once.and_return(service_stub)

      expect(service.keep_alive?).to be(true)
    end

    it "returns false if service does not need to stay alive" do
      service_stub = instance_double(Homebrew::Service, keep_alive?: false)

      allow(service).to receive(:service?).once.and_return(true)
      allow(service).to receive(:load_service).once.and_return(service_stub)

      expect(service.keep_alive?).to be(false)
    end

    it "returns false if no service" do
      allow(service).to receive(:service?).once.and_return(false)

      expect(service.keep_alive?).to be(false)
    end
  end

  describe "#service_startup?" do
    it "outputs false since there is no startup" do
      expect(service.service_startup?).to be(false)
    end

    it "outputs true since there is a startup service" do
      allow(service).to receive(:service?).once.and_return(true)
      allow(service).to receive(:load_service).and_return(instance_double(Homebrew::Service, requires_root?: true))

      expect(service.service_startup?).to be(true)
    end
  end

  describe "#to_hash" do
    it "represents non-service values" do
      allow(Homebrew::Services::System).to receive_messages(launchctl?: true, systemctl?: false)
      allow_any_instance_of(described_class).to receive_messages(service?:              false,
                                                                 service_file_present?: false)
      expected = {
        exit_code:    nil,
        file:         Pathname.new("/usr/local/opt/mysql/sh.brew.mysql.plist"),
        loaded:       false,
        loaded_file:  nil,
        name:         "mysql",
        pid:          nil,
        registered:   false,
        running:      false,
        schedulable:  false,
        service_name: "sh.brew.mysql",
        status:       :none,
        user:         nil,
      }
      expect(service.to_hash).to eq(expected)
    end

    it "represents running non-service values" do
      ENV["HOME"] = "/tmp_home"
      allow(Homebrew::Services::System).to receive_messages(launchctl?: true, systemctl?: false)
      expect(service).to receive(:service?).twice.and_return(false)
      expect(service).to receive(:service_file_present?).twice.and_return(true)
      expected = {
        exit_code:    nil,
        file:         Pathname.new("/tmp_home/Library/LaunchAgents/sh.brew.mysql.plist"),
        loaded:       false,
        loaded_file:  nil,
        name:         "mysql",
        pid:          nil,
        registered:   true,
        running:      false,
        schedulable:  false,
        service_name: "sh.brew.mysql",
        status:       :none,
        user:         nil,
      }
      expect(service.to_hash).to eq(expected)
    end

    it "represents service values" do
      ENV["HOME"] = "/tmp_home"
      allow(Homebrew::Services::System).to receive_messages(launchctl?: true, systemctl?: false)
      expect(service).to receive(:service?).twice.and_return(true)
      expect(service).to receive(:service_file_present?).twice.and_return(true)
      expect(service).to receive(:load_service).twice.and_return(service_object)
      expected = {
        command:        "/bin/cmd",
        cron:           nil,
        error_log_path: nil,
        exit_code:      nil,
        file:           Pathname.new("/tmp_home/Library/LaunchAgents/sh.brew.mysql.plist"),
        interval:       nil,
        loaded:         false,
        loaded_file:    nil,
        log_path:       nil,
        name:           "mysql",
        pid:            nil,
        registered:     true,
        root_dir:       nil,
        running:        false,
        schedulable:    false,
        service_name:   "sh.brew.mysql",
        status:         :none,
        user:           nil,
        working_dir:    nil,
      }
      expect(service.to_hash).to eq(expected)
    end
  end
end
