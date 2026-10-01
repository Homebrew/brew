# typed: strict
# frozen_string_literal: true

module Homebrew
  module Services
    module System
      module Systemctl
        sig { returns(T.nilable(Pathname)) }
        def self.executable
          @executable ||= T.let(which("systemctl"), T.nilable(Pathname))
        end

        class << self
          sig { params(executable: T.nilable(Pathname)).returns(T.nilable(Pathname)) }
          attr_writer :executable
        end

        sig { returns(String) }
        def self.scope
          System.root? ? "--system" : "--user"
        end

        sig { params(args: T.any(String, Pathname)).void }
        def self.run(*args)
          _run(*args, mode: :default)
        end

        sig { params(args: T.any(String, Pathname)).returns(T::Boolean) }
        def self.quiet_run(*args)
          _run(*args, mode: :quiet)
        end

        sig { params(args: T.any(String, Pathname)).returns(String) }
        def self.popen_read(*args)
          _run(*args, mode: :read)
        end

        sig { params(args: T.any(String, Pathname), mode: Symbol).returns(T.nilable(T.any(String, T::Boolean))) }
        private_class_method def self._run(*args, mode:)
          require "system_command"
          systemctl = executable
          raise "Could not find `systemctl` in PATH" if systemctl.nil?

          result = SystemCommand.run(systemctl,
                                     args:         [scope, *args.map(&:to_s)],
                                     print_stdout: mode == :default,
                                     print_stderr: mode == :default,
                                     must_succeed: mode == :default)
          if mode == :read
            result.stdout
          elsif mode == :quiet
            result.success?
          end
        end
      end
    end
  end
end
