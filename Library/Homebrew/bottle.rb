# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

class Bottle
  include Downloadable

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
      @tag = tag.to_unstandardized_sym.to_s
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

  attr_reader :name, :resource, :tag, :cellar, :rebuild

  def_delegators :resource, :url, :verify_download_integrity
  def_delegators :resource, :cached_download, :downloader

  def initialize(formula, spec, tag = nil)
    super()

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

  sig {
    override.params(
      verify_download_integrity: T::Boolean,
      timeout:                   T.nilable(T.any(Integer, Float)),
      quiet:                     T.nilable(T::Boolean),
    ).returns(Pathname)
  }
  def fetch(verify_download_integrity: true, timeout: nil, quiet: false)
    resource.fetch(verify_download_integrity:, timeout:, quiet:)
  rescue DownloadError
    raise unless fallback_on_error?

    fetch_tab
    retry
  end

  sig { override.void }
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

  def stage = downloader.stage

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

  sig { returns(Filename) }
  def filename
    Filename.create(resource.owner, @tag, @spec.rebuild)
  end

  sig { returns(T.nilable(Resource::BottleManifest)) }
  def github_packages_manifest_resource
    return if @resource.download_strategy != CurlGitHubPackagesDownloadStrategy

    @github_packages_manifest_resource ||= begin
      resource = Resource::BottleManifest.new(self)

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

  private

  def select_download_strategy(specs)
    specs[:using] ||= DownloadStrategyDetector.detect(@root_url)
    specs[:bottle] = true
    specs
  end

  def fallback_on_error?
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
