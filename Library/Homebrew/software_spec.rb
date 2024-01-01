# typed: true
# frozen_string_literal: true

require "attrable"
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
    # Ensure this is synced with `initialize_dup` and `freeze` (excluding simple objects like integers and booleans)
    @resource = Resource.new
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
    @uses_from_macos_elements = []
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
    @uses_from_macos_elements = @uses_from_macos_elements.dup
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
    @uses_from_macos_elements.freeze
    super
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

      raise "#{full_name}: version missing for \"#{r.name}\" resource!" if version.nil?

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

  def resource(name, klass = Resource, &block)
    if block
      raise DuplicateResourceError, name if resource_defined?(name)

      res = klass.new(name, &block)
      return unless res.url

      resources[name] = res
      dependency_collector.add(res)
    else
      resources.fetch(name) { raise ResourceMissingError.new(owner, name) }
    end
  end

  def go_resource(name, &block)
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

  def uses_from_macos(deps, bounds = {})
    if deps.is_a?(Hash)
      bounds = deps.dup
      deps = [bounds.shift].to_h
    end

    spec, tags = deps.is_a?(Hash) ? deps.first : deps
    raise TypeError, "Dependency name must be a string!" unless spec.is_a?(String)

    @uses_from_macos_elements << deps

    depends_on UsesFromMacOSDependency.new(spec, Array(tags), bounds: bounds)
  end

  # @deprecated
  def uses_from_macos_elements
    # TODO: remove all @uses_from_macos_elements when removing this method
    # Also remember to remove the delegate from formula.rb
    odisabled "#uses_from_macos_elements", "#declared_deps"
    @uses_from_macos_elements
  end

  # @deprecated
  def uses_from_macos_names
    # TODO: Remember to remove the delegate from formula.rb
    odisabled "#uses_from_macos_names", "#declared_deps"
    uses_from_macos_elements.flat_map { |e| e.is_a?(Hash) ? e.keys : e }
  end

  def deps
    dependency_collector.deps.dup_without_system_deps
  end

  def declared_deps
    dependency_collector.deps
  end

  def recursive_dependencies
    deps_f = []
    recursive_dependencies = deps.map do |dep|
      deps_f << dep.to_formula
      dep
    rescue TapFormulaUnavailableError
      # Don't complain about missing cross-tap dependencies
      next
    end.compact.uniq
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

class HeadSoftwareSpec < SoftwareSpec
  def initialize(flags: [])
    super
    @resource.version(Version.new("HEAD"))
  end

  def verify_download_integrity(_filename)
    # no-op
  end
end

