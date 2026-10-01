# typed: strict
# frozen_string_literal: true

module OS
  module Linux
    # Helper functions for working with ELF objects.
    #
    # @api private
    module Elf
      sig { params(str: String, ref: String, repl: T.any(String, ::Pathname)).returns(String) }
      def self.expand_elf_dst(str, ref, repl)
        # ELF gABI rules for DSTs:
        #   - Longest possible sequence using the rules (greedy).
        #   - Must start with a $ (enforced by caller).
        #   - Must follow $ with one underscore or ASCII [A-Za-z] (caller
        #     follows these rules for REF) or '{' (start curly quoted name).
        #   - Must follow first two characters with zero or more [A-Za-z0-9_]
        #     (enforced by caller) or '}' (end curly quoted name).
        # (from https://github.com/bminor/glibc/blob/41903cb6f460d62ba6dd2f4883116e2a624ee6f8/elf/dl-load.c#L182-L228)

        # In addition to capturing a token, also attempt to capture opening/closing braces and check that they are not
        # mismatched before expanding.
        str.gsub(/\$({?)([a-zA-Z_][a-zA-Z0-9_]*)(}?)/) do |orig_str|
          has_opening_brace = ::Regexp.last_match(1).present?
          matched_text = ::Regexp.last_match(2)
          has_closing_brace = ::Regexp.last_match(3).present?
          if (matched_text == ref) && (has_opening_brace == has_closing_brace)
            repl
          else
            orig_str
          end
        end
      end
    end
  end
end
