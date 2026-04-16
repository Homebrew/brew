# typed: strict
# frozen_string_literal: true

module Cask
  class DSL
    # Superclass for all stanzas which take a block.
    class Base
      extend Forwardable

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

      sig { params(executable: String, options: T.untyped).returns(T.nilable(SystemCommand::Result)) }
      def system_command(executable, **options)
        @command.run!(executable, **options)
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