class Bottle
  class Filename
    attr_reader :name, :version, :tag, :rebuild

    sig { params(formula: Formula, tag: Utils::Bottles::Tag, rebuild: Integer).returns(T.attached_class) }
    def self.create(formula, tag, rebuild)
      new(formula.name, formula.pkg_version, tag, rebuild)
    end

    sig { params(name: String, version: PkgVersion, tag: Utils::Bottles::Tag, rebuild: Integer).void }
    def initialize(name, version, tag, rebuild)
      @name = File.basename name

      raise ArgumentError, "Invalid bottle name" unless Utils.safe_filename?(@name)
      raise ArgumentError, "Invalid bottle version" unless Utils.safe_filename?(version.to_s)

      @version = version
      @tag = tag.to_s
      @rebuild = rebuild
    end

    sig { returns(String) }
    def to_s
      "#{name}--#{version}#{extname}"
    end
    alias to_str to_s

    sig { returns(String) }
    def json
      "#{name}--#{version}.#{tag}.bottle.json"
    end

    def url_encode
      ERB::Util.url_encode("#{name}-#{version}#{extname}")
    end

    def github_packages
      "#{name}--#{version}#{extname}"
    end

    sig { returns(String) }
    def extname
      s = rebuild.positive? ? ".#{rebuild}" : ""
      ".#{tag}.bottle#{s}.tar.gz"
    end
  end

  extend Forwardable

  attr_reader :name, :resource, :cellar, :rebuild

  def_delegators :resource, :url, :verify_download_integrity
  def_delegators :resource, :cached_download

  def initialize(formula, spec, tag = nil)
    @name = formula.name
    @resource = Resource.new
    @resource.owner = formula
    @spec = spec

    tag_spec = spec.tag_specification_for(Utils::Bottles.tag(tag))

    @tag = tag_spec.tag
    @cellar = tag_spec.cellar
    @rebuild = spec.rebuild

    @resource.version(formula.pkg_version.to_s)
    @resource.checksum = tag_spec.checksum

    @fetch_tab_retried = false

    root_url(spec.root_url, spec.root_url_specs)
  end

  def fetch(verify_download_integrity: true)
    @resource.fetch(verify_download_integrity: verify_download_integrity)
  rescue DownloadError
    raise unless fallback_on_error

    fetch_tab
    retry
  end

  def clear_cache
    @resource.clear_cache
    github_packages_manifest_resource&.clear_cache
    @fetch_tab_retried = false
  end

  def compatible_locations?
    @spec.compatible_locations?(tag: @tag)
  end

  # Does the bottle need to be relocated?
  def skip_relocation?
    @spec.skip_relocation?(tag: @tag)
  end

  def stage
    resource.downloader.stage
  end

  def fetch_tab
    return if github_packages_manifest_resource.blank?

    # a checksum is used later identifying the correct tab but we do not have the checksum for the manifest/tab
    github_packages_manifest_resource.fetch(verify_download_integrity: false)

    begin
      github_packages_manifest_resource_tab(github_packages_manifest_resource)
    rescue RuntimeError => e
      raise DownloadError.new(github_packages_manifest_resource, e)
    end
  rescue DownloadError
    raise unless fallback_on_error

    retry
  rescue ArgumentError
    raise if @fetch_tab_retried

    @fetch_tab_retried = true
    github_packages_manifest_resource.clear_cache
    retry
  end

  def tab_attributes
    return {} unless github_packages_manifest_resource&.downloaded?

    github_packages_manifest_resource_tab(github_packages_manifest_resource)
  end

  private

  def github_packages_manifest_resource_tab(github_packages_manifest_resource)
    manifest_json = github_packages_manifest_resource.cached_download.read

    json = begin
      JSON.parse(manifest_json)
    rescue JSON::ParserError
      raise "The downloaded GitHub Packages manifest was corrupted or modified (it is not valid JSON): " \
            "\n#{github_packages_manifest_resource.cached_download}"
    end

    manifests = json["manifests"]
    raise ArgumentError, "Missing 'manifests' section." if manifests.blank?

    manifests_annotations = manifests.map { |m| m["annotations"] }.compact
    raise ArgumentError, "Missing 'annotations' section." if manifests_annotations.blank?

    bottle_digest = @resource.checksum.hexdigest
    image_ref = GitHubPackages.version_rebuild(@resource.version, rebuild, @tag.to_s)
    manifest_annotations = manifests_annotations.find do |m|
      next if m["sh.brew.bottle.digest"] != bottle_digest

      m["org.opencontainers.image.ref.name"] == image_ref
    end
    raise ArgumentError, "Couldn't find manifest matching bottle checksum." if manifest_annotations.blank?

    tab = manifest_annotations["sh.brew.tab"]
    raise ArgumentError, "Couldn't find tab from manifest." if tab.blank?

    begin
      JSON.parse(tab)
    rescue JSON::ParserError
      raise ArgumentError, "Couldn't parse tab JSON."
    end
  end

  def github_packages_manifest_resource
    return if @resource.download_strategy != CurlGitHubPackagesDownloadStrategy

    @github_packages_manifest_resource ||= begin
      resource = Resource.new("#{name}_bottle_manifest")

      version_rebuild = GitHubPackages.version_rebuild(@resource.version, rebuild)
      resource.version(version_rebuild)

      image_name = GitHubPackages.image_formula_name(@name)
      image_tag = GitHubPackages.image_version_rebuild(version_rebuild)
      resource.url(
        "#{root_url}/#{image_name}/manifests/#{image_tag}",
        using:   CurlGitHubPackagesDownloadStrategy,
        headers: ["Accept: application/vnd.oci.image.index.v1+json"],
      )
      T.cast(resource.downloader, CurlGitHubPackagesDownloadStrategy).resolved_basename =
        "#{name}-#{version_rebuild}.bottle_manifest.json"
      resource
    end
  end

  def select_download_strategy(specs)
    specs[:using] ||= DownloadStrategyDetector.detect(@root_url)
    specs[:bottle] = true
    specs
  end

  def fallback_on_error
    # Use the default bottle domain as a fallback mirror
    if @resource.url.start_with?(Homebrew::EnvConfig.bottle_domain) &&
       Homebrew::EnvConfig.bottle_domain != HOMEBREW_BOTTLE_DEFAULT_DOMAIN
      opoo "Bottle missing, falling back to the default domain..."
      root_url(HOMEBREW_BOTTLE_DEFAULT_DOMAIN)
      @github_packages_manifest_resource = nil
      true
    else
      false
    end
  end

  def root_url(val = nil, specs = {})
    return @root_url if val.nil?

    @root_url = val

    filename = Filename.create(resource.owner, @tag, @spec.rebuild)
    path, resolved_basename = Utils::Bottles.path_resolved_basename(val, name, resource.checksum, filename)
    @resource.url("#{val}/#{path}", **select_download_strategy(specs))
    @resource.downloader.resolved_basename = resolved_basename if resolved_basename.present?
  end
end

