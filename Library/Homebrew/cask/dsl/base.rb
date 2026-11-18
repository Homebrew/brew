# typed: strict
# frozen_string_literal: true

require "utils/path"

module Cask
  class DSL
    # Superclass for all stanzas which take a block.
    class Base
      extend Forwardable
      include ::Utils::Path

      sig { returns(Cask) }
      attr_reader :cask

      sig { returns(T.class_of(SystemCommand)) }
      attr_reader :command

      sig { params(cask: Cask, command: T.class_of(SystemCommand)).void }
      def initialize(cask, command = SystemCommand)
        @cask = cask
        @command = command
      end

      def_delegators :@cask, :token, :version, :caskroom_path, :staged_path, :appdir, :language, :arch

      sig {
        params(
          executable:   String,
          args:         T::Array[T.any(String, Integer, Float, Pathname)],
          sudo:         T.nilable(T::Boolean),
          sudo_as_root: T::Boolean,
          env:          T::Hash[String, T.nilable(T.any(String, T::Boolean, PATH))],
          input:        T.any(String, T::Array[String]),
          must_succeed: T::Boolean,
          print_stdout: T.any(T::Boolean, Symbol),
          print_stderr: T.any(T::Boolean, Symbol),
          debug:        T.nilable(T::Boolean),
          verbose:      T.nilable(T::Boolean),
          secrets:      T.any(String, T::Array[String]),
          chdir:        T.nilable(T.any(String, Pathname)),
          timeout:      T.nilable(T.any(Integer, Float)),
        ).returns(T.nilable(SystemCommand::Result))
      }
      def system_command(executable, args: [], sudo: false, sudo_as_root: false, env: {}, input: [],
                         must_succeed: true, print_stdout: false, print_stderr: true, debug: nil, verbose: nil,
                         secrets: [], chdir: nil, timeout: nil)
        @command.run!(executable, args:, sudo:, sudo_as_root:, env:, input:, must_succeed:, print_stdout:,
                      print_stderr:, debug:, verbose:, secrets:, chdir:, timeout:)
      end

      sig { params(method: Symbol, _args: T.untyped).returns(T.noreturn) }
      def method_missing(method, *_args)
        raise NoMethodError, "undefined method '#{method}' for Cask '#{@cask}'"
      end

      sig { params(_method: Symbol, _include_private: T::Boolean).returns(T::Boolean) }
      def respond_to_missing?(_method, _include_private = false)
        false
      end
    end
  end
end
