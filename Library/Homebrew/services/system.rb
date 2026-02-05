# typed: strict
# frozen_string_literal: true

require_relative "system/systemctl"
require "utils/output"

module Homebrew
  module Services
    module System
      extend Utils::Output::Mixin

      LAUNCHCTL_DOMAIN_ACTION_NOT_SUPPORTED = T.let(125, Integer)
      MISSING_DAEMON_MANAGER_EXCEPTION_MESSAGE = T.let(
        "`brew services` is supported only on macOS or Linux (with systemd)!",
        String,
      )

      # Path to launchctl binary.
      sig { returns(T.nilable(Pathname)) }
      def self.launchctl
        @launchctl ||= T.let(which("launchctl"), T.nilable(Pathname))
      end

      # Is this a launchctl system
      sig { returns(T::Boolean) }
      def self.launchctl?
        launchctl.present?
      end

      # Is this a systemd system
      sig { returns(T::Boolean) }
      def self.systemctl?
        Systemctl.executable.present?
      end

      # Woohoo, we are root dude!
      sig { returns(T::Boolean) }
      def self.root?
        Process.euid.zero?
      end

      # Current user running `[sudo] brew services`.
      sig { returns(T.nilable(String)) }
      def self.user
        @user ||= T.let(ENV["USER"].presence || Utils.safe_popen_read("/usr/bin/whoami").chomp, T.nilable(String))
      end

      sig { params(pid: T.nilable(Integer)).returns(T.nilable(String)) }
      def self.user_of_process(pid)
        if pid.nil? || pid.zero?
          user
        else
          Utils.safe_popen_read("ps", "-o", "user", "-p", pid.to_s).lines.second&.chomp
        end
      end

      # Run at boot.
      sig { returns(Pathname) }
      def self.boot_path
        if launchctl?
          Pathname.new("/Library/LaunchDaemons")
        elsif systemctl?
          Pathname.new("/usr/lib/systemd/system")
        else
          raise UsageError, MISSING_DAEMON_MANAGER_EXCEPTION_MESSAGE
        end
      end

      # Run at login.
      sig { returns(Pathname) }
      def self.user_path
        if launchctl?
          Pathname.new("#{Dir.home}/Library/LaunchAgents")
        elsif systemctl?
          Pathname.new("#{Dir.home}/.config/systemd/user")
        else
          raise UsageError, MISSING_DAEMON_MANAGER_EXCEPTION_MESSAGE
        end
      end

      # If root, return `boot_path`, else return `user_path`.
      sig { returns(Pathname) }
      def self.path
        root? ? boot_path : user_path
      end

      sig { returns(String) }
      def self.domain_target
        if root?
          "system"
        elsif (ssh_tty = ENV.fetch("HOMEBREW_SSH_TTY", nil).present? &&
               File.stat("/dev/console").uid != Process.uid) ||
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
              puts "Hide this warning by setting `HOMEBREW_SERVICES_NO_DOMAIN_WARNING=1`."
              puts "Hide these hints with `HOMEBREW_NO_ENV_HINTS=1` (see `man brew`)."
            end
            @output_warning = T.let(true, T.nilable(TrueClass))
          end
          "user/#{Process.euid}"
        else
          "gui/#{Process.uid}"
        end
      end

      sig { returns(T::Array[String]) }
      def self.candidate_domain_targets
        candidates = [domain_target]
        candidates += ["user/#{Process.euid}", "gui/#{Process.uid}"] unless root?
        candidates.uniq
      end
    end
  end
end
