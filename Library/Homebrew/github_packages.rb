# typed: strict
# frozen_string_literal: true

require "utils/executable"

require "utils/curl"
require "utils/gzip"
require "utils/output"
require "json"
require "zlib"
require "extend/hash/keys"
require "system_command"

# GitHub Packages client.
class GitHubPackages
  include Context
  include SystemCommand::Mixin
  include Utils::Output::Mixin

  URL_DOMAIN = "ghcr.io"
  URL_PREFIX = T.let("https://#{URL_DOMAIN}/v2/".freeze, String)
  DOCKER_PREFIX = T.let("docker://#{URL_DOMAIN}/".freeze, String)
  public_constant :URL_DOMAIN
  private_constant :URL_PREFIX
  private_constant :DOCKER_PREFIX

  class Downloads < T::Struct
    const :source, String
    const :all_time, Integer
    const :last_30_days, Integer
    const :start_date, String
    const :end_date, String
    const :fetched_at, String
  end

  # GitHub's package overview includes exact totals and daily chart values.
  # Cache successful snapshots per UTC day for CLI and API generation callers.
  sig { params(formula_name: String).returns(T.nilable(Downloads)) }
  def self.downloads(formula_name)
    cache = HOMEBREW_CACHE/"github-packages-downloads/#{formula_name}.json"
    if cache.exist?
      begin
        cached = Downloads.from_hash(JSON.parse(cache.read))
        return cached if cached.fetched_at.start_with?(Time.now.utc.strftime("%F"))
      rescue JSON::ParserError, TypeError, ArgumentError
        nil
      end
    end

    url = "https://github.com/Homebrew/homebrew-core/pkgs/container/core%2F" \
          "#{image_formula_name(formula_name).gsub("/", "%2F")}"
    output = Utils::Curl.curl_output("--fail", "--compressed", url)
    return unless output.success?

    total = output.stdout[%r{Total downloads</span>\s*<h3[^>]*title="(\d+)"}, 1]
    chart = output.stdout[%r{aria-label="Downloads for the last 30 days">.*?</svg>}m]
    return if total.nil? || chart.nil?

    bars = chart.scan(/<rect\b[^>]*>/m).flatten
    daily = bars.filter_map do |bar|
      date = bar[/\bdata-date="(\d{4}-\d{2}-\d{2})"/, 1]
      count = bar[/\bdata-merge-count="(\d+)"/, 1]
      next if date.nil? || count.nil?

      [date, count.to_i]
    end.to_h
    return if daily.empty? || daily.length != bars.length

    dates = daily.keys.sort
    downloads = Downloads.new(source: url, all_time: total.to_i, last_30_days: daily.values.sum,
                              start_date: dates.fetch(0), end_date: dates.fetch(-1), fetched_at: Time.now.utc.iso8601)
    cache.dirname.mkpath
    cache.atomic_write(JSON.generate(downloads.serialize))
    downloads
  end

  URL_REGEX = %r{(?:#{Regexp.escape(URL_PREFIX)}|#{Regexp.escape(DOCKER_PREFIX)})([\w-]+)/([\w-]+)}

  # Valid OCI tag characters
  # https://github.com/opencontainers/distribution-spec/blob/main/spec.md#workflow-categories
  VALID_OCI_TAG_REGEX = /^[a-zA-Z0-9_][a-zA-Z0-9._-]{0,127}$/

  # Translate Homebrew tab.arch to OCI platform.architecture
  TAB_ARCH_TO_PLATFORM_ARCHITECTURE = T.let(
    {
      "arm64"  => "arm64",
      "x86_64" => "amd64",
    }.freeze,
    T::Hash[String, String],
  )

  # Translate Homebrew built_on.os to OCI platform.os
  BUILT_ON_OS_TO_PLATFORM_OS = T.let(
    {
      "Linux"     => "linux",
      "Macintosh" => "darwin",
    }.freeze,
    T::Hash[String, String],
  )

  # An image built from a formula's bottles, ready to upload.
  class Image < T::Struct
    const :root, Pathname
    const :uri, String
    const :package_url, String
    const :index_sha256, String
    # The image index on GitHub Packages when this image was built, which `--keep-old` adds to.
    const :base_index_sha256, T.nilable(String)
  end

  # Builds every image before uploading any. The block is given the SHA-256 of
  # each image index by formula name, which is what a bottle block's
  # `manifest_sha256` pins, so they can be committed before they are uploaded.
  sig {
    params(
      bottles_hash:  T::Hash[String, T.untyped],
      keep_old:      T::Boolean,
      dry_run:       T::Boolean,
      warn_on_error: T::Boolean,
      _block:        T.nilable(T.proc.params(manifest_sha256s: T::Hash[String, String]).void),
    ).void
  }
  def upload_bottles(bottles_hash, keep_old:, dry_run:, warn_on_error:, &_block)
    user = Homebrew::EnvConfig.github_packages_user
    token = Homebrew::EnvConfig.github_packages_token

    raise UsageError, "HOMEBREW_GITHUB_PACKAGES_USER is unset." if user.blank?
    raise UsageError, "HOMEBREW_GITHUB_PACKAGES_TOKEN is unset." if token.blank?

    skopeo = Utils::Executable.ensure!("skopeo", reason: "upload")

    require "json_schemer"

    load_schemas!

    # First, check and build them all so that we won't encounter an error in
    # the middle of uploading bottles.
    images = bottles_hash.to_h do |formula_full_name, bottle_hash|
      [formula_full_name,
       build_image(user, token, skopeo, formula_full_name, bottle_hash, keep_old:, dry_run:, warn_on_error:)]
    end.compact

    yield images.transform_values(&:index_sha256) if block_given?

    bottle_count = bottles_hash.count
    bottles_hash.each_with_index do |(formula_full_name, bottle_hash), index|
      # We run the preupload check again to prevent TOCTOU bugs. A bottle block may now
      # pin this image, so failing this check is an error and never only a warning.
      if (image = images[formula_full_name]) &&
         (result = preupload_check(user, token, skopeo, formula_full_name, bottle_hash,
                                   keep_old:, dry_run:, warn_on_error: false))
        # Uploading would remove any bottles added to the image index since this image was built.
        odie "#{image.uri} changed while its image was being built!" if result.last != image.base_index_sha256

        upload_image(user, token, skopeo, image, dry_run:)
      end
      next if bottle_count < 3

      uploaded_count = index + 1
      ohai "Upload progress: #{uploaded_count} formula(e) uploaded, #{bottle_count - uploaded_count} remaining"
    end
  end

  sig { params(version: Version, rebuild: Integer, bottle_tag: T.nilable(String)).returns(String) }
  def self.version_rebuild(version, rebuild, bottle_tag = nil)
    bottle_tag = (".#{bottle_tag}" if bottle_tag.present?)

    rebuild = if rebuild.positive?
      if bottle_tag
        ".#{rebuild}"
      else
        "-#{rebuild}"
      end
    end

    "#{version}#{bottle_tag}#{rebuild}"
  end

  sig { params(repo: String).returns(String) }
  def self.repo_without_prefix(repo)
    # Remove redundant repository prefix for a shorter name.
    repo.delete_prefix("homebrew-")
  end

  sig { params(org: String, repo: String, prefix: String).returns(String) }
  def self.root_url(org, repo, prefix = URL_PREFIX)
    # `docker`/`skopeo` insist on lowercase organisation (“repository name”).
    org = org.downcase

    "#{prefix}#{org}/#{repo_without_prefix(repo)}"
  end

  sig { params(url: T.nilable(String)).returns(T.nilable(String)) }
  def self.root_url_if_match(url)
    return if url.blank?

    _, org, repo, = *url.to_s.match(URL_REGEX)
    return if org.blank? || repo.blank?

    root_url(org, repo)
  end

  sig { params(formula_name: String).returns(String) }
  def self.image_formula_name(formula_name)
    # Invalid docker name characters:
    # - `/` makes sense because we already use it to separate repository/formula.
    # - `x` makes sense because we already use it in `Formulary`.
    formula_name.tr("@", "/")
                .tr("+", "x")
  end

  sig { params(version_rebuild: String).returns(String) }
  def self.image_version_rebuild(version_rebuild)
    unless version_rebuild.match?(VALID_OCI_TAG_REGEX)
      raise ArgumentError, "GitHub Packages versions must match #{VALID_OCI_TAG_REGEX.source}!"
    end

    version_rebuild
  end

  sig {
    params(
      user: String, token: String, skopeo: Pathname, formula_full_name: String,
      bottle_hash: T::Hash[String, T.untyped], keep_old: T::Boolean, dry_run: T::Boolean, warn_on_error: T::Boolean
    ).returns(T.nilable(Image))
  }
  def build_image(user, token, skopeo, formula_full_name, bottle_hash, keep_old:, dry_run:, warn_on_error:)
    result = preupload_check(user, token, skopeo, formula_full_name, bottle_hash,
                             keep_old:, dry_run:, warn_on_error:)
    # Skip upload if preupload check returned early.
    return if result.nil?

    formula_name, org, repo, version, rebuild, version_rebuild, image_name, image_uri, keep_old,
    base_index_sha256 = *result

    # Formulae in different taps can share a name and version.
    root = Pathname("#{formula_full_name}--#{version_rebuild}")
    FileUtils.rm_rf root
    root.mkpath

    if keep_old
      download(user, token, skopeo, image_uri, root, dry_run:)
    else
      image_layout = { imageLayoutVersion: "1.0.0" }
      validate_schema!(IMAGE_LAYOUT_SCHEMA_URI, image_layout)
      write_hash(root, image_layout, "oci-layout")
    end

    blobs = root/"blobs/sha256"
    blobs.mkpath

    git_path = bottle_hash["formula"]["tap_git_path"]
    git_revision = bottle_hash["formula"]["tap_git_revision"]

    source_org_repo = "#{org}/#{repo}"
    source = "https://github.com/#{source_org_repo}/blob/#{git_revision.presence || "HEAD"}/#{git_path}"

    formula_core_tap = formula_full_name.exclude?("/")
    documentation = if formula_core_tap
      "https://formulae.brew.sh/formula/#{formula_name}"
    elsif (remote = bottle_hash["formula"]["tap_git_remote"]) && remote.start_with?("https://github.com/")
      remote
    end

    license = bottle_hash["formula"]["license"].to_s
    created_date = bottle_hash["bottle"]["date"]
    if keep_old
      index = JSON.parse((root/"index.json").read)
      image_index_sha256 = index["manifests"].first["digest"].delete_prefix("sha256:")
      image_index = JSON.parse((blobs/image_index_sha256).read)
      (blobs/image_index_sha256).unlink

      formula_annotations_hash = image_index["annotations"]
      manifests = image_index["manifests"]
    else
      require "utils/spdx"
      image_license = SPDX.truncate_license(license)

      formula_annotations_hash = {
        "com.github.package.type"                => GITHUB_PACKAGE_TYPE,
        "org.opencontainers.image.created"       => created_date,
        "org.opencontainers.image.description"   => bottle_hash["formula"]["desc"],
        "org.opencontainers.image.documentation" => documentation,
        "org.opencontainers.image.licenses"      => image_license,
        "org.opencontainers.image.ref.name"      => version_rebuild,
        "org.opencontainers.image.revision"      => git_revision,
        "org.opencontainers.image.source"        => source,
        "org.opencontainers.image.title"         => formula_full_name,
        "org.opencontainers.image.url"           => bottle_hash["formula"]["homepage"],
        "org.opencontainers.image.vendor"        => org,
        "org.opencontainers.image.version"       => version.to_s, # Schema accepts strings for version
      }.compact_blank
      manifests = []
    end

    processed_image_refs = Set.new
    manifests.each do |manifest|
      processed_image_refs << manifest["annotations"]["org.opencontainers.image.ref.name"]
    end

    require "sbom"

    manifests += bottle_hash["bottle"]["tags"].map do |bottle_tag, tag_hash|
      bottle_tag = Utils::Bottles::Tag.from_symbol(bottle_tag.to_sym)
      all_bottle = bottle_tag.to_sym == :all

      tag = GitHubPackages.version_rebuild(version, rebuild, bottle_tag.to_s)

      if processed_image_refs.include?(tag)
        puts
        odie "A bottle JSON for #{bottle_tag} is present, but it is already in the image index!"
      else
        processed_image_refs << tag
      end

      local_file = tag_hash["local_filename"]
      odebug "Uploading #{local_file}"

      tar_gz_sha256 = Digest::SHA256.file(local_file).hexdigest
      FileUtils.ln local_file, blobs/tar_gz_sha256, force: true

      tab = tag_hash["tab"]
      architecture = TAB_ARCH_TO_PLATFORM_ARCHITECTURE[tab["arch"].presence || bottle_tag.standardized_arch.to_s]
      raise TypeError, "unknown tab['arch']: #{tab["arch"]}" if architecture.blank?

      os = if tab["built_on"].present? && tab["built_on"]["os"].present?
        BUILT_ON_OS_TO_PLATFORM_OS[tab["built_on"]["os"]]
      elsif bottle_tag.linux?
        "linux"
      else
        "darwin"
      end
      raise TypeError, "unknown tab['built_on']['os']: #{tab["built_on"]["os"]}" if os.blank?

      os_version = tab["built_on"]["os_version"].presence if tab["built_on"].present?
      case os
      when "darwin"
        os_version ||= "macOS #{bottle_tag.to_macos_version}"
      when "linux"
        os_version&.delete_suffix!(" LTS")
        os_version ||= OS::LINUX_CI_OS_VERSION
        glibc_version = tab["built_on"]["glibc_version"].presence if tab["built_on"].present?
        glibc_version ||= OS::LINUX_GLIBC_CI_VERSION
        cpu_variant = tab.dig("built_on", "oldest_cpu_family") || Hardware::CPU::INTEL_64BIT_OLDEST_CPU.to_s
      end

      platform_hash = {
        architecture:,
        os:,
        "os.version" => os_version,
      }.compact_blank

      tar_sha256 = Digest::SHA256.new
      Zlib::GzipReader.open(local_file) do |gz|
        while (data = gz.read(Utils::Gzip::GZIP_BUFFER_SIZE))
          tar_sha256 << data
        end
      end

      image_config = platform_hash.merge({
        rootfs: {
          type:     "layers",
          diff_ids: ["sha256:#{tar_sha256.hexdigest}"],
        },
      })
      validate_schema!(IMAGE_CONFIG_SCHEMA_URI, image_config)
      config_json_sha256, config_json_size = write_hash(blobs, image_config)

      documentation = "https://formulae.brew.sh/formula/#{formula_name}" if formula_core_tap

      local_file_size = File.size(local_file)

      path_exec_files_string = if (path_exec_files = tag_hash["path_exec_files"].presence)
        path_exec_files.join(",")
      end
      sbom_supplement_annotation = SBOM.github_packages_sbom_supplement_annotation(
        tag_hash["sbom"],
        formula_full_name:,
        formula_name:,
        version:,
        tar_gz_sha256:,
        root_url:          bottle_hash["bottle"]["root_url"],
        license:,
        created_date:,
      )

      descriptor_annotations_hash = {
        "org.opencontainers.image.ref.name" => tag,
        "sh.brew.bottle.cpu.variant"        => cpu_variant,
        "sh.brew.bottle.digest"             => tar_gz_sha256,
        "sh.brew.bottle.glibc.version"      => glibc_version,
        "sh.brew.bottle.size"               => local_file_size.to_s,
        "sh.brew.bottle.installed_size"     => tag_hash["installed_size"].to_s,
        "sh.brew.license"                   => license,
        "sh.brew.tab"                       => (all_bottle ? tab.except("arch", "built_on") : tab).to_json,
        "sh.brew.sbom.supplement"           => sbom_supplement_annotation,
        "sh.brew.path_exec_files"           => path_exec_files_string,
      }.compact_blank

      # TODO: upload/add tag_hash["all_files"] somewhere.

      annotations_hash = formula_annotations_hash.merge(descriptor_annotations_hash).merge(
        {
          "org.opencontainers.image.created"       => created_date,
          "org.opencontainers.image.documentation" => documentation,
          "org.opencontainers.image.title"         => "#{formula_full_name} #{tag}",
        },
      ).compact_blank.sort.to_h

      image_manifest = {
        schemaVersion: 2,
        config:        {
          mediaType: "application/vnd.oci.image.config.v1+json",
          digest:    "sha256:#{config_json_sha256}",
          size:      config_json_size,
        },
        layers:        [{
          mediaType:   "application/vnd.oci.image.layer.v1.tar+gzip",
          digest:      "sha256:#{tar_gz_sha256}",
          size:        File.size(local_file),
          annotations: {
            "org.opencontainers.image.title" => local_file,
          },
        }],
        annotations:   annotations_hash,
      }
      validate_schema!(IMAGE_MANIFEST_SCHEMA_URI, image_manifest)
      manifest_json_sha256, manifest_json_size = write_hash(blobs, image_manifest)

      {
        mediaType:   "application/vnd.oci.image.manifest.v1+json",
        digest:      "sha256:#{manifest_json_sha256}",
        size:        manifest_json_size,
        platform:    all_bottle ? nil : platform_hash,
        annotations: descriptor_annotations_hash,
      }.compact
    end

    image_index = {
      schemaVersion: 2,
      manifests:,
      annotations:   formula_annotations_hash,
    }
    validate_schema!(IMAGE_INDEX_SCHEMA_URI, image_index)
    index_json_sha256, index_json_size = write_hash(blobs, image_index)
    raise "Image index too large!" if index_json_size >= 4 * 1024 * 1024 # GitHub will error 500 if too large

    index_json = {
      schemaVersion: 2,
      manifests:     [{
        mediaType:   "application/vnd.oci.image.index.v1+json",
        digest:      "sha256:#{index_json_sha256}",
        size:        index_json_size,
        annotations: { "org.opencontainers.image.ref.name" => version_rebuild },
      }],
    }
    validate_schema!(IMAGE_INDEX_SCHEMA_URI, index_json)
    write_hash(root, index_json, "index.json")

    package_name = "#{GitHubPackages.repo_without_prefix(repo)}/#{image_name}"
    Image.new(root:, uri: image_uri, index_sha256: index_json_sha256, base_index_sha256:,
              package_url: "https://github.com/orgs/#{org}/packages/container/package/#{package_name}")
  end

  sig { params(user: String, token: String, skopeo: Pathname, image: Image, dry_run: T::Boolean).void }
  def upload_image(user, token, skopeo, image, dry_run:)
    puts
    args = ["copy", "--retry-times=3", "--format=oci", "--all", "--preserve-digests", "oci:#{image.root}", image.uri]
    if dry_run
      puts "#{skopeo} #{args.join(" ")} --dest-creds=#{user}:$HOMEBREW_GITHUB_PACKAGES_TOKEN"
    else
      args << "--dest-creds=#{user}:#{token}"
      retry_count = 0
      begin
        system_command!(skopeo, verbose: true, print_stdout: true, args:)
      rescue ErrorDuringExecution
        retry_count += 1
        odie "Cannot perform an upload to registry after retrying multiple times!" if retry_count >= 10
        Utils.exponential_backoff_sleep(retry_count)
        retry
      end

      ohai "Uploaded to #{image.package_url}"
    end
  end

  private

  IMAGE_CONFIG_SCHEMA_URI = "https://opencontainers.org/schema/image/config"
  IMAGE_INDEX_SCHEMA_URI = "https://opencontainers.org/schema/image/index"
  IMAGE_LAYOUT_SCHEMA_URI = "https://opencontainers.org/schema/image/layout"
  IMAGE_MANIFEST_SCHEMA_URI = "https://opencontainers.org/schema/image/manifest"

  GITHUB_PACKAGE_TYPE = "homebrew_bottle"
  private_constant :IMAGE_CONFIG_SCHEMA_URI, :IMAGE_INDEX_SCHEMA_URI, :IMAGE_LAYOUT_SCHEMA_URI,
                   :IMAGE_MANIFEST_SCHEMA_URI, :GITHUB_PACKAGE_TYPE

  sig { void }
  def load_schemas!
    schema_uri("content-descriptor",
               "https://opencontainers.org/schema/image/content-descriptor.json")
    schema_uri("defs", %w[
      https://opencontainers.org/schema/defs.json
      https://opencontainers.org/schema/descriptor/defs.json
      https://opencontainers.org/schema/image/defs.json
      https://opencontainers.org/schema/image/descriptor/defs.json
      https://opencontainers.org/schema/image/index/defs.json
      https://opencontainers.org/schema/image/manifest/defs.json
    ])
    schema_uri("defs-descriptor", %w[
      https://opencontainers.org/schema/descriptor.json
      https://opencontainers.org/schema/defs-descriptor.json
      https://opencontainers.org/schema/descriptor/defs-descriptor.json
      https://opencontainers.org/schema/image/defs-descriptor.json
      https://opencontainers.org/schema/image/descriptor/defs-descriptor.json
      https://opencontainers.org/schema/image/index/defs-descriptor.json
      https://opencontainers.org/schema/image/manifest/defs-descriptor.json
      https://opencontainers.org/schema/index/defs-descriptor.json
    ])
    schema_uri("config-schema", IMAGE_CONFIG_SCHEMA_URI)
    schema_uri("image-index-schema", IMAGE_INDEX_SCHEMA_URI)
    schema_uri("image-layout-schema", IMAGE_LAYOUT_SCHEMA_URI)
    schema_uri("image-manifest-schema", IMAGE_MANIFEST_SCHEMA_URI)
  end

  sig { params(basename: String, uris: T.any(String, T::Array[String])).void }
  def schema_uri(basename, uris)
    # The current `main` version has an invalid JSON schema.
    # Going forward, this should probably be pinned to tags.
    # We currently use features newer than the last one (v1.0.2).
    url = "https://raw.githubusercontent.com/opencontainers/image-spec/170393e57ed656f7f81c3070bfa8c3346eaa0a5a/schema/#{basename}.json"
    out = Utils::Curl.curl_output(url).stdout
    json = JSON.parse(out)

    @schema_json ||= T.let({}, T.nilable(T::Hash[String, T::Hash[String, T.untyped]]))
    Array(uris).each do |uri|
      @schema_json[uri] = json
    end
  end

  T::Sig::WithoutRuntime.sig { params(uri: URI::Generic).returns(T.nilable(T::Hash[String, T.untyped])) }
  def schema_resolver(uri)
    @schema_json&.fetch(uri.to_s.gsub(/#.*/, ""))
  end

  sig { params(schema_uri: String, json: T::Hash[T.any(String, Symbol), T.untyped]).void }
  def validate_schema!(schema_uri, json)
    schema = JSONSchemer.schema(@schema_json&.fetch(schema_uri), ref_resolver: method(:schema_resolver))
    json = json.deep_stringify_keys
    return if schema.valid?(json)

    puts
    ofail "#{Formatter.url(schema_uri)} JSON schema validation failed!"
    oh1 "Errors"
    puts schema.validate(json).to_a.inspect
    oh1 "JSON"
    puts json.inspect
    exit 1
  end

  sig { params(user: String, token: String, skopeo: Pathname, image_uri: String, root: Pathname, dry_run: T::Boolean).void }
  def download(user, token, skopeo, image_uri, root, dry_run:)
    puts
    args = ["copy", "--all", image_uri.to_s, "oci:#{root}"]
    if dry_run
      puts "#{skopeo} #{args.join(" ")} --src-creds=#{user}:$HOMEBREW_GITHUB_PACKAGES_TOKEN"
    else
      args << "--src-creds=#{user}:#{token}"
      system_command!(skopeo, verbose: true, print_stdout: true, args:)
    end
  end

  sig {
    params(
      user: String, token: String, skopeo: Pathname, _formula_full_name: String,
      bottle_hash: T::Hash[String, T.untyped], keep_old: T::Boolean, dry_run: T::Boolean, warn_on_error: T::Boolean
    ).returns(
      T.nilable([String, String, String, Version, Integer, String, String, String, T::Boolean, T.nilable(String)]),
    )
  }
  def preupload_check(user, token, skopeo, _formula_full_name, bottle_hash, keep_old:, dry_run:, warn_on_error:)
    formula_name = bottle_hash["formula"]["name"]

    _, org, repo, = *bottle_hash["bottle"]["root_url"].match(URL_REGEX)
    repo = "homebrew-#{repo}" unless repo.start_with?("homebrew-")

    version = Version.new(bottle_hash["formula"]["pkg_version"])
    rebuild = bottle_hash["bottle"]["rebuild"].to_i
    version_rebuild = GitHubPackages.version_rebuild(version, rebuild)

    image_name = GitHubPackages.image_formula_name(formula_name)
    image_tag = GitHubPackages.image_version_rebuild(version_rebuild)
    image_uri = "#{GitHubPackages.root_url(org, repo, DOCKER_PREFIX)}/#{image_name}:#{image_tag}"

    puts
    inspect_args = ["inspect", "--raw", image_uri.to_s]
    if dry_run
      puts "#{skopeo} #{inspect_args.join(" ")} --creds=#{user}:$HOMEBREW_GITHUB_PACKAGES_TOKEN"
    else
      inspect_args << "--creds=#{user}:#{token}"
      inspect_result = system_command(skopeo, print_stderr: false, args: inspect_args)
      index_sha256 = Digest::SHA256.hexdigest(inspect_result.stdout) if inspect_result.status.success?

      # Order here is important.
      if !inspect_result.status.success? && !inspect_result.stderr.match?(/(name|manifest) unknown/)
        # We got an error and it was not about the tag or package being unknown.
        if warn_on_error
          opoo "#{image_uri} inspection returned an error, skipping upload!\n#{inspect_result.stderr}"
          return
        else
          odie "#{image_uri} inspection returned an error!\n#{inspect_result.stderr}"
        end
      elsif keep_old
        # If the tag doesn't exist, ignore `--keep-old`.
        keep_old = false unless inspect_result.status.success?
        # Otherwise, do nothing - the tag already existing is expected behaviour for --keep-old.
      elsif inspect_result.status.success?
        # The tag already exists and we are not passing `--keep-old`.
        if warn_on_error
          opoo "#{image_uri} already exists, skipping upload!"
          return
        else
          odie "#{image_uri} already exists!"
        end
      end
    end

    [formula_name, org, repo, version, rebuild, version_rebuild, image_name, image_uri, keep_old, index_sha256]
  end

  sig { params(directory: Pathname, hash: T::Hash[T.any(String, Symbol), T.untyped], filename: T.nilable(String)).returns([String, Integer]) }
  def write_hash(directory, hash, filename = nil)
    json = JSON.pretty_generate(hash)
    sha256 = Digest::SHA256.hexdigest(json)
    filename ||= sha256
    path = directory/filename
    path.unlink if path.exist?
    path.write(json)

    [sha256, json.size]
  end
end
