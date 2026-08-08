# typed: strict
# frozen_string_literal: true

require "etc"
require "system_command"
require_relative "system/systemctl"
require "utils/output"

module Homebrew
  module Services
    module System
      extend Utils::Output::Mixin

      LAUNCHCTL_DOMAIN_ACTION_NOT_SUPPORTED = 125
      MISSING_DAEMON_MANAGER_EXCEPTION_MESSAGE = "`brew services` is supported only on macOS or Linux (with systemd)!"

      # Path to launchctl binary.
      sig { returns(T.nilable(Pathname)) }
      def self.launchctl
        @launchctl ||= T.let(which("launchctl"), T.nilable(Pathname))
      end

      class << self
        sig { params(launchctl: T.nilable(Pathname)).returns(T.nilable(Pathname)) }
        attr_writer :launchctl
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

      sig { params(username: String).returns(T::Boolean) }
      def self.user_exists?(username)
        # Current user must be present
        return true if username == user

        # Check other users
        Etc.getpwnam(username)
        true
      rescue ArgumentError
        false
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
              $stderr.puts "Hide this warning by setting `HOMEBREW_SERVICES_NO_DOMAIN_WARNING=1`."
              $stderr.puts "Hide these hints with `HOMEBREW_NO_ENV_HINTS=1` (see `man brew`)."
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

      # Probe for a launchd service across all candidate domains.
      # Returns output text, success flag, and the command type used
      # (`:launchctl_print` or `:launchctl_list`). Pass `sudo: true` to run
      # the probe with elevated privileges (e.g. for system-owned services).
      sig { params(label: String, sudo: T::Boolean).returns([String, T::Boolean, Symbol]) }
      def self.launchctl_find_service(label, sudo: false)
        launchctl_path = launchctl
        return ["", false, :launchctl_list] unless launchctl_path

        candidate_domain_targets.each do |domain|
          cmd = [launchctl_path.to_s, "print", "#{domain}/#{label}"]
          output, success = launchctl_run(cmd, sudo:)
          if success && output.present?
            odebug cmd.join(" "), output
            return [output, true, :launchctl_print]
          end
        end

        cmd = [launchctl_path.to_s, "list", label]
        output, success = launchctl_run(cmd, sudo:)
        odebug cmd.join(" "), output
        [output, success && output.present?, :launchctl_list]
      end

      # Check if a launchd service is running, given its label (e.g. `homebrew.mxcl.foo`).
      # Tries domain-qualified lookups first, then falls back to a bare label search.
      sig { params(label: String, sudo: T::Boolean).returns(T::Boolean) }
      def self.launchctl_service_running?(label, sudo: false)
        _, success, = launchctl_find_service(label, sudo:)
        success
      end

      # Run a launchctl command, optionally via sudo, capturing its output.
      sig { params(cmd: T::Array[String], sudo: T::Boolean).returns([String, T::Boolean]) }
      def self.launchctl_run(cmd, sudo:)
        if sudo
          result = SystemCommand.run(
            cmd.fetch(0),
            args:         cmd.drop(1),
            sudo:         true,
            sudo_as_root: true,
            print_stderr: false,
          )
          [result.stdout.chomp, result.success?]
        else
          output = Utils.popen_read(*cmd).chomp
          [output, ($CHILD_STATUS.present? && $CHILD_STATUS.success?) || false]
        end
      end
      private_class_method :launchctl_run
    end
  end
end
