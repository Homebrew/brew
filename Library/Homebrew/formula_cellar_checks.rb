# typed: strict
# frozen_string_literal: true

require "utils/shell"

# Checks to perform on a formula's cellar.
module FormulaCellarChecks
  extend T::Helpers

  abstract!
  requires_ancestor { Kernel }

  sig { abstract.returns(Formula) }
  def formula; end

  sig { abstract.params(output: T.nilable(String)).void }
  def problem_if_output(output); end

  sig { params(bin: Pathname).returns(T.nilable(String)) }
  def check_env_path(bin)
    return if Homebrew::EnvConfig.no_env_hints?

    # warn the user if stuff was installed outside of their PATH
    return unless bin.directory?
    return if bin.children.empty?

    prefix_bin = (HOMEBREW_PREFIX/bin.basename)
    return unless prefix_bin.directory?

    prefix_bin = prefix_bin.realpath
    return if ORIGINAL_PATHS.include? prefix_bin

    <<~EOS
      "#{prefix_bin}" is not in your PATH.
      You can amend this by altering your #{Utils::Shell.profile} file.
    EOS
  end

  sig { returns(T.nilable(String)) }
  def check_manpages
    # Check for man pages that aren't in share/man
    return unless (formula.prefix/"man").directory?

    <<~EOS
      A top-level "man" directory was found.
      Homebrew requires that man pages live under "share".
      This can often be fixed by passing `--mandir=\#{man}` to `configure`.
    EOS
  end

  sig { returns(T.nilable(String)) }
  def check_infopages
    # Check for info pages that aren't in share/info
    return unless (formula.prefix/"info").directory?

    <<~EOS
      A top-level "info" directory was found.
      Homebrew suggests that info pages live under "share".
      This can often be fixed by passing `--infodir=\#{info}` to `configure`.
    EOS
  end

  sig { returns(T.nilable(String)) }
  def check_jars
    return unless formula.lib.directory?

    jars = formula.lib.children.select { |g| g.extname == ".jar" }
    return if jars.empty?

    <<~EOS
      JARs were installed to "#{formula.lib}".
      Installing JARs to "lib" can cause conflicts between packages.
      For Java software, it is typically better for the formula to
      install to "libexec" and then symlink or wrap binaries into "bin".
      See formulae 'activemq', 'jruby', etc. for examples.
      The offending files are:
        #{jars * "\n  "}
    EOS
  end

  VALID_LIBRARY_EXTENSIONS = %w[.a .jnilib .la .o .so .jar .prl .pm .sh].freeze

  sig { params(filename: Pathname).returns(T::Boolean) }
  def valid_library_extension?(filename)
    VALID_LIBRARY_EXTENSIONS.include? filename.extname
  end
  alias generic_valid_library_extension? valid_library_extension?

  sig { returns(T.nilable(String)) }
  def check_non_libraries
    return unless formula.lib.directory?

    non_libraries = formula.lib.children.reject do |g|
      next true if g.directory?

      valid_library_extension? g
    end
    return if non_libraries.empty?

    <<~EOS
      Non-libraries were installed to "#{formula.lib}".
      Installing non-libraries to "lib" is discouraged.
      The offending files are:
        #{non_libraries * "\n  "}
    EOS
  end

  sig { params(bin: Pathname).returns(T.nilable(String)) }
  def check_non_executables(bin)
    return unless bin.directory?

    non_exes = bin.children.select { |g| g.directory? || !g.executable? }
    return if non_exes.empty?

    <<~EOS
      Non-executables were installed to "#{bin}".
      The offending files are:
        #{non_exes * "\n  "}
    EOS
  end

  sig { params(bin: Pathname).returns(T.nilable(String)) }
  def check_generic_executables(bin)
    return unless bin.directory?

    generic_names = %w[service start stop]
    generics = bin.children.select { |g| generic_names.include? g.basename.to_s }
    return if generics.empty?

    <<~EOS
      Generic binaries were installed to "#{bin}".
      Binaries with generic names are likely to conflict with other software.
      Homebrew suggests that this software is installed to "libexec" and then
      symlinked as needed.
      The offending files are:
        #{generics * "\n  "}
    EOS
  end

  sig { params(lib: Pathname).returns(T.nilable(String)) }
  def check_easy_install_pth(lib)
    pth_found = Dir["#{lib}/python3*/site-packages/easy-install.pth"].map { |f| File.dirname(f) }
    return if pth_found.empty?

    <<~EOS
      'easy-install.pth' files were found.
      These '.pth' files are likely to cause link conflicts.
      Easy install is now deprecated, do not use it.
      The offending files are:
        #{pth_found * "\n  "}
    EOS
  end

  sig { params(share: Pathname, name: String).returns(T.nilable(String)) }
  def check_elisp_dirname(share, name)
    return unless (share/"emacs/site-lisp").directory?
    # Emacs itself can do what it wants
    return if name == "emacs"

    bad_dir_name = (share/"emacs/site-lisp").children.any? do |child|
      child.directory? && child.basename.to_s != name
    end

    return unless bad_dir_name

    <<~EOS
      Emacs Lisp files were installed into the wrong "site-lisp" subdirectory.
      They should be installed into:
        #{share}/emacs/site-lisp/#{name}
    EOS
  end

  sig { params(share: Pathname, name: String).returns(T.nilable(String)) }
  def check_elisp_root(share, name)
    return unless (share/"emacs/site-lisp").directory?
    # Emacs itself can do what it wants
    return if name == "emacs"

    elisps = (share/"emacs/site-lisp").children.select do |file|
      Keg::ELISP_EXTENSIONS.include? file.extname
    end
    return if elisps.empty?

    <<~EOS
      Emacs Lisp files were linked directly to "#{HOMEBREW_PREFIX}/share/emacs/site-lisp".
      This may cause conflicts with other packages.
      They should instead be installed into:
        #{share}/emacs/site-lisp/#{name}
      The offending files are:
        #{elisps * "\n  "}
    EOS
  end

  sig { params(lib: Pathname, deps: Dependencies).returns(T.nilable(String)) }
  def check_python_packages(lib, deps)
    return unless lib.directory?

    lib_subdirs = lib.children
                     .select(&:directory?)
                     .map(&:basename)

    pythons = lib_subdirs.filter_map do |p|
      match = p.to_s.match(/^python(\d+\.\d+)$/)
      next if match.blank?
      next if match.captures.blank?

      match.captures.first
    end

    return if pythons.blank?

    python_deps = deps.to_a
                      .map(&:name)
                      .grep(/^python(@.*)?$/)
                      .filter_map { |d| Formula[d].version.to_s[/^\d+\.\d+/] }

    return if python_deps.blank?
    return if pythons.any? { |v| python_deps.include? v }

    pythons = pythons.map { |v| "Python #{v}" }
    python_deps = python_deps.map { |v| "Python #{v}" }

    <<~EOS
      Packages have been installed for:
        #{pythons * "\n  "}
      but this formula depends on:
        #{python_deps * "\n  "}
    EOS
  end

  sig { params(prefix: Pathname).returns(T.nilable(String)) }
  def check_shim_references(prefix)
    return unless prefix.directory?

    keg = Keg.new(prefix)

    matches = []
    keg.each_unique_file_matching(HOMEBREW_SHIMS_PATH) do |f|
      match = f.relative_path_from(keg.to_path)

      next if match.to_s.match? %r{^share/doc/.+?/INFO_BIN$}

      matches << match
    end

    return if matches.empty?

    <<~EOS
      Files were found with references to the Homebrew shims directory.
      The offending files are:
        #{matches * "\n  "}
    EOS
  end

  sig { params(prefix: Pathname, plist: Pathname).returns(T.nilable(String)) }
  def check_plist(prefix, plist)
    return unless prefix.directory?

    plist = begin
      Plist.parse_xml(plist, marshal: false)
    rescue
      nil
    end
    return if plist.blank?

    program_location = plist["ProgramArguments"]&.first
    key = "first ProgramArguments value"
    if program_location.blank?
      program_location = plist["Program"]
      key = "Program"
    end
    return if program_location.blank?

    Dir.chdir("/") do
      unless File.exist?(program_location)
        return <<~EOS
          The plist "#{key}" does not exist:
            #{program_location}
        EOS
      end

      return if File.executable?(program_location)
    end

    <<~EOS
      The plist "#{key}" is not executable:
        #{program_location}
    EOS
  end

  sig { params(name: String, keg_only: T::Boolean).returns(T.nilable(String)) }
  def check_python_symlinks(name, keg_only)
    return unless keg_only
    return unless name.start_with? "python"

    return if %w[pip3 wheel3].none? do |l|
      link = HOMEBREW_PREFIX/"bin"/l
      link.exist? && File.realpath(link).start_with?(HOMEBREW_CELLAR/name)
    end

    "Python formulae that are keg-only should not create `pip3` and `wheel3` symlinks."
  end

  sig { params(formula: Formula).returns(T.nilable(String)) }
  def check_service_command(formula)
    return unless formula.prefix.directory?
    return unless formula.service?
    return unless formula.service.command?

    "Service command does not exist" unless File.exist?(T.must(formula.service.command).first)
  end

  sig { params(formula: Formula).returns(T.nilable(String)) }
  def check_cpuid_instruction(formula)
    # Checking for `cpuid` only makes sense on Intel:
    # https://en.wikipedia.org/wiki/CPUID
    return unless Hardware::CPU.intel?

    dot_brew_formula = formula.prefix/".brew/#{formula.name}.rb"
    return unless dot_brew_formula.exist?

    return unless dot_brew_formula.read.include? "ENV.runtime_cpu_detection"

    # macOS `objdump` is a bit slow, so we prioritise llvm's `llvm-objdump` (~5.7x faster)
    # or binutils' `objdump` (~1.8x faster) if they are installed.
    objdump   = Formula["llvm"].opt_bin/"llvm-objdump" if Formula["llvm"].any_version_installed?
    objdump ||= Formula["binutils"].opt_bin/"objdump" if Formula["binutils"].any_version_installed?
    objdump ||= which("objdump")
    objdump ||= which("objdump", ORIGINAL_PATHS)

    unless objdump
      return <<~EOS
        No `objdump` found, so cannot check for a `cpuid` instruction. Install `objdump` with
          brew install binutils
      EOS
    end

    keg = Keg.new(formula.prefix)
    return if keg.binary_executable_or_library_files.any? do |file|
      cpuid_instruction?(file, objdump)
    end

    hardlinks = Set.new
    return if formula.lib.directory? && formula.lib.find.any? do |pn|
      next false if pn.symlink? || pn.directory? || pn.extname != ".a"
      next false unless hardlinks.add? [pn.stat.dev, pn.stat.ino]

      cpuid_instruction?(pn, objdump)
    end

    "No `cpuid` instruction detected. #{formula} should not use `ENV.runtime_cpu_detection`."
  end

  sig { params(formula: Formula).returns(T.nilable(String)) }
  def check_binary_arches(formula)
    return unless formula.prefix.directory?

    keg = Keg.new(formula.prefix)
    mismatches = {}
    keg.binary_executable_or_library_files.each do |file|
      farch = file.arch
      mismatches[file] = farch if farch != Hardware::CPU.arch
    end
    return if mismatches.empty?

    compatible_universal_binaries, mismatches = mismatches.partition do |file, arch|
      arch == :universal && file.archs.include?(Hardware::CPU.arch)
    end
    # To prevent transformation into nested arrays
    compatible_universal_binaries = compatible_universal_binaries.to_h
    mismatches = mismatches.to_h

    universal_binaries_expected = if (formula_tap = formula.tap).present? && formula_tap.core_tap?
      formula_tap.audit_exception(:universal_binary_allowlist, formula.name)
    else
      true
    end

    mismatches_expected = (formula_tap = formula.tap).blank? ||
                          formula_tap.audit_exception(:mismatched_binary_allowlist, formula.name)
    mismatches_expected = [mismatches_expected] if mismatches_expected.is_a?(String)
    if mismatches_expected.is_a?(Array)
      glob_flags = File::FNM_DOTMATCH | File::FNM_EXTGLOB | File::FNM_PATHNAME
      mismatches.delete_if do |file, _arch|
        mismatches_expected.any? { |pattern| file.fnmatch?("#{formula.prefix.realpath}/#{pattern}", glob_flags) }
      end
      mismatches_expected = false
      return if mismatches.empty? && compatible_universal_binaries.empty?
    end

    return if mismatches.empty? && universal_binaries_expected
    return if compatible_universal_binaries.empty? && mismatches_expected
    return if universal_binaries_expected && mismatches_expected

    s = ""

    if mismatches.present? && !mismatches_expected
      s += <<~EOS
        Binaries built for a non-native architecture were installed into #{formula}'s prefix.
        The offending files are:
          #{mismatches.map { |m| "#{m.first}\t(#{m.last})" } * "\n  "}
      EOS
    end

    if compatible_universal_binaries.present? && !universal_binaries_expected
      s += <<~EOS
        Unexpected universal binaries were found.
        The offending files are:
          #{compatible_universal_binaries.keys * "\n  "}
      EOS
    end

    s
  end

  sig { void }
  def audit_installed
    @new_formula ||= T.let(false, T.nilable(T::Boolean))

    problem_if_output(check_manpages)
    problem_if_output(check_infopages)
    problem_if_output(check_jars)
    problem_if_output(check_service_command(formula))
    problem_if_output(check_non_libraries) if @new_formula
    problem_if_output(check_non_executables(formula.bin))
    problem_if_output(check_generic_executables(formula.bin))
    problem_if_output(check_non_executables(formula.sbin))
    problem_if_output(check_generic_executables(formula.sbin))
    problem_if_output(check_easy_install_pth(formula.lib))
    problem_if_output(check_elisp_dirname(formula.share, formula.name))
    problem_if_output(check_elisp_root(formula.share, formula.name))
    problem_if_output(check_python_packages(formula.lib, formula.deps))
    problem_if_output(check_shim_references(formula.prefix))
    problem_if_output(check_plist(formula.prefix, formula.launchd_service_path))
    problem_if_output(check_python_symlinks(formula.name, formula.keg_only?))
    problem_if_output(check_cpuid_instruction(formula))
    problem_if_output(check_binary_arches(formula))
  end
  alias generic_audit_installed audit_installed

  private

  sig { params(dir: T.any(Pathname, String), pattern: String).returns(T::Array[String]) }
  def relative_glob(dir, pattern)
    File.directory?(dir) ? Dir.chdir(dir) { Dir[pattern] } : []
  end

  sig { params(file: T.any(Pathname, String), objdump: Pathname).returns(T::Boolean) }
  def cpuid_instruction?(file, objdump)
    @instruction_column_index ||= T.let({}, T.nilable(T::Hash[Pathname, Integer]))
    @instruction_column_index[objdump] ||= begin
      objdump_version = Utils.popen_read(objdump, "--version")

      if (objdump_version.match?(/^Apple LLVM/) && MacOS.version <= :mojave) ||
         objdump_version.exclude?("LLVM")
        2 # Mojave `objdump` or GNU Binutils `objdump`
      else
        1 # `llvm-objdump` or Catalina+ `objdump`
      end
    end

    has_cpuid_instruction = T.let(false, T::Boolean)
    Utils.popen_read(objdump, "--disassemble", file) do |io|
      until io.eof?
        instruction = io.readline.split("\t")[@instruction_column_index[objdump]]&.strip
        has_cpuid_instruction = instruction == "cpuid" if instruction.present?
        break if has_cpuid_instruction
      end
    end

    has_cpuid_instruction
  end
end

require "extend/os/formula_cellar_checks"
