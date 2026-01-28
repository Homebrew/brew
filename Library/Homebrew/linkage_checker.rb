# typed: strict
# frozen_string_literal: true

require "keg"
require "formula"
require "linkage_cache_store"
require "utils/output"

# Check for broken/missing linkage in a formula's keg.
class LinkageChecker
  include Utils::Output::Mixin

  sig { returns(Keg) }
  attr_reader :keg

  sig { returns(T.nilable(Formula)) }
  attr_reader :formula

  sig { returns(LinkageCacheStore) }
  attr_reader :store

  sig { returns(T::Array[String]) }
  attr_reader :indirect_deps, :undeclared_deps, :unwanted_system_dylibs

  sig { returns(T::Set[String]) }
  attr_reader :system_dylibs

  sig { params(keg: Keg, formula: T.nilable(Formula), cache_db: CacheStoreDatabase, rebuild_cache: T::Boolean).void }
  def initialize(keg, formula = nil, cache_db:, rebuild_cache: false)
    @keg = keg
    @formula = T.let(formula || resolve_formula(keg), T.nilable(Formula))
    @store = T.let(LinkageCacheStore.new(keg.to_s, cache_db), LinkageCacheStore)

    @system_dylibs    = T.let(Set.new, T::Set[String])
    @broken_dylibs    = T.let(Set.new, T::Set[String])
    @variable_dylibs  = T.let(Set.new, T::Set[String])
    @brewed_dylibs    = T.let({}, T::Hash[String, T::Set[String]])
    @reverse_links    = T.let({}, T::Hash[String, T::Set[String]])
    @broken_deps      = T.let({}, T::Hash[String, T::Array[String]])
    @indirect_deps    = T.let([], T::Array[String])
    @undeclared_deps  = T.let([], T::Array[String])
    @unnecessary_deps = T.let([], T::Array[String])
    @no_linkage_deps  = T.let([], T::Array[String])
    @unexpected_linkage_deps = T.let([], T::Array[String])
    @unwanted_system_dylibs = T.let([], T::Array[String])
    @version_conflict_deps = T.let([], T::Array[String])
    @files_missing_rpaths = T.let([], T::Array[String])
    @executable_path_dylibs = T.let([], T::Array[String])

    check_dylibs(rebuild_cache:)
  end

  sig { void }
  def display_normal_output
    display_items "System libraries", @system_dylibs
    display_items "Homebrew libraries", @brewed_dylibs
    display_items "Indirect dependencies with linkage", @indirect_deps
    display_items "@rpath-referenced libraries", @variable_dylibs
    display_items "Missing libraries", @broken_dylibs
    display_items "Broken dependencies", @broken_deps
    display_items "Undeclared dependencies with linkage", @undeclared_deps
    display_items "Dependencies with no linkage", @unnecessary_deps
    display_items "Homebrew dependencies not requiring linkage", @no_linkage_deps
    display_items "Unexpected linkage for no_linkage dependencies", @unexpected_linkage_deps
    display_items "Unwanted system libraries", @unwanted_system_dylibs
    display_items "Files with missing rpath", @files_missing_rpaths
    display_items "@executable_path references in libraries", @executable_path_dylibs
  end

  sig { void }
  def display_reverse_output
    return if @reverse_links.empty?

    sorted = @reverse_links.sort
    sorted.each do |dylib, files|
      puts dylib
      files.each do |f|
        unprefixed = f.to_s.delete_prefix "#{keg}/"
        puts "  #{unprefixed}"
      end
      puts if dylib != sorted.last&.first
    end
  end

  sig { params(puts_output: T::Boolean, strict: T::Boolean).void }
  def display_test_output(puts_output: true, strict: false)
    display_items("Missing libraries", @broken_dylibs, puts_output:)
    display_items("Broken dependencies", @broken_deps, puts_output:)
    display_items("Unwanted system libraries", @unwanted_system_dylibs, puts_output:)
    display_items("Conflicting libraries", @version_conflict_deps, puts_output:)
    display_items("Indirect dependencies with linkage", @indirect_deps, puts_output:)
    return unless strict

    display_items("Undeclared dependencies with linkage", @undeclared_deps, puts_output:)
    display_items("Unexpected linkage for no_linkage dependencies", @unexpected_linkage_deps, puts_output:)
    display_items("Files with missing rpath", @files_missing_rpaths, puts_output:)
    display_items "@executable_path references in libraries", @executable_path_dylibs, puts_output:
  end

  sig { params(test: T::Boolean, strict: T::Boolean).returns(T::Boolean) }
  def broken_library_linkage?(test: false, strict: false)
    raise ArgumentError, "Strict linkage checking requires test mode to be enabled." if strict && !test

    issues = [@broken_deps, @broken_dylibs]
    if test
      issues += [@unwanted_system_dylibs, @version_conflict_deps, @indirect_deps]
      if strict
        issues += [@undeclared_deps, @unexpected_linkage_deps,
                   @files_missing_rpaths, @executable_path_dylibs]
      end
    end
    issues.any?(&:present?)
  end

  private

  sig { params(dylib: String).returns(T.nilable(String)) }
  def dylib_to_dep(dylib)
    dylib =~ %r{#{Regexp.escape(HOMEBREW_PREFIX)}/(opt|Cellar)/([\w+-.@]+)/}o
    Regexp.last_match(2)
  end

  sig { params(file: String).returns(T::Boolean) }
  def broken_dylibs_allowed?(file)
    formula = self.formula
    return false if formula.nil? || formula.name != "julia"

    file.start_with?("#{formula.prefix.realpath}/share/julia/compiled/")
  end

  sig { params(rebuild_cache: T::Boolean).void }
  def check_dylibs(rebuild_cache:)
    keg_files_dylibs = nil

    if rebuild_cache
      store.delete!
    else
      keg_files_dylibs = store.fetch(:keg_files_dylibs)
    end

    keg_files_dylibs_was_empty = false
    keg_files_dylibs ||= {}
    if keg_files_dylibs.empty?
      keg_files_dylibs_was_empty = true
      @keg.find do |file|
        next if file.symlink? || file.directory?

        file = begin
          BinaryPathname.wrap(file)
        rescue NotImplementedError
          next
        end

        next if !file.dylib? && !file.binary_executable? && !file.mach_o_bundle?
        next unless file.arch_compatible?(Hardware::CPU.arch)

        # weakly loaded dylibs may not actually exist on disk, so skip them
        # when checking for broken linkage
        keg_files_dylibs[file] =
          file.dynamically_linked_libraries(except: :DYLIB_USE_WEAK_LINK)
      end
    end

    checked_dylibs = Set.new

    keg_files_dylibs.each do |file, dylibs|
      file_has_any_rpath_dylibs = T.let(false, T::Boolean)
      dylibs.each do |dylib|
        (@reverse_links[dylib] ||= Set.new) << file

        # Files that link @rpath-prefixed dylibs must include at
        # least one rpath in order to resolve it.
        if !file_has_any_rpath_dylibs && (dylib.start_with? "@rpath/")
          file_has_any_rpath_dylibs = true
          pathname = Pathname(file)
          @files_missing_rpaths << file if pathname.rpaths.empty? && !broken_dylibs_allowed?(file.to_s)
        end

        next if checked_dylibs.include? dylib

        checked_dylibs << dylib

        if dylib.start_with? "@rpath"
          @variable_dylibs << dylib
          next
        elsif dylib.start_with?("@executable_path") && !Pathname(file).binary_executable?
          @executable_path_dylibs << dylib
          next
        end

        begin
          owner = Keg.for(Pathname(dylib))
        rescue NotAKegError
          @system_dylibs << dylib
        rescue Errno::ENOENT
          next if harmless_broken_link?(dylib)

          if (dep = dylib_to_dep(dylib))
            broken_dep = (@broken_deps[dep] ||= [])
            broken_dep << dylib unless broken_dep.include?(dylib)
          elsif system_libraries_exist_in_cache? && dylib_found_in_shared_cache?(dylib)
            # If we cannot associate the dylib with a dependency, then it may be a system library.
            # Check the dylib shared cache for the library to verify this.
            @system_dylibs << dylib
          elsif !system_framework?(dylib) && !broken_dylibs_allowed?(file.to_s)
            @broken_dylibs << dylib
          end
        else
          tap = owner.tab.tap
          f = if tap.nil? || tap.core_tap?
            owner.name
          else
            "#{tap}/#{owner.name}"
          end
          (@brewed_dylibs[f] ||= Set.new) << dylib
        end
      end
    end

    if (check_formula_deps = self.check_formula_deps)
      @indirect_deps, @undeclared_deps, @unnecessary_deps,
        @version_conflict_deps, @no_linkage_deps, @unexpected_linkage_deps = check_formula_deps
    end

    return unless keg_files_dylibs_was_empty

    store.update!(keg_files_dylibs:)
  end

  sig { returns(T::Boolean) }
  def system_libraries_exist_in_cache?
    false
  end

  sig { params(dylib: String).returns(T::Boolean) }
  def dylib_found_in_shared_cache?(dylib)
    require "fiddle"
    @dyld_shared_cache_contains_path ||= T.let(begin
      libc = Fiddle.dlopen("/usr/lib/libSystem.B.dylib")

      Fiddle::Function.new(
        libc["_dyld_shared_cache_contains_path"],
        [Fiddle::TYPE_CONST_STRING],
        Fiddle::TYPE_BOOL,
      )
    end, T.nilable(Fiddle::Function))

    @dyld_shared_cache_contains_path.call(dylib)
  end

  sig {
    returns(T.nilable([T::Array[String], T::Array[String], T::Array[String],
                       T::Array[String], T::Array[String], T::Array[String]]))
  }
  def check_formula_deps
    formula = self.formula
    return if formula.nil?

    filter_out = proc do |dep|
      next true if dep.build? || dep.test?

      (dep.optional? || dep.recommended?) && formula.build.without?(dep)
    end

    declared_deps_full_names = formula.deps
                                      .reject { |dep| filter_out.call(dep) }
                                      .map(&:name)
    declared_deps_names = declared_deps_full_names.map do |dep|
      dep.split("/").last
    end

    # Get dependencies marked with :no_linkage
    no_linkage_deps_full_names = formula.deps
                                        .reject { |dep| filter_out.call(dep) }
                                        .select(&:no_linkage?)
                                        .map(&:name)
    no_linkage_deps_names = no_linkage_deps_full_names.map do |dep|
      dep.split("/").last
    end

    recursive_deps = formula.runtime_formula_dependencies(undeclared: false)
                            .map(&:name)

    indirect_deps = []
    undeclared_deps = []
    unexpected_linkage_deps = []
    @brewed_dylibs.each_key do |full_name|
      name = full_name.split("/").last
      next if name == formula.name

      # Check if this is a no_linkage dependency with unexpected linkage
      if no_linkage_deps_names.include?(name)
        unexpected_linkage_deps << full_name
        next
      end

      if recursive_deps.include?(name)
        indirect_deps << full_name unless declared_deps_names.include?(name)
      else
        undeclared_deps << full_name
      end
    end

    sort_by_formula_full_name!(indirect_deps)
    sort_by_formula_full_name!(undeclared_deps)
    sort_by_formula_full_name!(unexpected_linkage_deps)

    unnecessary_deps = declared_deps_full_names.reject do |full_name|
      next true if Formula[full_name].bin.directory?

      name = full_name.split("/").last
      @brewed_dylibs.keys.map { |l| l.split("/").last }.include?(name)
    end

    # Remove no_linkage dependencies from unnecessary_deps since they're expected not to have linkage
    unnecessary_deps -= no_linkage_deps_full_names

    missing_deps = @broken_deps.values.flatten.map { |d| dylib_to_dep(d) }
    unnecessary_deps -= missing_deps

    version_hash = {}
    version_conflict_deps = Set.new
    @brewed_dylibs.each_key do |l|
      name = l.split("/").fetch(-1)
      unversioned_name, = name.split("@")
      version_hash[unversioned_name] ||= Set.new
      version_hash[unversioned_name] << name
      next if version_hash[unversioned_name].length < 2

      version_conflict_deps += version_hash[unversioned_name]
    end

    [indirect_deps, undeclared_deps,
     unnecessary_deps, version_conflict_deps.to_a, no_linkage_deps_full_names, unexpected_linkage_deps]
  end

  sig { params(arr: T::Array[String]).void }
  def sort_by_formula_full_name!(arr)
    arr.sort! do |a, b|
      if a.include?("/") && b.exclude?("/")
        1
      elsif a.exclude?("/") && b.include?("/")
        -1
      else
        (a <=> b).to_i
      end
    end
  end

  # Whether or not dylib is a harmless broken link, meaning that it's
  # okay to skip (and not report) as broken.
  sig { params(dylib: String).returns(T::Boolean) }
  def harmless_broken_link?(dylib)
    # libgcc_s_* is referenced by programs that use the Java Service Wrapper,
    # and is harmless on x86(_64) machines
    # dyld will fall back to Apple libc++ if LLVM's is not available.
    [
      "/usr/lib/libgcc_s_ppc64.1.dylib",
      "/opt/local/lib/libgcc/libgcc_s.1.dylib",
      # TODO: Report linkage with `/usr/lib/libc++.1.dylib` when this link is broken.
      "#{HOMEBREW_PREFIX}/opt/llvm/lib/libc++.1.dylib",
    ].include?(dylib)
  end

  sig { params(dylib: String).returns(T::Boolean) }
  def system_framework?(dylib)
    dylib.start_with?("/System/Library/Frameworks/")
  end

  # Display a list of things.
  sig {
    params(
      label:       String,
      things:      T.any(T::Array[String], T::Set[String], T::Hash[String, T::Enumerable[String]]),
      puts_output: T::Boolean,
    ).returns(T.nilable(String))
  }
  def display_items(label, things, puts_output: true)
    return if things.empty?

    output = ["#{label}:"]
    if things.is_a? Hash
      things.sort.each do |list_label, items|
        items.sort.each do |item|
          output << "#{item} (#{list_label})"
        end
      end
    else
      output.concat(things.sort)
    end
    output = output.join("\n  ")
    puts output if puts_output
    output
  end

  sig { params(keg: Keg).returns(T.nilable(Formula)) }
  def resolve_formula(keg)
    Formulary.from_keg(keg)
  rescue FormulaUnavailableError
    opoo "Formula unavailable: #{keg.name}"
    nil
  end
end

require "extend/os/linkage_checker"
