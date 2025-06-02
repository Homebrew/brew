# typed: strict
# frozen_string_literal: true

require "cache_store"
require "linkage_checker"

module FormulaCellarChecks
  sig { returns(T.nilable(String)) }
  def check_shadowed_headers
    return if ["libtool", "subversion", "berkeley-db"].any? do |formula_name|
      formula.name.start_with?(formula_name)
    end

    return if formula.name.match?(Version.formula_optionally_versioned_regex(:php))
    return if formula.keg_only? || !formula.include.directory?

    files  = relative_glob(formula.include, "**/*.h")
    files &= relative_glob("#{MacOS.sdk_path}/usr/include", "**/*.h")
    files.map! { |p| File.join(formula.include, p) }

    return if files.empty?

    <<~EOS
      Header files that shadow system header files were installed to "#{formula.include}"
      The offending files are:
        #{files * "\n  "}
    EOS
  end

  sig { returns(T.nilable(String)) }
  def check_openssl_links
    return unless formula.prefix.directory?

    keg = Keg.new(formula.prefix)
    system_openssl = keg.mach_o_files.select do |obj|
      dlls = obj.dynamically_linked_libraries
      dlls.any? { |dll| %r{/usr/lib/lib(crypto|ssl|tls)\..*dylib}.match? dll }
    end
    return if system_openssl.empty?

    <<~EOS
      object files were linked against system openssl
      These object files were linked against the deprecated system OpenSSL or
      the system's private LibreSSL.
      Adding `depends_on "openssl"` to the formula may help.
        #{system_openssl * "\n  "}
    EOS
  end

  sig { params(lib: Pathname).returns(T.nilable(String)) }
  def check_python_framework_links(lib)
    python_modules = Pathname.glob lib/"python*/site-packages/**/*.so"
    framework_links = python_modules.select do |obj|
      dlls = obj.dynamically_linked_libraries
      dlls.any? { |dll| dll.include?("Python.framework") }
    end
    return if framework_links.empty?

    <<~EOS
      python modules have explicit framework links
      These python extension modules were linked directly to a Python
      framework binary. They should be linked with -undefined dynamic_lookup
      instead of -lpython or -framework Python.
        #{framework_links * "\n  "}
    EOS
  end

  sig { void }
  def check_linkage
    return unless formula.prefix.directory?

    keg = Keg.new(formula.prefix)

    CacheStoreDatabase.use(:linkage) do |db|
      checker = LinkageChecker.new(keg, formula, cache_db: db)
      next unless checker.broken_library_linkage?

      output = <<~EOS
        #{formula} has broken dynamic library links:
          #{checker.display_test_output}
      EOS

      tab = keg.tab
      if tab.poured_from_bottle
        output += <<~EOS
          Rebuild this from source with:
            brew reinstall --build-from-source #{formula}
          If that's successful, file an issue#{formula.tap ? " here:\n  #{T.must(formula.tap).issues_url}" : "."}
        EOS
      end
      problem_if_output output
    end
  end

  sig { params(formula: Formula).returns(T.nilable(String)) }
  def check_flat_namespace(formula)
    return unless formula.prefix.directory?
    return if formula.tap&.audit_exception(:flat_namespace_allowlist, formula.name)

    keg = ::Keg.new(formula.prefix)
    flat_namespace_files = keg.mach_o_files.reject do |file|
      next true unless file.dylib?

      macho = MachO.open(file)
      if MachO::Utils.fat_magic?(macho.magic)
        macho.machos.map(&:header).all? { |h| h.flag? :MH_TWOLEVEL }
      else
        macho.header.flag? :MH_TWOLEVEL
      end
    end
    return if flat_namespace_files.empty?

    <<~EOS
      Libraries were compiled with a flat namespace.
      This can cause linker errors due to name collisions and
      is often due to a bug in detecting the macOS version.
        #{flat_namespace_files * "\n  "}
    EOS
  end

  sig { void }
  def audit_installed
    generic_audit_installed
    problem_if_output(check_shadowed_headers)
    problem_if_output(check_openssl_links)
    problem_if_output(check_python_framework_links(formula.lib))
    check_linkage
    problem_if_output(check_flat_namespace(formula))
  end

  sig { params(filename: Pathname).returns(T::Boolean) }
  def valid_library_extension?(filename)
    macos_lib_extensions = %w[.dylib .framework]
    generic_valid_library_extension?(filename) || macos_lib_extensions.include?(filename.extname)
  end
end
