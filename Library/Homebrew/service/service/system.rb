# typed: true
# frozen_string_literal: true

require_relative "system/systemctl"

module Service
  module System
    extend FileUtils

    # Path to launchctl binary.
    def self.launchctl
      @launchctl ||= which("launchctl")
    end

    # Is this a launchctl system
    def self.launchctl?
      launchctl.present?
    end

    # Is this a systemd system
    def self.systemctl?
      Systemctl.executable.present?
    end

    # Woohoo, we are root dude!
    def self.root?
      Process.euid.zero?
    end

    # Current user running `[sudo] brew services`.
    def self.user
      @user ||= ENV["USER"].presence || Utils.safe_popen_read("/usr/bin/whoami").chomp
    end

    def self.user_of_process(pid)
      if pid.nil? || pid.zero?
        user
      else
        Utils.safe_popen_read("ps", "-o", "user", "-p", pid.to_s).lines.second&.chomp
      end
    end

    # Run at boot.
    def self.boot_path
      if launchctl?
        Pathname.new("/Library/LaunchDaemons")
      elsif systemctl?
        Pathname.new("/usr/lib/systemd/system")
      end
    end

    # Run at login.
    def self.user_path
      if launchctl?
        Pathname.new("#{Dir.home}/Library/LaunchAgents")
      elsif systemctl?
        Pathname.new("#{Dir.home}/.config/systemd/user")
      end
    end

    # If root, return `boot_path`, else return `user_path`.
    def self.path
      root? ? boot_path : user_path
    end

    def self.domain_target
      if root?
        "system"
      elsif (ssh_tty = ENV.fetch("HOMEBREW_SSH_TTY", nil).present? && File.stat("/dev/console").uid != Process.uid) ||
            (sudo_user = ENV.fetch("HOMEBREW_SUDO_USER", nil).present?) ||
            (Process.uid != Process.euid)
        if @output_warning.blank? && ENV.fetch("HOMEBREW_SERVICES_NO_DOMAIN_WARNING", nil).blank?
          if ssh_tty
            opoo "running over SSH without /dev/console ownership, using user/* instead of gui/* domain!"
          elsif sudo_user
            opoo "running through sudo, using user/* instead of gui/* domain!"
          else
            opoo "uid and euid do not match, using user/* instead of gui/* domain!"
          end
          unless Homebrew::EnvConfig.no_env_hints?
            puts "Hide this warning by setting HOMEBREW_SERVICES_NO_DOMAIN_WARNING."
            puts "Hide these hints with HOMEBREW_NO_ENV_HINTS (see `man brew`)."
          end
          @output_warning = true
        end
        "user/#{Process.euid}"
      else
        "gui/#{Process.uid}"
      end
    end
  end
end
