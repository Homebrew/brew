# typed: strict
# frozen_string_literal: true

require "cask/artifact/binary"

module Cask
  module Artifact
    # Artifact corresponding to the `command_wrapper` stanza.
    class CommandWrapper < Binary
      sig { override.returns(Symbol) }
      def self.dirmethod = :binarydir

      sig {
        override.params(
          cask:    Cask,
          source:  T.any(String, Pathname),
          options: T.untyped,
        ).returns(T.attached_class)
      }
      def self.from_args(cask, source, options = nil)
        options ||= {}
        options.assert_valid_keys(:target, :content)
        new(cask, source, **options)
      end

      sig {
        params(
          cask:    Cask,
          source:  T.any(String, Pathname),
          target:  T.any(String, Pathname),
          content: String,
        ).void
      }
      def initialize(cask, source, target:, content:)
        raise CaskInvalidError.new(cask, "'command_wrapper' requires content") if content.blank?

        super(cask, source, target:)
        @content = content
      end

      sig {
        override.params(
          force:   T::Boolean,
          adopt:   T::Boolean,
          command: T.class_of(SystemCommand),
          options: T.anything,
        ).void
      }
      def install_phase(force: false, adopt: false, command: SystemCommand, **options)
        source.dirname.mkpath
        source.write(@content)
        super
      end

      sig { override.returns(T::Array[T.anything]) }
      def to_args
        [@source_string, { target: @target_string, content: @content }]
      end
    end
  end
end
