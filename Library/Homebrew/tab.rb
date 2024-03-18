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

  attr_accessor :homebrew_version, :tabfile, :built_as_bottle, :installed_as_dependency, :installed_on_request,
                :changed_files, :poured_from_bottle, :loaded_from_api, :time, :stdlib, :aliases, :arch, :source,
                :built_on
  attr_writer :used_options, :unused_options, :compiler, :runtime_dependencies, :source_modified_time

  # Instantiates a {Tab} for a new installation of a formula.
  def self.create(formula, compiler, stdlib)
    build = formula.build
    runtime_deps = formula.runtime_dependencies(undeclared: false)
    attributes = {
      "homebrew_version"        => HOMEBREW_VERSION,
      "used_options"            => build.used_options.as_flags,
      "unused_options"          => build.unused_options.as_flags,
      "tabfile"                 => formula.prefix/FILENAME,
      "built_as_bottle"         => build.bottle?,
      "installed_as_dependency" => false,
      "installed_on_request"    => false,
      "poured_from_bottle"      => false,
      "loaded_from_api"         => false,
      "time"                    => Time.now.to_i,
      "source_modified_time"    => formula.source_modified_time.to_i,
      "compiler"                => compiler,
      "stdlib"                  => stdlib,
      "aliases"                 => formula.aliases,
      "runtime_dependencies"    => Tab.runtime_deps_hash(formula, runtime_deps),
      "arch"                    => Hardware::CPU.arch,
      "source"                  => {
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
      "built_on"                => DevelopmentTools.build_system_info,
    }

    # We can only get `tap_git_head` if the tap is installed locally
    attributes["source"]["tap_git_head"] = formula.tap.git_head if formula.tap&.installed?

    new(attributes)
  end

  # Returns the {Tab} for an install receipt at `path`.
  # Results are cached.
  def self.from_file(path)
    cache.fetch(path) do |p|
      content = File.read(p)
      return empty if content.blank?

      cache[p] = from_file_content(content, p)
    end
  end

  # Like {from_file}, but bypass the cache.
  def self.from_file_content(content, path)
    attributes = begin
      JSON.parse(content)
    rescue JSON::ParserError => e
      raise e, "Cannot parse #{path}: #{e}", e.backtrace
    end
    attributes["tabfile"] = path
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

    new(attributes)
  end

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
      tab = from_file(path)
      used_options = remap_deprecated_options(formula.deprecated_options, tab.used_options)
      tab.used_options = used_options.as_flags
    else
      # Formula is not installed. Return a fake tab.
      tab = empty
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

  def self.empty
    attributes = {
      "homebrew_version"        => HOMEBREW_VERSION,
      "used_options"            => [],
      "unused_options"          => [],
      "built_as_bottle"         => false,
      "installed_as_dependency" => false,
      "installed_on_request"    => false,
      "poured_from_bottle"      => false,
      "loaded_from_api"         => false,
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
      "built_on"                => DevelopmentTools.generic_build_system_info,
    }

    new(attributes)
  end

  def self.runtime_deps_hash(formula, deps)
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

  def initialize(attributes = {})
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
    Formula.clear_cache unless tabfile.exist?

    self.class.cache[tabfile] = self
    tabfile.atomic_write(to_json)
  end

  sig { returns(String) }
  def to_s
    s = []
    s << if poured_from_bottle
      "Poured from bottle"
    else
      "Built from source"
    end

    s << "using the formulae.brew.sh API" if loaded_from_api
    s << Time.at(time).strftime("on %Y-%m-%d at %H:%M:%S") if time

    unless used_options.empty?
      s << "with:"
      s << used_options.to_a.join(" ")
    end
    s.join(" ")
  end
end
