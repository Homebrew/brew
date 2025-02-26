# typed: true
# frozen_string_literal: true

module Service
  module System
    module Systemctl
      def self.executable
        @executable ||= which("systemctl")
      end

      def self.scope
        System.root? ? "--system" : "--user"
      end

      def self.run(*args)
        _run(*args, mode: :default)
      end

      def self.quiet_run(*args)
        _run(*args, mode: :quiet)
      end

      def self.popen_read(*args)
        _run(*args, mode: :read)
      end

      private_class_method def self._run(*args, mode:)
        require "system_command"
        result = SystemCommand.run(executable,
                                   args:         [scope, *args.map(&:to_s)],
                                   print_stdout: mode == :default,
                                   print_stderr: mode == :default,
                                   must_succeed: mode == :default,
                                   reset_uid:    true)
        if mode == :read
          result.stdout
        elsif mode == :quiet
          result.success?
        end
      end
    end
  end
end
