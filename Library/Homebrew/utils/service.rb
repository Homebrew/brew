# typed: strict
# frozen_string_literal: true

module Utils
  # Helpers for `brew services` related code.
  module Service
    # Check if a service is running for a specified formula.
    sig { params(formula: Formula).returns(T::Boolean) }
    def self.running?(formula)
      if launchctl?
        quiet_system(launchctl, "list", formula.plist_name)
      elsif systemctl?
        quiet_system(systemctl, "is-active", "--quiet", formula.service_name)
      end
    end

    # Check if a service file is installed in the expected location.
    sig { params(formula: Formula).returns(T::Boolean) }
    def self.installed?(formula)
      (launchctl? && formula.launchd_service_path.exist?) ||
        (systemctl? && formula.systemd_service_path.exist?)
    end

    # Path to launchctl binary.
    sig { returns(T.nilable(Pathname)) }
    def self.launchctl
      return @launchctl if defined? @launchctl
      return if ENV["HOMEBREW_TEST_GENERIC_OS"]

      @launchctl = T.let(which("launchctl"), T.nilable(Pathname))
    end

    # Path to systemctl binary.
    sig { returns(T.nilable(Pathname)) }
    def self.systemctl
      return @systemctl if defined? @systemctl
      return if ENV["HOMEBREW_TEST_GENERIC_OS"]

      @systemctl = T.let(which("systemctl"), T.nilable(Pathname))
    end

    sig { returns(T::Boolean) }
    def self.launchctl?
      !launchctl.nil?
    end

    sig { returns(T::Boolean) }
    def self.systemctl?
      !systemctl.nil?
    end
  end
end
