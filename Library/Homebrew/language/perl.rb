# typed: true
# frozen_string_literal: true

module Language
  # Helper functions for Perl formulae.
  #
  # @api public
  module Perl
    # Helper module for replacing `perl` shebangs.
    module Shebang
      module_function

      # A regex to match potential shebang permutations.
      PERL_SHEBANG_REGEX = %r{^#! ?/usr/bin/(?:env )?perl( |$)}.freeze

      # The length of the longest shebang matching `SHEBANG_REGEX`.
      PERL_SHEBANG_MAX_LENGTH = "#! /usr/bin/env perl ".length

      # @private
      sig { params(perl_path: T.any(String, Pathname)).returns(Utils::Shebang::RewriteInfo) }
      def perl_shebang_rewrite_info(perl_path)
        Utils::Shebang::RewriteInfo.new(
          PERL_SHEBANG_REGEX,
          PERL_SHEBANG_MAX_LENGTH,
          "#{perl_path}\\1",
        )
      end

      sig { params(formula: T.untyped).returns(Utils::Shebang::RewriteInfo) }
      def detected_perl_shebang(formula = self)
        perl_deps = formula.declared_deps.select { |dep| dep.name == "perl" }
        raise ShebangDetectionError.new("Perl", "formula does not depend on Perl") if perl_deps.empty?

        perl_path = if perl_deps.any? { |dep| !dep.uses_from_macos? || !dep.use_macos_install? }
          Formula["perl"].opt_bin/"perl"
        else
          "/usr/bin/perl#{MacOS.preferred_perl_version}"
        end

        perl_shebang_rewrite_info(perl_path)
      end
    end
  end
end
