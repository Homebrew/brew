# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

require "downloadable"
require "mktemp"
require "livecheck"
require "extend/on_system"

# Resource is the fundamental representation of an external resource. The
# primary formula download, along with other declared resources, are instances
# of this class.
class Resource
  include Downloadable
  include FileUtils
  include OnSystem::MacOSAndLinux

  attr_reader :source_modified_time, :patches, :owner
  attr_writer :checksum
  attr_accessor :download_strategy

  # Formula name must be set after the DSL, as we have no access to the
  # formula name before initialization of the formula.
  attr_accessor :name

  sig { params(name: T.nilable(String), block: T.nilable(T.proc.bind(Resource).void)).void }
  def initialize(name = nil, &block)
    super()
    # Ensure this is synced with `initialize_dup` and `freeze` (excluding simple objects like integers and booleans)
    @name = name
    @patches = []
    @livecheck = Livecheck.new(self)
    @livecheck_defined = false
    @insecure = false
    instance_eval(&block) if block
  end

  def initialize_dup(other)
    super
    @name = @name.dup
    @patches = @patches.dup
    @livecheck = @livecheck.dup
  end

  def freeze
    @name.freeze
    @patches.freeze
    @livecheck.freeze
    super
  end

  def owner=(owner)
    @owner = owner
    patches.each { |p| p.owner = owner }
  end

  # Removes /s from resource names; this allows Go package names
  # to be used as resource names without confusing software that
  # interacts with {download_name}, e.g. `github.com/foo/bar`.
  def escaped_name
    name.tr("/", "-")
  end

  def download_name
    return owner.name if name.nil?
    return escaped_name if owner.nil?

    "#{owner.name}--#{escaped_name}"
  end

  # Verifies download and unpacks it.
  # The block may call `|resource, staging| staging.retain!` to retain the staging
  # directory. Subclasses that override stage should implement the tmp
  # dir using {Mktemp} so that works with all subtypes.
  #
  # @api public
  def stage(target = nil, debug_symbols: false, &block)
    raise ArgumentError, "Target directory or block is required" if !target && !block_given?

    prepare_patches
    fetch_patches(skip_downloaded: true)
    fetch unless downloaded?

    unpack(target, debug_symbols:, &block)
  end

  def prepare_patches
    patches.grep(DATAPatch) { |p| p.path = owner.owner.path }
  end

  def fetch_patches(skip_downloaded: false)
    external_patches = patches.select(&:external?)
    external_patches.reject!(&:downloaded?) if skip_downloaded
    external_patches.each(&:fetch)
  end

  def apply_patches
    return if patches.empty?

    ohai "Patching #{name}"
    patches.each(&:apply)
  end

  # If a target is given, unpack there; else unpack to a temp folder.
  # If block is given, yield to that block with `|stage|`, where stage
  # is a {ResourceStageContext}.
  # A target or a block must be given, but not both.
  def unpack(target = nil, debug_symbols: false)
    current_working_directory = Pathname.pwd
    stage_resource(download_name, debug_symbols:) do |staging|
      downloader.stage do
        @source_modified_time = downloader.source_modified_time
        apply_patches
        if block_given?
          yield ResourceStageContext.new(self, staging)
        elsif target
          target = Pathname(target)
          target = current_working_directory/target if target.relative?
          target.install Pathname.pwd.children
        end
      end
    end
  end

  Partial = Struct.new(:resource, :files)

  def files(*files)
    Partial.new(self, files)
  end

  sig {
    override
      .params(
        verify_download_integrity: T::Boolean,
        timeout:                   T.nilable(T.any(Integer, Float)),
        quiet:                     T::Boolean,
      ).returns(Pathname)
  }
  def fetch(verify_download_integrity: true, timeout: nil, quiet: false)
    fetch_patches

    super
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

  # Whether a livecheck specification is defined or not. This is a legacy alias
  # for `#livecheck_defined?`.
  #
  # It returns `true` when a `livecheck` block is present in the {Resource}
  # and `false` otherwise.
  sig { returns(T::Boolean) }
  def livecheckable?
    # odeprecated "`livecheckable?`", "`livecheck_defined?`"
    @livecheck_defined == true
  end

  def sha256(val)
    @checksum = Checksum.new(val)
  end

  def url(val = nil, **specs)
    return @url&.to_s if val.nil?

    specs = specs.dup
    # Don't allow this to be set.
    specs.delete(:insecure)

    specs[:insecure] = true if @insecure

    @url = URL.new(val, specs)
    @downloader = nil
    @download_strategy = @url.download_strategy
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

  def mirror(val)
    mirrors << val
  end

  def patch(strip = :p1, src = nil, &block)
    p = ::Patch.create(strip, src, &block)
    patches << p
  end

  def using
    @url&.using
  end

  def specs
    @url&.specs || {}.freeze
  end

  protected

  def stage_resource(prefix, debug_symbols: false, &block)
    Mktemp.new(prefix, retain_in_cache: debug_symbols).run(&block)
  end

  private

  def determine_url_mirrors
    extra_urls = []

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
    def initialize(path)
      super(File.basename(path))
      @downloader = LocalBottleDownloadStrategy.new(path)
    end
  end

  # A resource for a formula.
  class Formula < Resource
    sig { override.returns(String) }
    def name
      T.must(owner).name
    end

    sig { override.returns(String) }
    def download_name
      name
    end
  end

  # A resource containing a Go package.
  class Go < Resource
    def stage(target, &block)
      super(target/name, &block)
    end
  end

  # A resource for a bottle manifest.
  class BottleManifest < Resource
    class Error < RuntimeError; end

    attr_reader :bottle

    def initialize(bottle)
      super("#{bottle.name}_bottle_manifest")
      @bottle = bottle
      @manifest_annotations = nil
    end

    def verify_download_integrity(_filename)
      # We don't have a checksum, but we can at least try parsing it.
      tab
    end

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

    private

    def manifest_annotations
      return @manifest_annotations unless @manifest_annotations.nil?

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

      bottle_digest = bottle.resource.checksum.hexdigest
      image_ref = GitHubPackages.version_rebuild(bottle.resource.version, bottle.rebuild, bottle.tag.to_s)
      manifest_annotations = manifests_annotations.find do |m|
        next if m["sh.brew.bottle.digest"] != bottle_digest

        m["org.opencontainers.image.ref.name"] == image_ref
      end
      raise Error, "Couldn't find manifest matching bottle checksum." if manifest_annotations.blank?

      @manifest_annotations = manifest_annotations
    end
  end

  # A resource containing a patch.
  class Patch < Resource
    attr_reader :patch_files

    def initialize(&block)
      @patch_files = []
      @directory = nil
      super "patch", &block
    end

    def apply(*paths)
      paths.flatten!
      @patch_files.concat(paths)
      @patch_files.uniq!
    end

    def directory(val = nil)
      return @directory if val.nil?

      @directory = val
    end
  end
end

# The context in which a {Resource#stage} occurs. Supports access to both
# the {Resource} and associated {Mktemp} in a single block argument. The interface
# is back-compatible with {Resource} itself as used in that context.
class ResourceStageContext
  extend Forwardable

  # The {Resource} that is being staged.
  attr_reader :resource

  # The {Mktemp} in which {#resource} is staged.
  attr_reader :staging

  def_delegators :@resource, :version, :url, :mirrors, :specs, :using, :source_modified_time
  def_delegators :@staging, :retain!

  def initialize(resource, staging)
    @resource = resource
    @staging = staging
  end

  sig { returns(String) }
  def to_s
    "<#{self.class}: resource=#{resource} staging=#{staging}>"
  end
end
