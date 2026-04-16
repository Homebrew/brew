# typed: strict
# frozen_string_literal: true

require "downloadable"
require "formula_creator"
require "mktemp"
require "livecheck"
require "on_system"
require "utils/output"

# Resource is the fundamental representation of an external resource. The
# primary formula download, along with other declared resources, are instances
# of this class.
class Resource
  include Downloadable
  include FileUtils
  include OnSystem::MacOSAndLinux
  include Utils::Output::Mixin

  Owner = T.type_alias { T.any(Cask::Cask, ::Formula, Resource, SoftwareSpec, Homebrew::FormulaCreator) }

  sig { returns(T.nilable(Time)) }
  attr_reader :source_modified_time

  sig { returns(T::Array[T.any(EmbeddedPatch, ExternalPatch)]) }
  attr_reader :patches

  sig { returns(T.nilable(Owner)) }
  attr_reader :owner

  sig { params(checksum: T.nilable(Checksum)).returns(T.nilable(Checksum)) }
  attr_writer :checksum

  sig { override.returns(T::Class[AbstractDownloadStrategy]) }
  def download_strategy
    @download_strategy || super
  end

  sig { params(download_strategy: T.nilable(T::Class[AbstractDownloadStrategy])).void }
  attr_writer :download_strategy

  # Formula name must be set after the DSL, as we have no access to the
  # formula name before initialization of the formula.
  sig { returns(T.nilable(String)) }
  attr_accessor :name

  sig { params(name: T.nilable(String), block: T.nilable(T.proc.bind(Resource).void)).void }
  def initialize(name = nil, &block)
    super()
    # Generally ensure this is synced with `initialize_dup` and `freeze`
    # (excluding simple objects like integers & booleans, weak refs like `owner` or permafrozen objects)
    @name = T.let(name, T.nilable(String))
    @source_modified_time = T.let(nil, T.nilable(Time))
    @patches = T.let([], T::Array[T.any(EmbeddedPatch, ExternalPatch)])
    @owner = T.let(nil, T.nilable(Owner))
    @livecheck = T.let(Livecheck.new(self), Livecheck)
    @livecheck_defined = T.let(false, T::Boolean)
    @insecure = T.let(false, T::Boolean)
    instance_eval(&block) if block
  end

  sig { override.params(other: T.any(Resource, Downloadable)).void }
  def initialize_dup(other)
    super
    @name = @name.dup
    @patches = @patches.dup
    @livecheck = @livecheck.dup
  end

  sig { override.returns(T.self_type) }
  def freeze
    @name.freeze
    @patches.freeze
    @livecheck.freeze
    super
  end

  sig { params(owner: T.nilable(Owner)).void }
  def owner=(owner)
    @owner = T.let(owner, T.nilable(Owner))
    patches.each { |p| p.owner = owner }
  end

  sig { override.returns(String) }
  def download_queue_type = "Resource"

  # Verifies download and unpacks it.
  # The block may call `|resource, staging| staging.retain!` to retain the staging
  # directory. Subclasses that override stage should implement the tmp
  # dir using {Mktemp} so that works with all subtypes.
  #
  # @api public
  sig {
    params(
      target:        T.nilable(T.any(String, Pathname)),
      debug_symbols: T::Boolean,
      block:         T.nilable(T.proc.params(arg0: ResourceStageContext).void),
    ).void
  }
  def stage(target = nil, debug_symbols: false, &block)
    raise ArgumentError, "Target directory or block is required" if !target && !block_given?

    prepare_patches
    fetch_patches(skip_downloaded: true)
    fetch unless downloaded?

    unpack(target, debug_symbols:, &block)
  end

  sig { void }
  def prepare_patches
    patches.grep(DATAPatch) { |p| p.path = T.cast(T.cast(T.must(owner), SoftwareSpec).owner, ::Formula).path }
  end

  sig { params(skip_downloaded: T::Boolean).void }
  def fetch_patches(skip_downloaded: false)
    external_patches = patches.grep(ExternalPatch)
    external_patches.reject!(&:downloaded?) if skip_downloaded
    external_patches.each(&:fetch)
  end

  sig { void }
  def apply_patches
    return if patches.empty?

    ohai "Patching #{name}"
    patches.each(&:apply)
  end

  # If a target is given, unpack there; else unpack to a temp folder.
  # If block is given, yield to that block with `|stage|`, where stage
  # is a {ResourceStageContext}.
  # A target or a block must be given, but not both.
  sig {
    params(
      target:        T.nilable(T.any(String, Pathname)),
      debug_symbols: T::Boolean,
      block:         T.nilable(T.proc.params(arg0: ResourceStageContext).void),
    ).void
  }
  def unpack(target = nil, debug_symbols: false, &block)
    current_working_directory = Pathname.pwd
    stage_resource(download_name, debug_symbols:) do |staging|
      downloader.stage do
        @source_modified_time = downloader.source_modified_time.freeze
        apply_patches
        if block
          yield(ResourceStageContext.new(self, staging))
        elsif target
          target = Pathname(target)
          target = current_working_directory/target if target.relative?
          target.install Pathname.pwd.children
        end
      end
    end
  end

  Partial = Struct.new(:resource, :files)

  sig { params(files: T.untyped).returns(Partial) }
  def files(*files)
    Partial.new(self, files)
  end

  sig {
    override
      .params(
        verify_download_integrity: T::Boolean,
        timeout:                   T.nilable(T.any(Integer, Float)),
        quiet:                     T::Boolean,
        skip_patches:              T::Boolean,
      ).returns(Pathname)
  }
  def fetch(verify_download_integrity: true, timeout: nil, quiet: false, skip_patches: false)
    fetch_patches unless skip_patches

    super(verify_download_integrity:, timeout:, quiet:)
  end

  # {Livecheck} can be used to check for newer versions of the software.
  # This method evaluates the DSL specified in the `livecheck` block of the
  # {Resource} (if it exists) and sets the instance variables of a {Livecheck}
  # object accordingly. This is used by `brew livecheck` to check for newer
  # versions of the software.
  #
  # ### Example
  #
  # ```ruby
  # livecheck do
  #   url "https://example.com/foo/releases"
  #   regex /foo-(\d+(?:\.\d+)+)\.tar/
  # end
  # ```
  sig { params(block: T.nilable(T.proc.bind(Livecheck).void)).returns(T.untyped) }
  def livecheck(&block)
    return @livecheck unless block

    @livecheck_defined = true
    @livecheck.instance_eval(&block)
  end

  # Whether a livecheck specification is defined or not.
  #
  # It returns `true` when a `livecheck` block is present in the {Resource}
  # and `false` otherwise.
  sig { returns(T::Boolean) }
  def livecheck_defined?
    @livecheck_defined == true
  end

  sig { params(val: String).returns(Checksum) }
  def sha256(val)
    @checksum = Checksum.new(val)
  end

  sig { override.params(val: T.nilable(String), specs: T.anything).returns(T.nilable(String)) }
  def url(val = nil, **specs)
    return @url&.to_s if val.nil?

    specs = specs.dup
    # Don't allow this to be set.
    specs.delete(:insecure)

    specs[:insecure] = true if @insecure

    @url = URL.new(val, specs)
    @downloader = nil
    @download_strategy = @url.download_strategy
    @url.to_s
  end

  sig { override.params(val: T.nilable(T.any(String, Version))).returns(T.nilable(Version)) }
  def version(val = nil)
    return super() if val.nil?

    @version = case val
    when String
      val.blank? ? Version::NULL : Version.new(val)
    when Version
      val
    end
  end

  sig { params(val: String).returns(T::Array[String]) }
  def mirror(val)
    mirrors << val
  end

  sig {
    params(
      strip: T.any(Symbol, String),
      src:   T.nilable(T.any(Symbol, String)),
      block: T.nilable(T.proc.bind(Resource::Patch).void),
    ).returns(T::Array[T.any(EmbeddedPatch, ExternalPatch)])
  }
  def patch(strip = :p1, src = nil, &block)
    p = ::Patch.create(strip, src, &block)
    patches << p
  end

  sig { returns(T.nilable(T.any(T::Class[AbstractDownloadStrategy], Symbol))) }
  def using
    @url&.using
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def specs
    @url&.specs || {}.freeze
  end

  protected

  sig {
    type_parameters(:U)
      .params(
        prefix:        String,
        debug_symbols: T::Boolean,
        block:         T.proc.params(arg0: Mktemp).returns(T.type_parameter(:U)),
      ).returns(T.type_parameter(:U))
  }
  def stage_resource(prefix, debug_symbols: false, &block)
    Mktemp.new(prefix, retain_in_cache: debug_symbols).run(&block)
  end

  private

  sig { override.returns(String) }
  def download_name
    owner_name = owner&.name
    resource_name = name
    if resource_name.nil?
      raise "Resource name and owner name are both nil" if owner_name.nil?

      owner_name
    else
      # Removes /s from resource names; this allows Go package names
      # to be used as resource names without confusing software that
      # interacts with {download_name}, e.g. `github.com/foo/bar`.
      escaped_name = resource_name.tr("/", "-")
      owner_name ? "#{owner_name}--#{escaped_name}" : escaped_name
    end
  end

  sig { override.returns(T::Array[String]) }
  def determine_url_mirrors
    extra_urls = []
    url = T.must(self.url)

    # glibc-bootstrap
    if url.start_with?("https://github.com/Homebrew/glibc-bootstrap/releases/download")
      if (artifact_domain = Homebrew::EnvConfig.artifact_domain.presence)
        artifact_url = url.sub("https://github.com", artifact_domain)
        return [artifact_url] if Homebrew::EnvConfig.artifact_domain_no_fallback?

        extra_urls << artifact_url
      end

      if Homebrew::EnvConfig.bottle_domain != HOMEBREW_BOTTLE_DEFAULT_DOMAIN
        tag, filename = url.split("/").last(2)
        extra_urls << "#{Homebrew::EnvConfig.bottle_domain}/glibc-bootstrap/#{tag}/#{filename}"
      end
    end

    # PyPI packages: PEP 503 – Simple Repository API <https://peps.python.org/pep-0503>
    if (pip_index_url = Homebrew::EnvConfig.pip_index_url.presence)
      pip_index_base_url = pip_index_url.chomp("/").chomp("/simple")
      %w[https://files.pythonhosted.org https://pypi.org].each do |base_url|
        extra_urls << url.sub(base_url, pip_index_base_url) if url.start_with?("#{base_url}/packages")
      end
    end

    [*extra_urls, *super].uniq
  end

  # A local resource that doesn't need to be downloaded.
  class Local < Resource
    sig { params(path: String).void }
    def initialize(path)
      super(File.basename(path))
      @downloader = T.let(LocalBottleDownloadStrategy.new(Pathname(path)), LocalBottleDownloadStrategy)
    end
  end

  # A resource for a formula.
  class Formula < Resource
    sig { override.returns(String) }
    def download_queue_type = "Formula"

    sig { override.returns(String) }
    def download_queue_name = "#{T.must(owner).name} (#{version})"
  end

  # A resource containing a Go package.
  class Go < Resource
    # This is a legacy override that should be refactored for compatibility with the parent class.
    # rubocop:disable Sorbet/AllowIncompatibleOverride
    sig {
      override(allow_incompatible: true).params(
        target: Pathname,
        block:  T.nilable(T.proc.params(arg0: ResourceStageContext).void),
      ).void
    }
    # rubocop:enable Sorbet/AllowIncompatibleOverride
    def stage(target, &block)
      resource_name = name
      raise "Resource name is nil" if resource_name.nil?

      super(target/resource_name, &block)
    end
  end

  # A resource for a bottle manifest.
  class BottleManifest < Resource
    class Error < RuntimeError; end

    sig { returns(Bottle) }
    attr_reader :bottle

    sig { params(bottle: Bottle).void }
    def initialize(bottle)
      super("#{bottle.name}_bottle_manifest")
      @bottle = bottle
      @manifest_annotations = T.let(nil, T.nilable(T::Hash[String, T.untyped]))
    end

    sig { override.params(_filename: Pathname).void }
    def verify_download_integrity(_filename)
      # We don't have a checksum, but we can at least try parsing it.
      tab
    end

    sig { returns(T::Hash[String, T.untyped]) }
    def tab
      tab = manifest_annotations["sh.brew.tab"]
      raise Error, "Couldn't find tab from manifest." if tab.blank?

      begin
        JSON.parse(tab)
      rescue JSON::ParserError
        raise Error, "Couldn't parse tab JSON."
      end
    end

    sig { returns(T.nilable(Integer)) }
    def bottle_size
      manifest_annotations["sh.brew.bottle.size"]&.to_i
    end

    sig { returns(T.nilable(Integer)) }
    def installed_size
      manifest_annotations["sh.brew.bottle.installed_size"]&.to_i
    end

    sig { override.returns(String) }
    def download_queue_type = "Bottle Manifest"

    sig { override.returns(String) }
    def download_queue_name = "#{bottle.name} (#{bottle.resource.version})"

    private

    sig { returns(T::Hash[String, T.untyped]) }
    def manifest_annotations
      cached = @manifest_annotations
      return cached unless cached.nil?

      json = begin
        JSON.parse(cached_download.read)
      rescue JSON::ParserError
        raise Error, "The downloaded GitHub Packages manifest was corrupted or modified (it is not valid JSON): " \
                     "\n#{cached_download}"
      end

      manifests = json["manifests"]
      raise Error, "Missing 'manifests' section." if manifests.blank?

      manifests_annotations = manifests.filter_map { |m| m["annotations"] }
      raise Error, "Missing 'annotations' section." if manifests_annotations.blank?

      checksum = bottle.resource.checksum
      raise "Checksum is nil" if checksum.nil?

      bottle_digest = checksum.hexdigest
      version = bottle.resource.version
      raise "Version is nil" if version.nil?

      image_ref = GitHubPackages.version_rebuild(version, bottle.rebuild, bottle.tag.to_s)
      manifests_annotation = manifests_annotations.find do |m|
        next if m["sh.brew.bottle.digest"] != bottle_digest

        m["org.opencontainers.image.ref.name"] == image_ref
      end
      raise Error, "Couldn't find manifest matching bottle checksum." if manifests_annotation.blank?

      @manifest_annotations = manifests_annotation
    end
  end

  # A resource containing a patch.
  class Patch < Resource
    sig { returns(T::Array[T.any(String, Pathname)]) }
    attr_reader :patch_files

    sig { params(block: T.nilable(T.proc.bind(Resource::Patch).void)).void }
    def initialize(&block)
      @patch_files = T.let([], T::Array[T.any(String, Pathname)])
      @directory = T.let(nil, T.nilable(T.any(String, Pathname)))
      super "patch", &block
    end

    sig { params(paths: T.any(String, Pathname, T::Array[T.any(String, Pathname)])).void }
    def apply(*paths)
      @patch_files.concat(paths.flatten)
      @patch_files.uniq!
    end

    sig { params(val: T.nilable(T.any(String, Pathname))).returns(T.nilable(T.any(String, Pathname))) }
    def directory(val = nil)
      return @directory if val.nil?

      @directory = val
    end

    sig { override.returns(String) }
    def download_queue_type = "Patch"

    sig { override.returns(String) }
    def download_queue_name
      if (last_url_component = url.to_s.split("/").last)
        return last_url_component
      end

      super
    end
  end
end

# The context in which a {Resource#stage} occurs. Supports access to both
# the {Resource} and associated {Mktemp} in a single block argument. The interface
# is back-compatible with {Resource} itself as used in that context.
class ResourceStageContext # rubocop:todo Style/OneClassPerFile
  extend Forwardable

  # The {Resource} that is being staged.
  sig { returns(Resource) }
  attr_reader :resource

  # The {Mktemp} in which {#resource} is staged.
  sig { returns(Mktemp) }
  attr_reader :staging

  def_delegators :@resource, :version, :url, :mirrors, :specs, :using, :source_modified_time
  def_delegators :@staging, :retain!

  sig { params(resource: Resource, staging: Mktemp).void }
  def initialize(resource, staging)
    @resource = T.let(resource, Resource)
    @staging = T.let(staging, Mktemp)
  end

  sig { returns(String) }
  def to_s
    "<#{self.class}: resource=#{resource} staging=#{staging}>"
  end
end
