# typed: strict
# frozen_string_literal: true

require "unpack_strategy"

class Bottle
  include Downloadable

  class Filename
    sig { returns(String) }
    attr_reader :name, :tag

    sig { returns(PkgVersion) }
    attr_reader :version

    sig { returns(Integer) }
    attr_reader :rebuild

    sig { params(formula: Formula, tag: Utils::Bottles::Tag, rebuild: Integer).returns(T.attached_class) }
    def self.create(formula, tag, rebuild)
      new(formula.name, formula.pkg_version, tag, rebuild)
    end

    sig { params(name: String, version: PkgVersion, tag: Utils::Bottles::Tag, rebuild: Integer).void }
    def initialize(name, version, tag, rebuild)
      @name = T.let(File.basename(name), String)

      raise ArgumentError, "Invalid bottle name" unless Utils.safe_filename?(@name)
      raise ArgumentError, "Invalid bottle version" unless Utils.safe_filename?(version.to_s)

      @version = version
      @tag = T.let(tag.to_unstandardized_sym.to_s, String)
      @rebuild = rebuild
    end

    sig { returns(String) }
    def to_str
      "#{name}--#{version}#{extname}"
    end

    sig { returns(String) }
    def to_s = to_str

    sig { returns(String) }
    def json
      "#{name}--#{version}.#{tag}.bottle.json"
    end

    sig { returns(String) }
    def url_encode
      ERB::Util.url_encode("#{name}-#{version}#{extname}")
    end

    sig { returns(String) }
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

  sig { returns(String) }
  attr_reader :name

  sig { returns(Resource) }
  attr_reader :resource

  sig { returns(Utils::Bottles::Tag) }
  attr_reader :tag

  sig { returns(T.any(String, Symbol)) }
  attr_reader :cellar

  sig { returns(Integer) }
  attr_reader :rebuild

  def_delegators :resource, :url, :verify_download_integrity
  def_delegators :resource, :cached_download, :downloader

  sig {
    params(
      formula:     T.nilable(Formula),
      spec:        BottleSpecification,
      tag:         T.nilable(Utils::Bottles::Tag),
      name:        T.nilable(String),
      pkg_version: T.nilable(PkgVersion),
    ).void
  }
  def initialize(formula, spec, tag = nil, name: nil, pkg_version: nil)
    super()

    resource_name = T.let(nil, T.nilable(String))
    if formula
      name = formula.name
      pkg_version = formula.pkg_version
    else
      raise ArgumentError, "Bottle name is required" if name.nil?
      raise ArgumentError, "Bottle version is required" if pkg_version.nil?

      resource_name = name
    end

    @name = T.let(name, String)
    @pkg_version = T.let(pkg_version, PkgVersion)
    @resource = T.let(Resource.new(resource_name), Resource)
    @resource.owner = formula if formula
    @spec = spec

    tag_spec = spec.tag_specification_for(Utils::Bottles.tag(tag))

    odie "#{@name} tag specification for tag #{tag} is nil" if tag_spec.nil?

    @tag = T.let(tag_spec.tag, Utils::Bottles::Tag)
    @cellar = T.let(tag_spec.cellar, T.any(String, Symbol))
    @rebuild = T.let(spec.rebuild, Integer)

    @resource.version(@pkg_version.to_s)
    @resource.checksum = tag_spec.checksum

    @fetch_tab_retried = T.let(false, T::Boolean)

    root_url(spec.root_url, spec.root_url_specs)
  end

  sig {
    override.params(
      verify_download_integrity: T::Boolean,
      timeout:                   T.nilable(T.any(Integer, Float)),
      quiet:                     T::Boolean,
    ).returns(Pathname)
  }
  def fetch(verify_download_integrity: true, timeout: nil, quiet: false)
    resource.fetch(verify_download_integrity:, timeout:, quiet:)
  rescue DownloadError
    raise unless fallback_on_error?

    fetch_tab
    retry
  end

  sig { override.returns(T::Boolean) }
  def downloaded_and_valid?
    return false unless cached_download.file?

    resource_checksum = resource.checksum
    return false if resource_checksum.nil?

    downloader = resource.downloader
    return false unless downloader.is_a?(CurlGitHubPackagesDownloadStrategy)
    return false unless downloader.immutable_bottle_blob?

    downloader.bottle_blob_sha256 == resource_checksum.hexdigest
  end

  sig { override.returns(T.nilable(Integer)) }
  def total_size
    bottle_size || super
  end

  sig { override.void }
  def clear_cache
    @resource.clear_cache
    github_packages_manifest_resource&.clear_cache
    @fetch_tab_retried = false
  end

  sig { returns(T::Boolean) }
  def compatible_locations?
    @spec.compatible_locations?(tag: @tag)
  end

  # Does the bottle need to be relocated?
  sig { returns(T::Boolean) }
  def skip_relocation?
    attrs = tab_attributes
    tab = Tab.new(attrs) unless attrs.empty?
    @spec.skip_relocation?(tag: @tag, tab:)
  end

  sig { void }
  def stage = downloader.stage

  sig { params(timeout: T.nilable(T.any(Integer, Float)), quiet: T::Boolean).void }
  def fetch_tab(timeout: nil, quiet: false)
    return unless (resource = github_packages_manifest_resource)

    begin
      resource.fetch(timeout:, quiet:)
    rescue DownloadError
      raise unless fallback_on_error?

      retry
    rescue Resource::BottleManifest::Error
      raise if @fetch_tab_retried

      @fetch_tab_retried = true
      resource.clear_cache
      retry
    end
  end

  sig { returns(T::Hash[String, T.untyped]) }
  def tab_attributes
    if (resource = github_packages_manifest_resource) && resource.downloaded?
      return resource.tab
    end

    {}
  end

  sig { returns(T.nilable(Integer)) }
  def bottle_size
    resource = github_packages_manifest_resource
    return unless resource&.downloaded?

    resource.bottle_size
  end

  sig { returns(T.nilable(Integer)) }
  def installed_size
    resource = github_packages_manifest_resource
    return unless resource&.downloaded?

    resource.installed_size
  end

  sig { returns(T.nilable(T::Array[String])) }
  def path_exec_files
    resource = github_packages_manifest_resource
    return unless resource&.downloaded?

    resource.path_exec_files
  end

  sig { returns(T.nilable(T::Hash[String, Object])) }
  def sbom_supplement
    resource = github_packages_manifest_resource
    return unless resource&.downloaded_and_valid?

    resource.sbom_supplement
  end

  sig { returns(Filename) }
  def filename = Filename.new(@name, @pkg_version, @tag, @spec.rebuild)

  sig { returns(Pathname) }
  def staged_path_from_download_queue
    bottle_filename = filename
    HOMEBREW_TEMP_CELLAR/bottle_filename.name/bottle_filename.version.to_s
  end

  sig { returns(Pathname) }
  def staged_path_from_download_queue_marker
    Pathname("#{staged_path_from_download_queue}.poured")
  end

  sig { override.params(_download: Pathname, pour: T::Boolean).returns(T::Boolean) }
  def stage_from_download_queue?(_download, pour:)
    pour
  end

  sig { override.params(download: Pathname, pour: T::Boolean).void }
  def stage_from_download_queue(download, pour:)
    return unless pour

    bottle_tmp_keg = staged_path_from_download_queue
    bottle_poured_file = staged_path_from_download_queue_marker

    begin
      HOMEBREW_TEMP_CELLAR.mkpath

      return if bottle_poured_file.exist?

      FileUtils.rm(bottle_poured_file) if bottle_poured_file.symlink?
      FileUtils.rm_r(bottle_tmp_keg) if bottle_tmp_keg.directory?

      UnpackStrategy.detect(download, prioritize_extension: true)
                    .extract_nestedly(to: HOMEBREW_TEMP_CELLAR)

      # Create a separate file to mark a completed extraction. This avoids
      # a potential race condition if a user interrupts the install.
      # We use a symlink to easily check that both this extra status file
      # and the real extracted directory exist via `Pathname#exist?`.
      FileUtils.ln_s(bottle_tmp_keg, bottle_poured_file)
    # Catch any exception type here to clean up partial queued extractions.
    rescue Exception # rubocop:disable Lint/RescueException
      ignore_interrupts do
        FileUtils.rm_r(bottle_tmp_keg) if bottle_tmp_keg.directory?
        bottle_tmp_keg.parent.rmdir_if_possible
      end
      raise
    end
  end

  sig { returns(T.nilable(Resource::BottleManifest)) }
  def github_packages_manifest_resource
    return if @resource.download_strategy != CurlGitHubPackagesDownloadStrategy

    @github_packages_manifest_resource ||= T.let(
      begin
        resource = Resource::BottleManifest.new(self)

        resource_version = @resource.version
        odie "resource version is nil" if resource_version.nil?

        version_rebuild = GitHubPackages.version_rebuild(resource_version, rebuild)
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
      end,
      T.nilable(Resource::BottleManifest),
    )
  end

  sig { override.returns(String) }
  def download_queue_type = "Bottle"

  sig { override.returns(String) }
  def download_queue_name = "#{name} (#{resource.version})"

  private

  sig { params(specs: T::Hash[Symbol, T.anything]).returns(T::Hash[Symbol, T.anything]) }
  def select_download_strategy(specs)
    odie "cannot select download strategy for #{name} because root_url is nil" if @root_url.nil?
    specs[:using] ||= DownloadStrategyDetector.detect(@root_url)
    specs[:bottle] = true
    specs
  end

  sig { returns(T::Boolean) }
  def fallback_on_error?
    # Use the default bottle domain as a fallback mirror
    if @resource.url&.start_with?(Homebrew::EnvConfig.bottle_domain) &&
       Homebrew::EnvConfig.bottle_domain != HOMEBREW_BOTTLE_DEFAULT_DOMAIN
      opoo "Bottle missing, falling back to the default domain..."
      root_url(HOMEBREW_BOTTLE_DEFAULT_DOMAIN)
      @github_packages_manifest_resource = T.let(nil, T.nilable(Resource::BottleManifest))
      true
    else
      false
    end
  end

  sig { params(val: T.nilable(String), specs: T::Hash[Symbol, T.anything]).returns(T.nilable(String)) }
  def root_url(val = nil, specs = {})
    return @root_url if val.nil?

    @root_url = T.let(val, T.nilable(String))

    filename = self.filename
    resource_checksum = resource.checksum
    odie "resource checksum is nil" if resource_checksum.nil?

    path, resolved_basename = Utils::Bottles.path_resolved_basename(val, name, resource_checksum, filename)
    @resource.url("#{val}/#{path}", **select_download_strategy(specs))
    return unless resolved_basename.present?

    downloader = @resource.downloader
    return unless downloader.is_a?(CurlGitHubPackagesDownloadStrategy)

    downloader.resolved_basename = resolved_basename
  end
end
