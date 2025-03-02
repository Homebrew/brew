# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

require "resource"
require "download_strategy"
require "checksum"
require "version"
require "options"
require "build_options"
require "dependency_collector"
require "utils/bottles"
require "patch"
require "compilers"
require "macos_version"
require "extend/on_system"

class SoftwareSpec
  include Downloadable

  extend Forwardable
  include OnSystem::MacOSAndLinux

  PREDEFINED_OPTIONS = {
    universal: Option.new("universal", "Build a universal binary"),
    cxx11:     Option.new("c++11",     "Build using C++11 mode"),
  }.freeze

  attr_reader :name, :full_name, :owner, :build, :resources, :patches, :options, :deprecated_flags,
              :deprecated_options, :dependency_collector, :bottle_specification, :compiler_failures

  def_delegators :@resource, :stage, :fetch, :verify_download_integrity, :source_modified_time, :download_name,
                 :cached_download, :clear_cache, :checksum, :mirrors, :specs, :using, :version, :mirror,
                 :downloader

  def_delegators :@resource, :sha256

  def initialize(flags: [])
    super()

    # Ensure this is synced with `initialize_dup` and `freeze` (excluding simple objects like integers and booleans)
    @resource = Resource::Formula.new
    @resources = {}
    @dependency_collector = DependencyCollector.new
    @bottle_specification = BottleSpecification.new
    @patches = []
    @options = Options.new
    @flags = flags
    @deprecated_flags = []
    @deprecated_options = []
    @build = BuildOptions.new(Options.create(@flags), options)
    @compiler_failures = []
  end

  def initialize_dup(other)
    super
    @resource = @resource.dup
    @resources = @resources.dup
    @dependency_collector = @dependency_collector.dup
    @bottle_specification = @bottle_specification.dup
    @patches = @patches.dup
    @options = @options.dup
    @flags = @flags.dup
    @deprecated_flags = @deprecated_flags.dup
    @deprecated_options = @deprecated_options.dup
    @build = @build.dup
    @compiler_failures = @compiler_failures.dup
  end

  def freeze
    @resource.freeze
    @resources.freeze
    @dependency_collector.freeze
    @bottle_specification.freeze
    @patches.freeze
    @options.freeze
    @flags.freeze
    @deprecated_flags.freeze
    @deprecated_options.freeze
    @build.freeze
    @compiler_failures.freeze
    super
  end

  sig { override.returns(String) }
  def download_type
    "formula"
  end

  def owner=(owner)
    @name = owner.name
    @full_name = owner.full_name
    @bottle_specification.tap = owner.tap
    @owner = owner
    @resource.owner = self
    resources.each_value do |r|
      r.owner = self
      next if r.version
      next if version.nil?

      r.version(version.head? ? Version.new("HEAD") : version.dup)
    end
    patches.each { |p| p.owner = self }
  end

  def url(val = nil, specs = {})
    return @resource.url if val.nil?

    @resource.url(val, **specs)
    dependency_collector.add(@resource)
  end

  def bottle_defined?
    !bottle_specification.collector.tags.empty?
  end

  def bottle_tag?(tag = nil)
    bottle_specification.tag?(Utils::Bottles.tag(tag))
  end

  def bottled?(tag = nil)
    bottle_tag?(tag) &&
      (tag.present? || bottle_specification.compatible_locations? || owner.force_bottle)
  end

  def bottle(&block)
    bottle_specification.instance_eval(&block)
  end

  def resource_defined?(name)
    resources.key?(name)
  end

  sig {
    params(name: String, klass: T.class_of(Resource), block: T.nilable(T.proc.bind(Resource).void))
      .returns(T.nilable(Resource))
  }
  def resource(name = T.unsafe(nil), klass = Resource, &block)
    if block
      raise ArgumentError, "Resource must have a name." if name.nil?
      raise DuplicateResourceError, name if resource_defined?(name)

      res = klass.new(name, &block)
      return unless res.url

      resources[name] = res
      dependency_collector.add(res)
      res
    else
      return @resource if name.nil?

      resources.fetch(name) { raise ResourceMissingError.new(owner, name) }
    end
  end

  def go_resource(name, &block)
    odisabled "`SoftwareSpec#go_resource`", "Go modules"
    resource name, Resource::Go, &block
  end

  def option_defined?(name)
    options.include?(name)
  end

  def option(name, description = "")
    opt = PREDEFINED_OPTIONS.fetch(name) do
      unless name.is_a?(String)
        raise ArgumentError, "option name must be string or symbol; got a #{name.class}: #{name}"
      end
      raise ArgumentError, "option name is required" if name.empty?
      raise ArgumentError, "option name must be longer than one character: #{name}" if name.length <= 1
      raise ArgumentError, "option name must not start with dashes: #{name}" if name.start_with?("-")

      Option.new(name, description)
    end
    options << opt
  end

  def deprecated_option(hash)
    raise ArgumentError, "deprecated_option hash must not be empty" if hash.empty?

    hash.each do |old_options, new_options|
      Array(old_options).each do |old_option|
        Array(new_options).each do |new_option|
          deprecated_option = DeprecatedOption.new(old_option, new_option)
          deprecated_options << deprecated_option

          old_flag = deprecated_option.old_flag
          new_flag = deprecated_option.current_flag
          next unless @flags.include? old_flag

          @flags -= [old_flag]
          @flags |= [new_flag]
          @deprecated_flags << deprecated_option
        end
      end
    end
    @build = BuildOptions.new(Options.create(@flags), options)
  end

  def depends_on(spec)
    dep = dependency_collector.add(spec)
    add_dep_option(dep) if dep
  end

  sig {
    params(
      dep:    T.any(String, T::Hash[T.any(String, Symbol), T.any(Symbol, T::Array[Symbol])]),
      bounds: T::Hash[Symbol, Symbol],
    ).void
  }
  def uses_from_macos(dep, bounds = {})
    if dep.is_a?(Hash)
      bounds = dep.dup
      dep, tags = bounds.shift
      dep = T.cast(dep, String)
      tags = [*tags]
      bounds = T.cast(bounds, T::Hash[Symbol, Symbol])
    else
      tags = []
    end

    depends_on UsesFromMacOSDependency.new(dep, tags, bounds:)
  end

  def deps
    dependency_collector.deps.dup_without_system_deps
  end

  def declared_deps
    dependency_collector.deps
  end

  def recursive_dependencies
    deps_f = []
    recursive_dependencies = deps.filter_map do |dep|
      deps_f << dep.to_formula
      dep
    rescue TapFormulaUnavailableError
      # Don't complain about missing cross-tap dependencies
      next
    end.uniq
    deps_f.compact.each do |f|
      f.recursive_dependencies.each do |dep|
        recursive_dependencies << dep unless recursive_dependencies.include?(dep)
      end
    end
    recursive_dependencies
  end

  def requirements
    dependency_collector.requirements
  end

  def recursive_requirements
    Requirement.expand(self)
  end

  def patch(strip = :p1, src = nil, &block)
    p = Patch.create(strip, src, &block)
    return if p.is_a?(ExternalPatch) && p.url.blank?

    dependency_collector.add(p.resource) if p.is_a? ExternalPatch
    patches << p
  end

  def fails_with(compiler, &block)
    compiler_failures << CompilerFailure.create(compiler, &block)
  end

  def needs(*standards)
    standards.each do |standard|
      compiler_failures.concat CompilerFailure.for_standard(standard)
    end
  end

  def add_dep_option(dep)
    dep.option_names.each do |name|
      if dep.optional? && !option_defined?("with-#{name}")
        options << Option.new("with-#{name}", "Build with #{name} support")
      elsif dep.recommended? && !option_defined?("without-#{name}")
        options << Option.new("without-#{name}", "Build without #{name} support")
      end
    end
  end
end
