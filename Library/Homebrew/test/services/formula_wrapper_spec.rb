# frozen_string_literal: true

require "services/system"
require "services/formula_wrapper"
require "tempfile"

RSpec.describe Homebrew::Services::FormulaWrapper do
  subject(:service) { described_class.new(formula) }

  let(:formula) do
    instance_double(Formula,
                    name:                   "mysql",
                    plist_name:             "plist-mysql-test",
                    service_name:           "plist-mysql-test",
                    launchd_service_path:   Pathname.new("/usr/local/opt/mysql/homebrew.mysql.plist"),
                    systemd_service_path:   Pathname.new("/usr/local/opt/mysql/homebrew.mysql.service"),
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

  describe "#service_file" do
    it "macOS - outputs the full service file path" do
      allow(Homebrew::Services::System).to receive(:launchctl?).and_return(true)
      expect(service.service_file.to_s).to eq("/usr/local/opt/mysql/homebrew.mysql.plist")
    end

    it "systemD - outputs the full service file path" do
      allow(Homebrew::Services::System).to receive_messages(launchctl?: false, systemctl?: true)
      expect(service.service_file.to_s).to eq("/usr/local/opt/mysql/homebrew.mysql.service")
    end

    it "Other - raises an error" do
      allow(Homebrew::Services::System).to receive_messages(launchctl?: false, systemctl?: false)
      expect do
        service.service_file
      end.to raise_error(UsageError,
                         "Invalid usage: `brew services` is supported only on macOS or Linux (with systemd)!")
    end
  end

  describe "#name" do
    it "outputs formula name" do
      expect(service.name).to eq("mysql")
    end
  end

  describe "#service_name" do
    it "macOS - outputs the service name" do
      allow(Homebrew::Services::System).to receive(:launchctl?).and_return(true)
      expect(service.service_name).to eq("plist-mysql-test")
    end

    it "systemD - outputs the service name" do
      allow(Homebrew::Services::System).to receive_messages(launchctl?: false, systemctl?: true)
      expect(service.service_name).to eq("plist-mysql-test")
    end

    it "Other - raises an error" do
      allow(Homebrew::Services::System).to receive_messages(launchctl?: false, systemctl?: false)
      expect do
        service.service_name
      end.to raise_error(UsageError,
                         "Invalid usage: `brew services` is supported only on macOS or Linux (with systemd)!")
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
      expect(service.dest.to_s).to eq("/tmp_home/Library/LaunchAgents/homebrew.mysql.plist")
    end

    it "systemD - outputs the destination for the service file" do
      allow(Homebrew::Services::System).to receive(:systemctl?).and_return(true)
      expect(service.dest.to_s).to eq("/tmp_home/.config/systemd/user/homebrew.mysql.service")
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

    it "systemD - outputs if the service is loaded" do
      allow(Homebrew::Services::System).to receive_messages(launchctl?: false, systemctl?: true)
      allow(Homebrew::Services::System::Systemctl).to receive(:quiet_run).and_return(false)
      allow(Utils).to receive(:safe_popen_read)
      expect(service.loaded?).to be(false)
    end

    it "Other - raises an error" do
      allow(Homebrew::Services::System).to receive_messages(launchctl?: false, systemctl?: false)
      expect do
        service.loaded?
      end.to raise_error(UsageError,
                         "Invalid usage: `brew services` is supported only on macOS or Linux (with systemd)!")
    end
  end

  describe "#plist?" do
    it "false if not installed" do
      allow(service).to receive(:installed?).and_return(false)
      expect(service.plist?).to be(false)
    end

    it "true if installed and file" do
      tempfile = File.new("/tmp/foo", File::CREAT)
      allow(service).to receive_messages(installed?: true, service_file: Pathname.new(tempfile))
      expect(service.plist?).to be(true)
      File.delete(tempfile)
    end

    it "false if opt_prefix missing" do
      allow(service).to receive_messages(installed?:   true,
                                         service_file: Pathname.new(File::NULL),
                                         formula:      instance_double(Formula,
                                                                       opt_prefix: Pathname.new("/dfslkfhjdsolshlk")))
      expect(service.plist?).to be(false)
    end
  end

  describe "#owner" do
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

    it "returns nil if no service" do
      allow(service).to receive(:service?).once.and_return(false)

      expect(service.timed?).to be_nil
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

    it "returns nil if no service" do
      allow(service).to receive(:service?).once.and_return(false)

      expect(service.keep_alive?).to be_nil
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
      allow_any_instance_of(described_class).to receive_messages(service?: false, service_file_present?: false)
      expected = {
        exit_code:    nil,
        file:         Pathname.new("/usr/local/opt/mysql/homebrew.mysql.plist"),
        loaded:       false,
        loaded_file:  nil,
        name:         "mysql",
        pid:          nil,
        registered:   false,
        running:      false,
        schedulable:  nil,
        service_name: "plist-mysql-test",
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
        file:         Pathname.new("/tmp_home/Library/LaunchAgents/homebrew.mysql.plist"),
        loaded:       false,
        loaded_file:  nil,
        name:         "mysql",
        pid:          nil,
        registered:   true,
        running:      false,
        schedulable:  nil,
        service_name: "plist-mysql-test",
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
        file:           Pathname.new("/tmp_home/Library/LaunchAgents/homebrew.mysql.plist"),
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
        service_name:   "plist-mysql-test",
        status:         :none,
        user:           nil,
        working_dir:    nil,
      }
      expect(service.to_hash).to eq(expected)
    end
  end
end
