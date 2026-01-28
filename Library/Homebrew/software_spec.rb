# typed: strict
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
require "on_system"

class SoftwareSpec
  include Downloadable

  extend Forwardable
  include OnSystem::MacOSAndLinux

  sig { returns(T.nilable(String)) }
  attr_reader :name

  sig { returns(T.nilable(String)) }
  attr_reader :full_name

  sig { returns(T.nilable(T.any(Formula, Cask::Cask))) }
  attr_reader :owner

  sig { returns(BuildOptions) }
  attr_reader :build

  sig { returns(T::Hash[String, Resource]) }
  attr_reader :resources

  sig { returns(T::Array[T.any(EmbeddedPatch, ExternalPatch)]) }
  attr_reader :patches

  sig { returns(Options) }
  attr_reader :options

  sig { returns(T::Array[DeprecatedOption]) }
  attr_reader :deprecated_flags

  sig { returns(T::Array[DeprecatedOption]) }
  attr_reader :deprecated_options

  sig { returns(DependencyCollector) }
  attr_reader :dependency_collector

  sig { returns(BottleSpecification) }
  attr_reader :bottle_specification

  sig { returns(T::Array[CompilerFailure]) }
  attr_reader :compiler_failures

  def_delegators :@resource, :stage, :fetch, :verify_download_integrity, :source_modified_time,
                 :cached_download, :clear_cache, :checksum, :mirrors, :specs, :using, :version, :mirror,
                 :downloader, :download_queue_name, :download_queue_type

  def_delegators :@resource, :sha256

  sig { params(flags: T::Array[String]).void }
  def initialize(flags: [])
    super()

    @name = T.let(nil, T.nilable(String))
    @full_name = T.let(nil, T.nilable(String))
    @owner = T.let(nil, T.nilable(T.any(Formula, Cask::Cask)))

    # Ensure this is synced with `initialize_dup` and `freeze` (excluding simple objects like integers and booleans)
    @resource = T.let(Resource::Formula.new, Resource::Formula)
    @resources = T.let({}, T::Hash[String, Resource])
    @dependency_collector = T.let(DependencyCollector.new, DependencyCollector)
    @bottle_specification = T.let(BottleSpecification.new, BottleSpecification)
    @patches = T.let([], T::Array[T.any(EmbeddedPatch, ExternalPatch)])
    @options = T.let(Options.new, Options)
    @flags = flags
    @deprecated_flags = T.let([], T::Array[DeprecatedOption])
    @deprecated_options = T.let([], T::Array[DeprecatedOption])
    @build = T.let(BuildOptions.new(Options.create(@flags), options), BuildOptions)
    @compiler_failures = T.let([], T::Array[CompilerFailure])
  end

  sig { override.params(other: T.any(SoftwareSpec, Downloadable)).void }
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

  sig { override.returns(T.self_type) }
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

  sig { params(owner: T.any(Formula, Cask::Cask)).void }
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

  sig { override.params(val: T.nilable(String), specs: T::Hash[Symbol, T.anything]).returns(T.nilable(String)) }
  def url(val = nil, specs = {})
    if val
      @resource.url(val, **specs)
      dependency_collector.add(@resource)
    end
    @resource.url
  end

  sig { returns(T::Boolean) }
  def bottle_defined?
    !bottle_specification.collector.tags.empty?
  end

  sig { params(tag: T.nilable(T.any(Utils::Bottles::Tag, Symbol))).returns(T::Boolean) }
  def bottle_tag?(tag = nil)
    bottle_specification.tag?(Utils::Bottles.tag(tag))
  end

  sig { params(tag: T.nilable(T.any(Utils::Bottles::Tag, Symbol))).returns(T::Boolean) }
  def bottled?(tag = nil)
    return false unless bottle_tag?(tag)

    return true if tag.present?
    return true if bottle_specification.compatible_locations?

    owner = self.owner
    return false unless owner.is_a?(Formula)

    owner.force_bottle
  end

  sig { params(block: T.proc.bind(BottleSpecification).void).void }
  def bottle(&block)
    bottle_specification.instance_eval(&block)
  end

  sig { params(name: String).returns(T::Boolean) }
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

  sig { params(name: T.any(Option, String)).returns(T::Boolean) }
  def option_defined?(name)
    options.include?(name)
  end

  sig { params(name: String, description: String).void }
  def option(name, description = "")
    raise ArgumentError, "option name is required" if name.empty?
    raise ArgumentError, "option name must be longer than one character: #{name}" if name.length <= 1
    raise ArgumentError, "option name must not start with dashes: #{name}" if name.start_with?("-")

    options << Option.new(name, description)
  end

  sig { params(hash: T::Hash[T.any(String, T::Array[String]), T.any(String, T::Array[String])]).void }
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

  sig { params(spec: T.any(String, Symbol, T::Hash[T.any(String, Symbol, T::Class[Requirement]), T.untyped], T::Class[Requirement], Dependable)).void }
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

  sig { returns(Dependencies) }
  def deps
    dependency_collector.deps.dup_without_system_deps
  end

  sig { returns(Dependencies) }
  def declared_deps
    dependency_collector.deps
  end

  sig { returns(T::Array[Dependable]) }
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

  sig { returns(Requirements) }
  def requirements
    dependency_collector.requirements
  end

  sig { returns(Requirements) }
  def recursive_requirements
    Requirement.expand(self)
  end

  sig {
    params(strip: T.any(Symbol, String), src: T.nilable(T.any(String, Symbol)),
           block: T.nilable(T.proc.bind(Patch).void)).void
  }
  def patch(strip = :p1, src = T.unsafe(nil), &block)
    p = Patch.create(strip, src, &block)
    return if p.is_a?(ExternalPatch) && p.url.blank?

    dependency_collector.add(p.resource) if p.is_a? ExternalPatch
    patches << p
  end

  sig { params(compiler: T.any(T::Hash[Symbol, String], Symbol), block: T.nilable(T.proc.bind(CompilerFailure).void)).void }
  def fails_with(compiler, &block)
    compiler_failures << CompilerFailure.create(compiler, &block)
  end

  sig { params(dep: Dependable).void }
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
