# typed: strict
# frozen_string_literal: true

module OS
  module Mac
    module SharedEnvExtension
      extend T::Helpers

      requires_ancestor { ::SharedEnvExtension }

      sig {
        params(
          formula:         T.nilable(::Formula),
          cc:              T.nilable(String),
          build_bottle:    T.nilable(T::Boolean),
          bottle_arch:     T.nilable(String),
          testing_formula: T::Boolean,
          debug_symbols:   T.nilable(T::Boolean),
        ).void
      }
      def setup_build_environment(formula: nil, cc: nil, build_bottle: false, bottle_arch: nil,
                                  testing_formula: false, debug_symbols: false)
        super

        # Normalise the system Perl version used, where multiple may be available
        self["VERSIONER_PERL_VERSION"] = MacOS.preferred_perl_version
      end

      sig { returns(T::Boolean) }
      def no_weak_imports_support?
        compiler == :clang
      end

      sig { returns(T::Boolean) }
      def no_fixup_chains_support?
        # This is supported starting Xcode 13, which ships ld64-711.
        # https://developer.apple.com/documentation/xcode-release-notes/xcode-13-release-notes
        # https://en.wikipedia.org/wiki/Xcode#Xcode_11.0_-_14.x_(since_SwiftUI_framework)_2
        ::DevelopmentTools.ld64_version >= 711
      end
    end
  end
end

SharedEnvExtension.prepend(OS::Mac::SharedEnvExtension)
