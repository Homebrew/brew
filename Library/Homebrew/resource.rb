# typed: true
# frozen_string_literal: true

require "downloadable"
require "mktemp"
require "livecheck"
require "extend/on_system"

# Resource is the fundamental representation of an external resource. The
# primary formula download, along with other declared resources, are instances
# of this class.
#
# @api private
class Resource < Downloadable
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
    @livecheckable = false
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

    return if !owner.respond_to?(:full_name) || owner.full_name != "ca-certificates"
    return if Homebrew::EnvConfig.no_insecure_redirect?

    @insecure = !specs[:bottle] && (DevelopmentTools.ca_file_substitution_required? ||
                                    DevelopmentTools.curl_substitution_required?)
    return if @url.nil?

    specs = if @insecure
      @url.specs.merge({ insecure: true })
    else
      @url.specs.except(:insecure)
    end
    @url = URL.new(@url.to_s, specs)
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
    raise ArgumentError, "Target directory or block is required" if !target && block.blank?

    prepare_patches
    fetch_patches(skip_downloaded: true)
    fetch unless downloaded?

    unpack(target, debug_symbols: debug_symbols, &block)
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
    stage_resource(download_name, debug_symbols: debug_symbols) do |staging|
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

  def fetch(verify_download_integrity: true)
    fetch_patches

    super(verify_download_integrity: verify_download_integrity)
  end

  # @!attribute [w] livecheck
  # {Livecheck} can be used to check for newer versions of the software.
  # This method evaluates the DSL specified in the livecheck block of the
  # {Resource} (if it exists) and sets the instance variables of a {Livecheck}
  # object accordingly. This is used by `brew livecheck` to check for newer
  # versions of the software.
  #
  # <pre>livecheck do
  #   url "https://example.com/foo/releases"
  #   regex /foo-(\d+(?:\.\d+)+)\.tar/
  # end</pre>
  def livecheck(&block)
    return @livecheck unless block

    @livecheckable = true
    @livecheck.instance_eval(&block)
  end

  # Whether a livecheck specification is defined or not.
  # It returns true when a livecheck block is present in the {Resource} and
  # false otherwise, and is used by livecheck.
  def livecheckable?
    @livecheckable == true
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

  sig { params(val: T.nilable(T.any(String, Version))).returns(T.nilable(Version)) }
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
    p = Patch.create(strip, src, &block)
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
        extra_urls << url.sub("https://github.com", artifact_domain)
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

  # A resource containing a Go package.
  class Go < Resource
    def stage(target, &block)
      super(target/name, &block)
    end
  end

  # A resource containing a patch.
  class PatchResource < Resource
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
#
# @api private
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