class BottleSpecification
  extend Attrable
  RELOCATABLE_CELLARS = [:any, :any_skip_relocation].freeze

  attr_rw :rebuild
  attr_accessor :tap
  attr_reader :collector, :root_url_specs, :repository

  sig { void }
  def initialize
    @rebuild = 0
    @repository = Homebrew::DEFAULT_REPOSITORY
    @collector = Utils::Bottles::Collector.new
    @root_url_specs = {}
  end

  def root_url(var = nil, specs = {})
    if var.nil?
      @root_url ||= if (github_packages_url = GitHubPackages.root_url_if_match(Homebrew::EnvConfig.bottle_domain))
        github_packages_url
      else
        Homebrew::EnvConfig.bottle_domain
      end
    else
      @root_url = if (github_packages_url = GitHubPackages.root_url_if_match(var))
        github_packages_url
      else
        var
      end
      @root_url_specs.merge!(specs)
    end
  end

  def ==(other)
    self.class == other.class && rebuild == other.rebuild && collector == other.collector &&
      root_url == other.root_url && root_url_specs == other.root_url_specs && tap == other.tap
  end
  alias eql? ==

  sig { params(tag: Utils::Bottles::Tag).returns(T.any(Symbol, String)) }
  def tag_to_cellar(tag = Utils::Bottles.tag)
    spec = collector.specification_for(tag)
    if spec.present?
      spec.cellar
    else
      tag.default_cellar
    end
  end

  sig { params(tag: Utils::Bottles::Tag).returns(T::Boolean) }
  def compatible_locations?(tag: Utils::Bottles.tag)
    cellar = tag_to_cellar(tag)

    return true if RELOCATABLE_CELLARS.include?(cellar)

    prefix = Pathname(cellar.to_s).parent.to_s

    cellar_relocatable = cellar.size >= HOMEBREW_CELLAR.to_s.size && ENV["HOMEBREW_RELOCATE_BUILD_PREFIX"].present?
    prefix_relocatable = prefix.size >= HOMEBREW_PREFIX.to_s.size && ENV["HOMEBREW_RELOCATE_BUILD_PREFIX"].present?

    compatible_cellar = cellar == HOMEBREW_CELLAR.to_s || cellar_relocatable
    compatible_prefix = prefix == HOMEBREW_PREFIX.to_s || prefix_relocatable

    compatible_cellar && compatible_prefix
  end

  # Does the {Bottle} this {BottleSpecification} belongs to need to be relocated?
  sig { params(tag: Utils::Bottles::Tag).returns(T::Boolean) }
  def skip_relocation?(tag: Utils::Bottles.tag)
    spec = collector.specification_for(tag)
    spec&.cellar == :any_skip_relocation
  end

  sig { params(tag: T.any(Symbol, Utils::Bottles::Tag), no_older_versions: T::Boolean).returns(T::Boolean) }
  def tag?(tag, no_older_versions: false)
    collector.tag?(tag, no_older_versions: no_older_versions)
  end

  # Checksum methods in the DSL's bottle block take
  # a Hash, which indicates the platform the checksum applies on.
  # Example bottle block syntax:
  # bottle do
  #  sha256 cellar: :any_skip_relocation, big_sur: "69489ae397e4645..."
  #  sha256 cellar: :any, catalina: "449de5ea35d0e94..."
  # end
  def sha256(hash)
    sha256_regex = /^[a-f0-9]{64}$/i

    # find new `sha256 big_sur: "69489ae397e4645..."` format
    tag, digest = hash.find do |key, value|
      key.is_a?(Symbol) && value.is_a?(String) && value.match?(sha256_regex)
    end

    cellar = hash[:cellar] if digest && tag

    tag = Utils::Bottles::Tag.from_symbol(tag)

    cellar ||= tag.default_cellar

    collector.add(tag, checksum: Checksum.new(digest), cellar: cellar)
  end

  sig {
    params(tag: Utils::Bottles::Tag, no_older_versions: T::Boolean)
      .returns(T.nilable(Utils::Bottles::TagSpecification))
  }
  def tag_specification_for(tag, no_older_versions: false)
    collector.specification_for(tag, no_older_versions: no_older_versions)
  end

  def checksums
    tags = collector.tags.sort_by do |tag|
      version = tag.to_macos_version
      # Give arm64 bottles a higher priority so they are first
      priority = (tag.arch == :arm64) ? "2" : "1"
      "#{priority}.#{version}_#{tag}"
    rescue MacOSVersion::Error
      # Sort non-MacOS tags below MacOS tags.
      "0.#{tag}"
    end
    tags.reverse.map do |tag|
      spec = collector.specification_for(tag)
      {
        "tag"    => spec.tag.to_sym,
        "digest" => spec.checksum,
        "cellar" => spec.cellar,
      }
    end
  end
end

class PourBottleCheck
  include OnSystem::MacOSAndLinux

  def initialize(formula)
    @formula = formula
  end

  def reason(reason)
    @formula.pour_bottle_check_unsatisfied_reason = reason
  end

  def satisfy(&block)
    @formula.send(:define_method, :pour_bottle?, &block)
  end
end

require "extend/os/software_spec"
