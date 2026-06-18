# typed: true
# frozen_string_literal: true

require "services/system"

RSpec.describe Homebrew::Services::System do
  let(:bindir) { mktmpdir }

  before do
    described_class.reset_launchctl!
    Homebrew::Services::System::Systemctl.reset_executable!
  end

  describe "#launchctl" do
    it "returns the launchctl command location when available and nil when unavailable" do
      launchctl = bindir/"launchctl"
      launchctl.write <<~SH
        #!/bin/sh
        exit 0
      SH
      launchctl.chmod 0755

      with_env(PATH: bindir.to_s) do
        expect(described_class.launchctl).to eq(launchctl)
      end

      described_class.reset_launchctl!
      launchctl.unlink

      with_env(PATH: bindir.to_s) do
        expect(described_class.launchctl).to be_nil
      end
    end
  end

  describe "#launchctl?" do
    it "returns true when launchctl is available and false when unavailable" do
      launchctl = bindir/"launchctl"
      launchctl.write <<~SH
        #!/bin/sh
        exit 0
      SH
      launchctl.chmod 0755

      with_env(PATH: bindir.to_s) do
        expect(described_class.launchctl?).to be(true)
      end

      described_class.reset_launchctl!
      launchctl.unlink

      with_env(PATH: bindir.to_s) do
        expect(described_class.launchctl?).to be(false)
      end
    end
  end

  describe "#systemctl?" do
    it "returns true when systemctl is available and false when unavailable" do
      systemctl = bindir/"systemctl"
      systemctl.write <<~SH
        #!/bin/sh
        exit 0
      SH
      systemctl.chmod 0755

      with_env(PATH: bindir.to_s) do
        expect(described_class.systemctl?).to be(true)
      end

      Homebrew::Services::System::Systemctl.reset_executable!
      systemctl.unlink

      with_env(PATH: bindir.to_s) do
        expect(described_class.systemctl?).to be(false)
      end
    end
  end

  describe "#root?" do
    it "checks if the command is ran as root" do
      expect(described_class.root?).to be(false)
    end
  end

  describe "#user" do
    it "returns the current username" do
      expect(described_class.user).to eq(ENV.fetch("USER"))
    end
  end

  describe "#user_of_process" do
    it "returns the username for empty PID" do
      expect(described_class.user_of_process(nil)).to eq(ENV.fetch("USER"))
    end

    it "returns the PID username" do
      allow(Utils).to receive(:safe_popen_read).and_return <<~EOS
        USER
        user
      EOS
      expect(described_class.user_of_process(50)).to eq("user")
    end

    it "returns nil if unavailable" do
      allow(Utils).to receive(:safe_popen_read).and_return <<~EOS
        USER
      EOS
      expect(described_class.user_of_process(50)).to be_nil
    end
  end

  describe "#user_exists?" do
    it "returns true when a specified user exists" do
      expect(described_class.user_exists?(ENV.fetch("USER"))).to be(true)
    end

    it "returns false when a specified user does not exist" do
      expect(described_class.user_exists?("not_a_real_user_#{SecureRandom.hex(4)}")).to be(false)
    end
  end

  describe "#domain_target" do
    it "returns the current domain target" do
      allow(described_class).to receive(:root?).and_return(false)
      expect(described_class.domain_target).to match(%r{gui/(\d+)})
    end

    it "returns the root domain target" do
      allow(described_class).to receive(:root?).and_return(true)
      expect(described_class.domain_target).to match("system")
    end
  end

  describe "#boot_path" do
    it "macOS - returns the boot path" do
      allow(described_class).to receive(:launchctl?).and_return(true)
      expect(described_class.boot_path.to_s).to eq("/Library/LaunchDaemons")
    end

    it "SystemD - returns the boot path" do
      allow(described_class).to receive_messages(launchctl?: false, systemctl?: true)
      expect(described_class.boot_path.to_s).to eq("/usr/lib/systemd/system")
    end

    it "Unknown - raises an error" do
      allow(described_class).to receive_messages(launchctl?: false, systemctl?: false)
      expect do
        described_class.boot_path.to_s
      end.to raise_error(UsageError,
                         "Invalid usage: `brew services` is supported only on macOS or Linux (with systemd)!")
    end
  end

  describe "#user_path" do
    it "macOS - returns the user path" do
      ENV["HOME"] = "/tmp_home"
      allow(described_class).to receive_messages(launchctl?: true, systemctl?: false)
      expect(described_class.user_path.to_s).to eq("/tmp_home/Library/LaunchAgents")
    end

    it "systemD - returns the user path" do
      ENV["HOME"] = "/tmp_home"
      allow(described_class).to receive_messages(launchctl?: false, systemctl?: true)
      expect(described_class.user_path.to_s).to eq("/tmp_home/.config/systemd/user")
    end

    it "Unknown - raises an error" do
      ENV["HOME"] = "/tmp_home"
      allow(described_class).to receive_messages(launchctl?: false, systemctl?: false)
      expect do
        described_class.user_path.to_s
      end.to raise_error(UsageError,
                         "Invalid usage: `brew services` is supported only on macOS or Linux (with systemd)!")
    end
  end

  describe "#path" do
    it "macOS - user - returns the current relevant path" do
      ENV["HOME"] = "/tmp_home"
      allow(described_class).to receive_messages(root?: false, launchctl?: true, systemctl?: false)
      expect(described_class.path.to_s).to eq("/tmp_home/Library/LaunchAgents")
    end

    it "macOS - root- returns the current relevant path" do
      ENV["HOME"] = "/tmp_home"
      allow(described_class).to receive_messages(root?: true, launchctl?: true, systemctl?: false)
      expect(described_class.path.to_s).to eq("/Library/LaunchDaemons")
    end

    it "systemD - user - returns the current relevant path" do
      ENV["HOME"] = "/tmp_home"
      allow(described_class).to receive_messages(root?: false, launchctl?: false, systemctl?: true)
      expect(described_class.path.to_s).to eq("/tmp_home/.config/systemd/user")
    end

    it "systemD - root- returns the current relevant path" do
      ENV["HOME"] = "/tmp_home"
      allow(described_class).to receive_messages(root?: true, launchctl?: false, systemctl?: true)
      expect(described_class.path.to_s).to eq("/usr/lib/systemd/system")
    end
  end
end
