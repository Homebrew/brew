# typed: strict
# frozen_string_literal: true

module OS
  module Mac
    module Superenv
      extend T::Helpers

      requires_ancestor { SharedEnvExtension }
      requires_ancestor { ::Superenv }

      module ClassMethods
        sig { returns(::Pathname) }
        def shims_path
          HOMEBREW_SHIMS_PATH/"mac/super"
        end

        sig { returns(T.nilable(::Pathname)) }
        def bin
          return unless ::DevelopmentTools.installed?

          shims_path.realpath
        end
      end

      sig { returns(T::Array[::Pathname]) }
      def homebrew_extra_pkg_config_paths
        %W[
          /usr/lib/pkgconfig
          #{HOMEBREW_LIBRARY}/Homebrew/os/mac/pkgconfig/#{MacOS.version}
        ].map { |p| ::Pathname.new(p) }
      end

      sig { returns(T::Boolean) }
      def libxml2_include_needed?
        return false if deps.any? { |d| d.name == "libxml2" }
        return false if ::Pathname.new("#{self["HOMEBREW_SDKROOT"]}/usr/include/libxml").directory?

        true
      end

      sig { returns(T::Array[::Pathname]) }
      def homebrew_extra_isystem_paths
        paths = []
        paths << "#{self["HOMEBREW_SDKROOT"]}/usr/include/libxml2" if libxml2_include_needed?
        paths << "#{self["HOMEBREW_SDKROOT"]}/usr/include/apache2" if MacOS::Xcode.without_clt?
        paths << "#{self["HOMEBREW_SDKROOT"]}/System/Library/Frameworks/OpenGL.framework/Versions/Current/Headers"
        paths.map { |p| ::Pathname.new(p) }
      end

      sig { returns(T::Array[::Pathname]) }
      def homebrew_extra_library_paths
        paths = []
        if compiler == :llvm_clang
          paths << "#{self["HOMEBREW_SDKROOT"]}/usr/lib"
          paths << ::Formula["llvm"].opt_lib
        end
        paths << "#{self["HOMEBREW_SDKROOT"]}/System/Library/Frameworks/OpenGL.framework/Versions/Current/Libraries"
        paths.map { |p| ::Pathname.new(p) }
      end

      sig { returns(T::Array[::Pathname]) }
      def homebrew_extra_cmake_include_paths
        paths = []
        paths << "#{self["HOMEBREW_SDKROOT"]}/usr/include/libxml2" if libxml2_include_needed?
        paths << "#{self["HOMEBREW_SDKROOT"]}/usr/include/apache2" if MacOS::Xcode.without_clt?
        paths << "#{self["HOMEBREW_SDKROOT"]}/System/Library/Frameworks/OpenGL.framework/Versions/Current/Headers"
        paths.map { |p| ::Pathname.new(p) }
      end

      sig { returns(T::Array[::Pathname]) }
      def homebrew_extra_cmake_library_paths
        %W[
          #{self["HOMEBREW_SDKROOT"]}/System/Library/Frameworks/OpenGL.framework/Versions/Current/Libraries
        ].map { |p| ::Pathname.new(p) }
      end

      sig { returns(T::Array[::Pathname]) }
      def homebrew_extra_cmake_frameworks_paths
        paths = []
        paths << "#{self["HOMEBREW_SDKROOT"]}/System/Library/Frameworks" if MacOS::Xcode.without_clt?
        paths.map { |p| ::Pathname.new(p) }
      end

      sig { returns(String) }
      def determine_cccfg
        s = +""
        # Fix issue with >= Mountain Lion apr-1-config having broken paths
        s << "a"
        s.freeze
      end

      # @private
      sig {
        params(
          formula:         T.nilable(Formula),
          cc:              T.nilable(String),
          build_bottle:    T.nilable(T::Boolean),
          bottle_arch:     T.nilable(String),
          testing_formula: T::Boolean,
          debug_symbols:   T.nilable(T::Boolean),
        ).void
      }
      def setup_build_environment(formula: nil, cc: nil, build_bottle: false, bottle_arch: nil,
                                  testing_formula: false, debug_symbols: false)
        sdk = formula ? MacOS.sdk_for_formula(formula) : MacOS.sdk
        is_xcode_sdk = sdk&.source == :xcode

        Homebrew::Diagnostic.checks(:fatal_setup_build_environment_checks)
        self["HOMEBREW_SDKROOT"] = sdk.path.to_s if sdk

        self["HOMEBREW_DEVELOPER_DIR"] = if is_xcode_sdk
          MacOS::Xcode.prefix.to_s
        else
          MacOS::CLT::PKG_PATH
        end

        # This is a workaround for the missing `m4` in Xcode CLT 15.3, which was
        # reported in FB13679972. Apple has fixed this in Xcode CLT 16.0.
        # See https://github.com/Homebrew/homebrew-core/issues/165388
        if deps.none? { |d| d.name == "m4" } &&
           MacOS.active_developer_dir == MacOS::CLT::PKG_PATH &&
           !File.exist?("#{MacOS::CLT::PKG_PATH}/usr/bin/m4") &&
           (gm4 = ::DevelopmentTools.locate("gm4").to_s).present?
          self["M4"] = gm4
        end

        super

        # On macOS Sonoma (at least release candidate), iconv() is generally
        # present and working, but has a minor regression that defeats the
        # test implemented in gettext's configure script (and used by many
        # gettext dependents).
        ENV["am_cv_func_iconv_works"] = "yes" if MacOS.version == "14"

        # The tools in /usr/bin proxy to the active developer directory.
        # This means we can use them for any combination of CLT and Xcode.
        self["HOMEBREW_PREFER_CLT_PROXIES"] = "1"

        # Deterministic timestamping.
        self["ZERO_AR_DATE"] = "1"

        # Pass `-no_fixup_chains` whenever the linker is invoked with `-undefined dynamic_lookup`.
        # See: https://github.com/python/cpython/issues/97524
        #      https://github.com/pybind/pybind11/pull/4301
        no_fixup_chains

        # Strip build prefixes from linker where supported, for deterministic builds.
        append_to_cccfg "o"

        # Pass `-ld_classic` whenever the linker is invoked with `-dead_strip_dylibs`
        # on `ld` versions that don't properly handle that option.
        return unless ::DevelopmentTools.ld64_version.between?("1015.7", "1022.1")

        append_to_cccfg "c"
      end

      sig { void }
      def no_weak_imports
        append_to_cccfg "w" if no_weak_imports_support?
      end

      sig { void }
      def no_fixup_chains
        append_to_cccfg "f" if no_fixup_chains_support?
      end
    end
  end
end

Superenv.singleton_class.prepend(OS::Mac::Superenv::ClassMethods)
Superenv.prepend(OS::Mac::Superenv)
