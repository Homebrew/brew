# frozen_string_literal: true
# typed: true

module T::Private
  module Compiler
    # If this code ever runs, the caller is running interpreted (or the
    # compiler didn't see the call to `running_compiled?` statically.)
    #
    # The Sorbet Compiler replaces calls to this method unconditionally (no
    # runtime guards) to return `true` when compiling a file.
    def self.running_compiled?
      false
    end

    # Returns `nil` because the compiler isn't running.
    #
    # The Sorbet Compiler replaces calls to this method unconditionally (no
    # runtime guards) to return a String showing the Sorbet Compiler's version
    # string.
    def self.compiler_version
      nil
    end
  end
end
