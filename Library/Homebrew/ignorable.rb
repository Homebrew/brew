# typed: strict
# frozen_string_literal: true

require "warnings"
Warnings.ignore(/warning: callcc is obsolete; use Fiber instead/) do
  require "continuation"
end

# Provides the ability to optionally ignore errors raised and continue execution.
module Ignorable
  # Marks exceptions which can be ignored and provides
  # the ability to jump back to where it was raised.
  module ExceptionMixin
    sig { returns(T.untyped) }
    attr_accessor :continuation

    sig { void }
    def ignore
      continuation.call
    end
  end

  sig { params(blk: T.nilable(T.proc.void)).void }
  def self.hook_raise(&blk)
    # TODO: migrate away from this inline class here, they don't play nicely with
    #       Sorbet, when we migrate to `typed: strict`
    # rubocop:todo Sorbet/BlockMethodDefinition
    Object.class_eval do
      alias_method :original_raise, :raise

      sig { params(args: T.anything).void }
      def raise(*args)
        callcc do |continuation|
          super
        # Handle all possible exceptions.
        rescue Exception => e # rubocop:disable Lint/RescueException
          unless e.is_a?(ScriptError)
            e.extend(ExceptionMixin)
            T.cast(e, ExceptionMixin).continuation = continuation
          end
          super(e)
        end
      end

      alias_method :fail, :raise
    end
    # rubocop:enable Sorbet/BlockMethodDefinition

    return unless block_given?

    yield
    unhook_raise
  end

  sig { void }
  def self.unhook_raise
    Object.class_eval do
      alias_method :raise, :original_raise
      alias_method :fail, :original_raise
      undef_method :original_raise
    end
  end
end
