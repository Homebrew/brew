# typed: strict
# frozen_string_literal: true

class Tab < AbstractTab
  Cache = type_template { { fixed: T::Hash[T.any(Pathname, String), T.untyped] } }

  # Check whether the formula was poured from a bottle.
  #
  # @api internal
  sig { returns(T.nilable(T::Boolean)) }
  attr_accessor :poured_from_bottle

  sig { returns(T.nilable(T::Boolean)) }
  attr_accessor :built_as_bottle

  sig { returns(T.nilable(T.any(String, Symbol))) }
  attr_accessor :stdlib

  sig { returns(T.nilable(T::Array[String])) }
  attr_accessor :aliases

  sig { params(used_options: T.nilable(T::Array[String])).returns(T.nilable(T::Array[String])) }
  attr_writer :used_options

  sig { params(unused_options: T.nilable(T::Array[String])).returns(T.nilable(T::Array[String])) }
  attr_writer :unused_options

  sig { params(compiler: T.nilable(T.any(String, Symbol))).returns(T.nilable(T.any(String, Symbol))) }
  attr_writer :compiler

  sig { params(source_modified_time: T.nilable(Integer)).returns(T.nilable(Integer)) }
  attr_writer :source_modified_time

  sig { returns(T.nilable(String)) }
  attr_reader :tapped_from

  sig { returns(T.nilable(T::Array[Pathname])) }
  attr_accessor :changed_files

  sig { params(attributes: T.any(T::Hash[String, T.untyped], T::Hash[Symbol, T.untyped])).void }
  def initialize(attributes = {})
    @poured_from_bottle = T.let(nil, T.nilable(T::Boolean))
    @built_as_bottle = T.let(nil, T.nilable(T::Boolean))
    @changed_files = T.let(nil, T.nilable(T::Array[Pathname]))
    @stdlib = T.let(nil, T.nilable(T.any(String, Symbol)))
    @aliases = T.let(nil, T.nilable(T::Array[String]))
    @used_options = T.let(nil, T.nilable(T::Array[String]))
    @unused_options = T.let(nil, T.nilable(T::Array[String]))
    @compiler = T.let(nil, T.nilable(T.any(String, Symbol)))
    @source_modified_time = T.let(nil, T.nilable(Integer))
    @tapped_from = T.let(nil, T.nilable(String))

    super
  end

  # Instantiates a {Tab} for a new installation of a formula.
  sig {
    override.params(formula_or_cask: T.any(Formula, Cask::Cask), compiler: T.any(Symbol, String),
                    stdlib: T.nilable(T.any(String, Symbol))).returns(T.attached_class)
  }
  def self.create(formula_or_cask, compiler = DevelopmentTools.default_compiler, stdlib = nil)
    formula = T.cast(formula_or_cask, Formula)

    tab = super(formula)
    build = formula.build
    runtime_deps = formula.runtime_dependencies(undeclared: false)

    tab.used_options = build.used_options.as_flags
    tab.unused_options = build.unused_options.as_flags
    tab.tabfile = formula.prefix/FILENAME
    tab.built_as_bottle = build.bottle?
    tab.poured_from_bottle = false
    tab.source_modified_time = formula.source_modified_time.to_i
    tab.compiler = compiler
    tab.stdlib = stdlib
    tab.aliases = formula.aliases
    tab.runtime_dependencies = Tab.runtime_deps_hash(formula, runtime_deps)
    active_spec = if formula.active_spec_sym == :head
      T.must(formula.head)
    else
      T.must(formula.stable)
    end

    tab.source["spec"] = formula.active_spec_sym.to_s
    tab.source["path"] = formula.specified_path.to_s
    if (downloader = active_spec.downloader).cached_location.exist? &&
       (scm_revision = downloader.source_revision).present?
      tab.source["scm_revision"] = scm_revision
    end
    tab.source["versions"] = {
      "stable"                => formula.stable&.version&.to_s,
      "head"                  => formula.head&.version&.to_s,
      "version_scheme"        => formula.version_scheme,
      "compatibility_version" => formula.compatibility_version,
    }

    tab
  end

  # Like {from_file}, but bypass the cache.
  sig { params(content: String, path: T.any(Pathname, String)).returns(T.attached_class) }
  def self.from_file_content(content, path)
    tab = super

    tab.tap = tab.tapped_from if !tab.tapped_from.nil? && tab.tapped_from != "path or URL"
    tab.tap = "homebrew/core" if ["mxcl/master", "Homebrew/homebrew"].include?(tab.tap)

    if tab.source["spec"].nil?
      version = PkgVersion.parse(File.basename(File.dirname(path)))
      tab.source["spec"] = if version.head?
        "head"
      else
        "stable"
      end
    end

    tab.source["versions"] ||= empty_source_versions

    # Tabs created with Homebrew 1.5.13 through 4.0.17 inclusive created empty string versions in some cases.
    ["stable", "head"].each do |spec|
      tab.source["versions"][spec] = tab.source["versions"][spec].presence
    end

    tab
  end

  # Get the {Tab} for the given {Keg},
  # or a fake one if the formula is not installed.
  #
  # @api internal
  sig { params(keg: T.any(Keg, Pathname)).returns(T.attached_class) }
  def self.for_keg(keg)
    path = keg/FILENAME

    tab = if path.exist?
      from_file(path)
    else
      empty
    end

    tab.tabfile = path
    tab
  end

  # Returns a {Tab} for the named formula's installation,
  # or a fake one if the formula is not installed.
  sig { params(name: String).returns(T.attached_class) }
  def self.for_name(name)
    rack = HOMEBREW_CELLAR/name
    if (keg = Keg.from_rack(rack))
      for_keg(keg)
    else
      for_formula(Formulary.from_rack(rack, keg:))
    end
  end

  sig { params(deprecated_options: T::Array[DeprecatedOption], options: Options).returns(Options) }
  def self.remap_deprecated_options(deprecated_options, options)
    deprecated_options.each do |deprecated_option|
      option = options.find { |o| o.name == deprecated_option.old }
      next unless option

      options -= [option]
      options << Option.new(deprecated_option.current, option.description)
    end
    options
  end

  # Returns a {Tab} for an already installed formula,
  # or a fake one if the formula is not installed.
  sig { params(formula: Formula).returns(T.attached_class) }
  def self.for_formula(formula)
    paths = []

    paths << formula.opt_prefix.resolved_path if formula.opt_prefix.symlink? && formula.opt_prefix.directory?

    paths << formula.linked_keg.resolved_path if formula.linked_keg.symlink? && formula.linked_keg.directory?

    if (dirs = formula.installed_prefixes).length == 1
      paths << dirs.first
    end

    paths << formula.latest_installed_prefix

    path = paths.map { |pathname| pathname/FILENAME }.find(&:file?)

    if path
      tab = from_file(path)
      used_options = remap_deprecated_options(formula.deprecated_options, tab.used_options)
      tab.used_options = used_options.as_flags
    else
      # Formula is not installed. Return a fake tab.
      tab = empty
      tab.unused_options = formula.options.as_flags
      tab.source = {
        "path"         => formula.specified_path.to_s,
        "tap"          => formula.tap&.name,
        "tap_git_head" => formula.tap_git_head,
        "spec"         => formula.active_spec_sym.to_s,
        "versions"     => {
          "stable"         => formula.stable&.version&.to_s,
          "head"           => formula.head&.version&.to_s,
          "version_scheme" => formula.version_scheme,
        },
      }
    end

    tab
  end

  sig { returns(T.attached_class) }
  def self.empty
    tab = super

    tab.used_options = []
    tab.unused_options = []
    tab.built_as_bottle = false
    tab.poured_from_bottle = false
    tab.source_modified_time = 0
    tab.stdlib = nil
    tab.compiler = DevelopmentTools.default_compiler
    tab.aliases = []
    tab.source["spec"] = "stable"
    tab.source["versions"] = empty_source_versions

    tab
  end

  sig { returns(T::Hash[String, T.untyped]) }
  def self.empty_source_versions
    {
      "stable"                => nil,
      "head"                  => nil,
      "version_scheme"        => 0,
      "compatibility_version" => nil,
    }
  end
  private_class_method :empty_source_versions

  sig { params(formula: Formula, deps: T::Array[Dependency]).returns(T::Array[T::Hash[String, T.untyped]]) }
  def self.runtime_deps_hash(formula, deps)
    deps.map do |dep|
      formula_to_dep_hash(dep.to_formula, formula.deps.map(&:name))
    end
  end

  sig { returns(T::Boolean) }
  def any_args_or_options?
    !used_options.empty? || !unused_options.empty?
  end

  sig { params(val: T.any(String, Dependency, Requirement)).returns(T::Boolean) }
  def with?(val)
    option_names = val.is_a?(String) ? [val] : val.option_names

    option_names.any? do |name|
      include?("with-#{name}") || unused_options.include?("without-#{name}")
    end
  end

  sig { params(val: T.any(String, Dependency, Requirement)).returns(T::Boolean) }
  def without?(val)
    !with?(val)
  end

  sig { params(opt: String).returns(T::Boolean) }
  def include?(opt)
    used_options.include? opt
  end

  sig { returns(T::Boolean) }
  def head?
    spec == :head
  end

  sig { returns(T::Boolean) }
  def stable?
    spec == :stable
  end

  # The options used to install the formula.
  #
  # @api internal
  sig { returns(Options) }
  def used_options
    Options.create(@used_options)
  end

  sig { returns(Options) }
  def unused_options
    Options.create(@unused_options)
  end

  sig { returns(T.any(String, Symbol)) }
  def compiler
    @compiler || DevelopmentTools.default_compiler
  end

  sig { override.returns(RuntimeDependencies) }
  def runtime_dependencies
    # Homebrew versions prior to 1.1.6 generated incorrect runtime dependency
    # lists.
    @runtime_dependencies if parsed_homebrew_version >= "1.1.6"
  end

  sig { returns(CxxStdlib) }
  def cxxstdlib
    # Older tabs won't have these values, so provide sensible defaults
    lib = stdlib&.to_sym
    CxxStdlib.create(lib, compiler.to_sym)
  end

  sig { returns(T::Boolean) }
  def built_bottle?
    !!built_as_bottle && !poured_from_bottle
  end

  sig { returns(T::Boolean) }
  def bottle?
    !!built_as_bottle
  end

  sig { returns(Symbol) }
  def spec
    source["spec"].to_sym
  end

  sig { returns(T::Hash[String, T.untyped]) }
  def versions
    source["versions"]
  end

  sig { returns(T.nilable(Version)) }
  def stable_version
    versions["stable"]&.then { Version.new(it) }
  end

  sig { returns(T.nilable(Version)) }
  def head_version
    versions["head"]&.then { Version.new(it) }
  end

  sig { returns(Integer) }
  def version_scheme
    versions["version_scheme"] || 0
  end

  sig { returns(Time) }
  def source_modified_time
    Time.at(@source_modified_time || 0)
  end

  sig { params(options: T.nilable(T::Hash[String, T.untyped])).returns(String) }
  def to_json(options = nil)
    attributes = {
      "homebrew_version"         => homebrew_version,
      "used_options"             => used_options.as_flags,
      "unused_options"           => unused_options.as_flags,
      "built_as_bottle"          => built_as_bottle,
      "poured_from_bottle"       => poured_from_bottle,
      "loaded_from_api"          => loaded_from_api,
      "loaded_from_internal_api" => loaded_from_internal_api,
      "installed_on_request"     => installed_on_request,
      "changed_files"            => changed_files&.map(&:to_s),
      "time"                     => time,
      "source_modified_time"     => source_modified_time.to_i,
      "stdlib"                   => stdlib&.to_s,
      "compiler"                 => compiler.to_s,
      "aliases"                  => aliases,
      "runtime_dependencies"     => runtime_dependencies,
      "source"                   => source,
      "arch"                     => arch,
      "built_on"                 => built_on,
    }
    attributes.delete("stdlib") if attributes["stdlib"].blank?

    JSON.pretty_generate(attributes, options)
  end

  # A subset of to_json that we care about for bottles.
  sig { returns(T::Hash[String, T.untyped]) }
  def to_bottle_hash
    attributes = {
      "homebrew_version"     => homebrew_version,
      "changed_files"        => changed_files&.map(&:to_s),
      "source_modified_time" => source_modified_time.to_i,
      "stdlib"               => stdlib&.to_s,
      "compiler"             => compiler.to_s,
      "runtime_dependencies" => runtime_dependencies,
      "source"               => source.slice("scm_revision").compact.presence,
      "arch"                 => arch,
      "built_on"             => built_on,
    }
    attributes.delete("stdlib") if attributes["stdlib"].blank?
    attributes.delete("source") if attributes["source"].blank?
    attributes
  end

  sig { void }
  def write
    # If this is a new installation, the cache of installed formulae
    # will no longer be valid.
    Formula.clear_cache unless tabfile&.exist?

    super
  end

  sig { returns(String) }
  def to_s
    s = []
    s << if poured_from_bottle
      "Poured from bottle"
    else
      "Built from source"
    end

    if loaded_from_internal_api
      s << "using the internal formulae.brew.sh API"
    elsif loaded_from_api
      s << "using the formulae.brew.sh API"
    end

    if (t = time)
      s << Time.at(t).strftime("on %Y-%m-%d at %H:%M:%S")
    end

    unless used_options.empty?
      s << "with:"
      s << used_options.to_a.join(" ")
    end
    s.join(" ")
  end
end
