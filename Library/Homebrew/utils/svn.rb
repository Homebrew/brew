# typed: true
# frozen_string_literal: true

require "system_command"

module Utils
  # Helper functions for querying SVN information.
  #
  # @api private
  module Svn
    class << self
      include SystemCommand::Mixin

      sig { returns(T::Boolean) }
      def available?
        version.present?
      end

      sig { returns(T.nilable(String)) }
      def version
        return @version if defined?(@version)

        stdout, _, status = system_command(HOMEBREW_SHIMS_PATH/"shared/svn", args: ["--version"], print_stderr: false)
        @version = status.success? ? stdout.chomp[/svn, version (\d+(?:\.\d+)*)/, 1] : nil
      end

      sig { params(url: String).returns(T::Boolean) }
      def remote_exists?(url)
        return true unless available?

        args = ["ls", url, "--depth", "empty"]
        _, stderr, status = system_command("svn", args: args, print_stderr: false)
        return status.success? unless stderr.include?("certificate verification failed")

        # OK to unconditionally trust here because we're just checking if a URL exists.
        system_command("svn", args: args.concat(invalid_cert_flags), print_stderr: false).success?
      end

      sig { returns(Array) }
      def invalid_cert_flags
        opoo "Ignoring Subversion certificate errors!"
        args = ["--non-interactive", "--trust-server-cert"]
        if Version.new(version || "-1") >= Version.new("1.9")
          args << "--trust-server-cert-failures=expired,not-yet-valid"
        end
        args
      end

      def clear_version_cache
        remove_instance_variable(:@version) if defined?(@version)
      end
    end
  end
end
