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

    # Quote a string for use in systemd command lines, e.g., in `ExecStart`.
    # https://www.freedesktop.org/software/systemd/man/latest/systemd.syntax.html#Quoting
    sig { params(str: String).returns(String) }
    def self.systemd_quote(str)
      result = +"\""
      # No need to escape single quotes and spaces, as we're always double
      # quoting the entire string.
      str.each_char do |char|
        result << case char
        when "\a" then "\\a"
        when "\b" then "\\b"
        when "\f" then "\\f"
        when "\n" then "\\n"
        when "\r" then "\\r"
        when "\t" then "\\t"
        when "\v" then "\\v"
        when "\\" then "\\\\"
        when "\"" then "\\\""
        else char
        end
      end
      result << "\""
      result.freeze
    end
  end
end
