# typed: true
# frozen_string_literal: true

require "cxxstdlib"
require "options"
require "json"
require "development_tools"
require "extend/cachable"

# Rather than calling `new` directly, use one of the class methods like {Tab.create}.
class Tab
  extend Cachable

  FILENAME = "INSTALL_RECEIPT.json"

  # Check whether the formula or cask was installed as a dependency.
  #
  # @api internal
  attr_accessor :installed_as_dependency

  # Check whether the formula or cask was installed on request.
  #
  # @api internal
  attr_accessor :installed_on_request

  attr_accessor :homebrew_version, :tabfile,
                :loaded_from_api, :time, :arch, :source,
                :built_on

  # Returns the formula or cask runtime dependencies.
  #
  # @api internal
  attr_writer :runtime_dependencies

  # Used only for cask tabs
  attr_accessor :caskfile_only, :uninstall_artifacts

  # Used only for formula tabs
  attr_accessor :built_as_bottle, :changed_files, :stdlib, :aliases
  attr_writer :used_options, :unused_options, :compiler, :source_modified_time

  # Check whether the formula was poured from a bottle.
  #
  # @api internal
  attr_accessor :poured_from_bottle

  def self.create(formula_or_cask, compiler = nil, stdlib = nil)
    return create_from_formula(formula_or_cask, compiler, stdlib) if formula_or_cask.is_a? Formula

    create_from_cask(formula_or_cask)
  end

  def self.generic_attributes
    {
      "homebrew_version"        => HOMEBREW_VERSION,
      "installed_as_dependency" => false,
      "installed_on_request"    => false,
      "time"                    => Time.now.to_i,
      "arch"                    => Hardware::CPU.arch,
      "built_on"                => DevelopmentTools.build_system_info,
    }
  end

  # Instantiates a {Tab} for a new installation of a formula.
  def self.create_from_formula(formula, compiler, stdlib)
    build = formula.build
    runtime_deps = formula.runtime_dependencies(undeclared: false)
    attributes = generic_attributes.merge({
      "used_options"         => build.used_options.as_flags,
      "unused_options"       => build.unused_options.as_flags,
      "tabfile"              => formula.prefix/FILENAME,
      "built_as_bottle"      => build.bottle?,
      "poured_from_bottle"   => false,
      "loaded_from_api"      => formula.loaded_from_api?,
      "source_modified_time" => formula.source_modified_time.to_i,
      "compiler"             => compiler,
      "stdlib"               => stdlib,
      "aliases"              => formula.aliases,
      "runtime_dependencies" => Tab.formula_runtime_deps_hash(formula, runtime_deps),
      "source"               => {
        "path"         => formula.specified_path.to_s,
        "tap"          => formula.tap&.name,
        "tap_git_head" => nil, # Filled in later if possible
        "spec"         => formula.active_spec_sym.to_s,
        "versions"     => {
          "stable"         => formula.stable&.version&.to_s,
          "head"           => formula.head&.version&.to_s,
          "version_scheme" => formula.version_scheme,
        },
      },
    })

    # We can only get `tap_git_head` if the tap is installed locally
    attributes["source"]["tap_git_head"] = formula.tap.git_head if formula.tap&.installed?

    new(attributes, type: :formula)
  end

  def self.create_from_cask(cask)
    attributes = generic_attributes.merge({
      "tabfile"              => cask.metadata_main_container_path/FILENAME,
      "loaded_from_api"      => cask.loaded_from_api?,
      "caskfile_only"        => cask.caskfile_only?,
      "runtime_dependencies" => Tab.cask_runtime_deps_hash(cask, cask.depends_on),
      "source"               => {
        "path"         => cask.sourcefile_path.to_s,
        "tap"          => cask.tap&.name,
        "tap_git_head" => nil, # Filled in later if possible
        "version"      => cask.version.to_s,
      },
      "uninstall_artifacts"  => cask.artifacts_list(uninstall_phase_only: true),
    })

    # We can only get `tap_git_head` if the tap is installed locally
    attributes["source"]["tap_git_head"] = cask.tap.git_head if cask.tap&.installed?

    new(attributes, type: :cask)
  end

  # Returns the {Tab} for an install receipt at `path`.
  #
  # NOTE: Results are cached.
  def self.from_file(path, type: :formula)
    cache.fetch(path) do |p|
      content = File.read(p)
      return empty(type:) if content.blank?

      cache[p] = from_file_content(content, p, type:)
    end
  end

  # Like {from_file}, but bypass the cache.
  def self.from_file_content(content, path, type: :formula)
    attributes = begin
      JSON.parse(content)
    rescue JSON::ParserError => e
      raise e, "Cannot parse #{path}: #{e}", e.backtrace
    end
    attributes["tabfile"] = path

    return new(attributes, type:) if type == :cask

    attributes["source_modified_time"] ||= 0
    attributes["source"] ||= {}

    tapped_from = attributes["tapped_from"]
    if !tapped_from.nil? && tapped_from != "path or URL"
      attributes["source"]["tap"] = attributes.delete("tapped_from")
    end

    if attributes["source"]["tap"] == "mxcl/master" ||
       attributes["source"]["tap"] == "Homebrew/homebrew"
      attributes["source"]["tap"] = "homebrew/core"
    end

    if attributes["source"]["spec"].nil?
      version = PkgVersion.parse(File.basename(File.dirname(path)))
      attributes["source"]["spec"] = if version.head?
        "head"
      else
        "stable"
      end
    end

    if attributes["source"]["versions"].nil?
      attributes["source"]["versions"] = {
        "stable"         => nil,
        "head"           => nil,
        "version_scheme" => 0,
      }
    end

    # Tabs created with Homebrew 1.5.13 through 4.0.17 inclusive created empty string versions in some cases.
    ["stable", "head"].each do |spec|
      attributes["source"]["versions"][spec] = attributes["source"]["versions"][spec].presence
    end

    new(attributes, type:)
  end

  # Get the {Tab} for the given {Keg},
  # or a fake one if the formula is not installed.
  #
  # @api internal
  sig { params(keg: T.any(Keg, Pathname)).returns(T.attached_class) }
  def self.for_keg(keg)
    path = keg/FILENAME

    tab = if path.exist?
      from_file(path, type: :formula)
    else
      empty(type: :formula)
    end

    tab.tabfile = path
    tab
  end

  # Returns a {Tab} for the named formula's installation,
  # or a fake one if the formula is not installed.
  def self.for_name(name)
    for_formula(Formulary.factory(name))
  end

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
      tab = from_file(path, type: :formula)
      used_options = remap_deprecated_options(formula.deprecated_options, tab.used_options)
      tab.used_options = used_options.as_flags
    else
      # Formula is not installed. Return a fake tab.
      tab = empty(type: :formula)
      tab.unused_options = formula.options.as_flags
      tab.source = {
        "path"     => formula.specified_path.to_s,
        "tap"      => formula.tap&.name,
        "spec"     => formula.active_spec_sym.to_s,
        "versions" => {
          "stable"         => formula.stable&.version&.to_s,
          "head"           => formula.head&.version&.to_s,
          "version_scheme" => formula.version_scheme,
        },
      }
    end

    tab
  end

  # Returns a {Tab} for an already installed cask,
  # or a fake one if the cask is not installed.
  def self.for_cask(cask)
    path = cask.metadata_main_container_path/FILENAME

    return from_file(path, type: :cask) if path.exist?

    tab = empty(type: :cask)
    tab.source = {
      "path"         => cask.sourcefile_path.to_s,
      "tap"          => cask.tap&.name,
      "tap_git_head" => nil,
      "version"      => cask.version.to_s,
    }
    tab.uninstall_artifacts = cask.artifacts_list(uninstall_phase_only: true)
    tab.source["tap_git_head"] = cask.tap.git_head if cask.tap&.installed?

    tab
  end

  def self.empty(type: :formula)
    attributes = {
      "homebrew_version"        => HOMEBREW_VERSION,
      "used_options"            => [],
      "unused_options"          => [],
      "built_as_bottle"         => false,
      "installed_as_dependency" => false,
      "installed_on_request"    => false,
      "poured_from_bottle"      => false,
      "loaded_from_api"         => false,
      "caskfile_only"           => false,
      "time"                    => nil,
      "source_modified_time"    => 0,
      "stdlib"                  => nil,
      "compiler"                => DevelopmentTools.default_compiler,
      "aliases"                 => [],
      "runtime_dependencies"    => nil,
      "arch"                    => nil,
      "source"                  => {
        "path"         => nil,
        "tap"          => nil,
        "tap_git_head" => nil,
        "spec"         => "stable",
        "versions"     => {
          "stable"         => nil,
          "head"           => nil,
          "version_scheme" => 0,
        },
      },
      "uninstall_artifacts"     => [],
      "built_on"                => DevelopmentTools.generic_build_system_info,
    }

    new(attributes, type:)
  end

  def self.formula_runtime_deps_hash(formula, deps)
    deps.map do |dep|
      f = dep.to_formula
      {
        "full_name"         => f.full_name,
        "version"           => f.version.to_s,
        "revision"          => f.revision,
        "pkg_version"       => f.pkg_version.to_s,
        "declared_directly" => formula.deps.include?(dep),
      }
    end
  end

  def self.cask_runtime_deps_hash(cask, depends_on)
    mappable_types = [:cask, :formula]
    depends_on.to_h do |type, deps|
      next [type, deps] unless mappable_types.include? type

      deps = deps.map do |dep|
        if type == :cask
          c = Cask::CaskLoader.load(dep)
          {
            "full_name"         => c.full_name,
            "version"           => c.version.to_s,
            "declared_directly" => cask.depends_on.cask.include?(dep),
          }
        elsif type == :formula
          f = Formulary.factory(dep, warn: false)
          {
            "full_name"         => f.full_name,
            "version"           => f.version.to_s,
            "revision"          => f.revision,
            "pkg_version"       => f.pkg_version.to_s,
            "declared_directly" => cask.depends_on.formula.include?(dep),
          }
        else
          dep
        end
      end

      [type, deps]
    end
  end

  def initialize(attributes = {}, type: :formula)
    @type = type
    attributes.each { |key, value| instance_variable_set(:"@#{key}", value) }
  end

  def any_args_or_options?
    !used_options.empty? || !unused_options.empty?
  end

  def with?(val)
    option_names = val.respond_to?(:option_names) ? val.option_names : [val]

    option_names.any? do |name|
      include?("with-#{name}") || unused_options.include?("without-#{name}")
    end
  end

  def without?(val)
    !with?(val)
  end

  def include?(opt)
    used_options.include? opt
  end

  def head?
    spec == :head
  end

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

  def unused_options
    Options.create(@unused_options)
  end

  def compiler
    @compiler || DevelopmentTools.default_compiler
  end

  def parsed_homebrew_version
    return Version::NULL if homebrew_version.nil?

    Version.new(homebrew_version)
  end

  def runtime_dependencies
    # Homebrew versions prior to 1.1.6 generated incorrect runtime dependency
    # lists.
    @runtime_dependencies if parsed_homebrew_version >= "1.1.6"
  end

  def cxxstdlib
    # Older tabs won't have these values, so provide sensible defaults
    lib = stdlib.to_sym if stdlib
    CxxStdlib.create(lib, compiler.to_sym)
  end

  def built_bottle?
    built_as_bottle && !poured_from_bottle
  end

  def bottle?
    built_as_bottle
  end

  sig { returns(T.nilable(Tap)) }
  def tap
    tap_name = source["tap"]
    Tap.fetch(tap_name) if tap_name
  end

  def tap=(tap)
    tap_name = tap.respond_to?(:name) ? tap.name : tap
    source["tap"] = tap_name
  end

  def spec
    source["spec"].to_sym
  end

  def cask_version
    source["version"]
  end

  def versions
    source["versions"]
  end

  def stable_version
    versions["stable"]&.then { Version.new(_1) }
  end

  def head_version
    versions["head"]&.then { Version.new(_1) }
  end

  def version_scheme
    versions["version_scheme"] || 0
  end

  sig { returns(Time) }
  def source_modified_time
    Time.at(@source_modified_time || 0)
  end

  def to_json(options = nil)
    return to_cask_json(options) if @type == :cask

    to_formula_json(options)
  end

  def to_formula_json(options = nil)
    attributes = {
      "homebrew_version"        => homebrew_version,
      "used_options"            => used_options.as_flags,
      "unused_options"          => unused_options.as_flags,
      "built_as_bottle"         => built_as_bottle,
      "poured_from_bottle"      => poured_from_bottle,
      "loaded_from_api"         => loaded_from_api,
      "installed_as_dependency" => installed_as_dependency,
      "installed_on_request"    => installed_on_request,
      "changed_files"           => changed_files&.map(&:to_s),
      "time"                    => time,
      "source_modified_time"    => source_modified_time.to_i,
      "stdlib"                  => stdlib&.to_s,
      "compiler"                => compiler&.to_s,
      "aliases"                 => aliases,
      "runtime_dependencies"    => runtime_dependencies,
      "source"                  => source,
      "arch"                    => arch,
      "built_on"                => built_on,
    }
    attributes.delete("stdlib") if attributes["stdlib"].blank?

    JSON.pretty_generate(attributes, options)
  end

  def to_cask_json(*_args)
    attributes = {
      "homebrew_version"        => homebrew_version,
      "loaded_from_api"         => loaded_from_api,
      "caskfile_only"           => caskfile_only,
      "installed_as_dependency" => installed_as_dependency,
      "installed_on_request"    => installed_on_request,
      "time"                    => time,
      "runtime_dependencies"    => runtime_dependencies,
      "source"                  => source,
      "arch"                    => arch,
      "uninstall_artifacts"     => uninstall_artifacts,
      "built_on"                => built_on,
    }

    JSON.pretty_generate(attributes)
  end

  # A subset of to_json that we care about for bottles.
  def to_bottle_hash
    attributes = {
      "homebrew_version"     => homebrew_version,
      "changed_files"        => changed_files&.map(&:to_s),
      "source_modified_time" => source_modified_time.to_i,
      "stdlib"               => stdlib&.to_s,
      "compiler"             => compiler&.to_s,
      "runtime_dependencies" => runtime_dependencies,
      "arch"                 => arch,
      "built_on"             => built_on,
    }
    attributes.delete("stdlib") if attributes["stdlib"].blank?
    attributes
  end

  def write
    # If this is a new installation, the cache of installed formulae
    # will no longer be valid.
    Formula.clear_cache if @type == :formula && !tabfile.exist?

    self.class.cache[tabfile] = self
    tabfile.atomic_write(to_json)
  end

  sig { returns(String) }
  def to_s
    s = []
    s << if @type == :cask
      "Installed"
    elsif poured_from_bottle
      "Poured from bottle"
    else
      "Built from source"
    end

    s << "using the formulae.brew.sh API" if loaded_from_api
    s << Time.at(time).strftime("on %Y-%m-%d at %H:%M:%S") if time

    if @type == :formula && used_options.any?
      s << "with:"
      s << used_options.to_a.join(" ")
    end
    s.join(" ")
  end
end
