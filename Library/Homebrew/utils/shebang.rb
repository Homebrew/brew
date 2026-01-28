# typed: strict
# frozen_string_literal: true

module Utils
  # Helper functions for manipulating shebang lines.
  module Shebang
    extend T::Helpers

    requires_ancestor { Kernel }

    module_function

    # Specification on how to rewrite a given shebang.
    class RewriteInfo
      sig { returns(Regexp) }
      attr_reader :regex

      sig { returns(Integer) }
      attr_reader :max_length

      sig { returns(T.any(String, Pathname)) }
      attr_reader :replacement

      sig { params(regex: Regexp, max_length: Integer, replacement: T.any(String, Pathname)).void }
      def initialize(regex, max_length, replacement)
        @regex = regex
        @max_length = max_length
        @replacement = replacement
      end
    end

    # Rewrite shebang for the given `paths` using the given `rewrite_info`.
    #
    # ### Example
    #
    # ```ruby
    # rewrite_shebang detected_python_shebang, bin/"script.py"
    # ```
    #
    # @api public
    sig { params(rewrite_info: RewriteInfo, paths: T.any(String, Pathname)).void }
    def rewrite_shebang(rewrite_info, *paths)
      paths.each do |f|
        f = Pathname(f)
        next unless f.file?
        next unless rewrite_info.regex.match?(f.read(rewrite_info.max_length))

        Utils::Inreplace.inreplace f.to_s, rewrite_info.regex, "#!#{rewrite_info.replacement}"
      end
    end
  end
end
