# typed: true
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
    attr_accessor :continuation

    def ignore
      continuation.call
    end
  end

  def self.hook_raise
    Object.class_eval do
      alias_method :original_raise, :raise

      def raise(*)
        callcc do |continuation|
          super
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

    return unless block_given?

    yield
    unhook_raise
  end

  def self.unhook_raise
    Object.class_eval do
      alias_method :raise, :original_raise
      alias_method :fail, :original_raise
      undef :original_raise
    end
  end
end
