# typed: strict
# frozen_string_literal: true

require "autobump_constants"

module Autobump
  # Common implementation of the formula and cask autobump exclusion stanza.
  module DSL
    extend T::Helpers

    requires_ancestor { Kernel }

    # The reason for a DSL exclusion, if any.
    sig { returns(T.nilable(T.any(String, Symbol))) }
    attr_reader :no_autobump_message

    sig { returns(T::Boolean) }
    def autobump? = no_autobump_message.nil?

    private

    sig { params(because: T.any(String, Symbol), from_metadata: T::Boolean).void }
    def set_no_autobump(because:, from_metadata: false)
      if because.is_a?(Symbol) && !NO_AUTOBUMP_REASONS_LIST.key?(because) && !from_metadata
        raise ArgumentError, "'because' argument should use valid symbol or a string!"
      end

      @no_autobump_message = T.let(because, T.nilable(T.any(String, Symbol)))
    end
  end
end
