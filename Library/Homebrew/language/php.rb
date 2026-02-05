# typed: strict
# frozen_string_literal: true

module Language
  # Helper functions for PHP formulae.
  #
  # @api public
  module PHP
    # Helper module for replacing `php` shebangs.
    module Shebang
      extend T::Helpers

      requires_ancestor { Formula }

      module_function

      # A regex to match potential shebang permutations.
      PHP_SHEBANG_REGEX = %r{\A#! ?(?:/usr/bin/(?:env )?)?php( |$)}

      # The length of the longest shebang matching `SHEBANG_REGEX`.
      PHP_SHEBANG_MAX_LENGTH = T.let("#! /usr/bin/env php ".length, Integer)

      # @private
      sig { params(php_path: T.any(String, Pathname)).returns(Utils::Shebang::RewriteInfo) }
      def php_shebang_rewrite_info(php_path)
        Utils::Shebang::RewriteInfo.new(
          PHP_SHEBANG_REGEX,
          PHP_SHEBANG_MAX_LENGTH,
          "#{php_path}\\1",
        )
      end

      sig { params(formula: Formula).returns(Utils::Shebang::RewriteInfo) }
      def detected_php_shebang(formula = T.cast(self, Formula))
        php_deps = formula.deps.select(&:required?).map(&:name).grep(/^php(@.+)?$/)
        raise ShebangDetectionError.new("PHP", "formula does not depend on PHP") if php_deps.empty?
        raise ShebangDetectionError.new("PHP", "formula has multiple PHP dependencies") if php_deps.length > 1

        php_shebang_rewrite_info(Formula[php_deps.first].opt_bin/"php")
      end
    end
  end
end
