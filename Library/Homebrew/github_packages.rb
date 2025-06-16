# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

require "utils/curl"
require "utils/gzip"
require "json"
require "zlib"
require "extend/hash/keys"
require "system_command"

# GitHub Packages client.
class GitHubPackages
  include Context
  include SystemCommand::Mixin

  URL_DOMAIN = "ghcr.io"
  URL_PREFIX = "https://#{URL_DOMAIN}/v2/".freeze
  DOCKER_PREFIX = "docker://#{URL_DOMAIN}/".freeze
  public_constant :URL_DOMAIN
  private_constant :URL_PREFIX
  private_constant :DOCKER_PREFIX

  URL_REGEX = %r{(?:#{Regexp.escape(URL_PREFIX)}|#{Regexp.escape(DOCKER_PREFIX)})([\w-]+)/([\w-]+)}

  # Valid OCI tag characters
  # https://github.com/opencontainers/distribution-spec/blob/main/spec.md#workflow-categories
  VALID_OCI_TAG_REGEX = /^[a-zA-Z0-9_][a-zA-Z0-9._-]{0,127}$/
  INVALID_OCI_TAG_CHARS_REGEX = /[^a-zA-Z0-9._-]/

  # Translate Homebrew tab.arch to OCI platform.architecture
  TAB_ARCH_TO_PLATFORM_ARCHITECTURE = {
    "arm64"  => "arm64",
    "x86_64" => "amd64",
  }.freeze

  # Translate Homebrew built_on.os to OCI platform.os
  BUILT_ON_OS_TO_PLATFORM_OS = {
    "Linux"     => "linux",
    "Macintosh" => "darwin",
  }.freeze

  sig {
    params(
      bottles_hash:  T::Hash[String, T.untyped],
      keep_old:      T::Boolean,
      dry_run:       T::Boolean,
      warn_on_error: T::Boolean,
    ).void
  }
  def upload_bottles(bottles_hash, keep_old:, dry_run:, warn_on_error:)
    user = Homebrew::EnvConfig.github_packages_user
    token = Homebrew::EnvConfig.github_packages_token

    raise UsageError, "HOMEBREW_GITHUB_PACKAGES_USER is unset." if user.blank?
    raise UsageError, "HOMEBREW_GITHUB_PACKAGES_TOKEN is unset." if token.blank?

    skopeo = ensure_executable!("skopeo", reason: "upload")

    require "json_schemer"

    load_schemas!

    bottles_hash.each do |formula_full_name, bottle_hash|
      # First, check that we won't encounter an error in the middle of uploading bottles.
      preupload_check(user, token, skopeo, formula_full_name, bottle_hash,
                      keep_old:, dry_run:, warn_on_error:)
    end

    # We intentionally iterate over `bottles_hash` twice to
    # avoid erroring out in the middle of uploading bottles.
    # rubocop:disable Style/CombinableLoops
    bottles_hash.each do |formula_full_name, bottle_hash|
      # Next, upload the bottles after checking them all.
      upload_bottle(user, token, skopeo, formula_full_name, bottle_hash,
                    keep_old:, dry_run:, warn_on_error:)
    end
    # rubocop:enable Style/CombinableLoops
  end

  def self.version_rebuild(version, rebuild, bottle_tag = nil)
    bottle_tag = (".#{bottle_tag}" if bottle_tag.present?)

    rebuild = if rebuild.to_i.positive?
      if bottle_tag
        ".#{rebuild}"
      else
        "-#{rebuild}"
      end
    end

    "#{version}#{bottle_tag}#{rebuild}"
  end

  def self.repo_without_prefix(repo)
    # Remove redundant repository prefix for a shorter name.
    repo.delete_prefix("homebrew-")
  end

  def self.root_url(org, repo, prefix = URL_PREFIX)
    # `docker`/`skopeo` insist on lowercase organisation (“repository name”).
    org = org.downcase

    "#{prefix}#{org}/#{repo_without_prefix(repo)}"
  end

  def self.root_url_if_match(url)
    return if url.blank?

    _, org, repo, = *url.to_s.match(URL_REGEX)
    return if org.blank? || repo.blank?

    root_url(org, repo)
  end

  def self.image_formula_name(formula_name)
    # Invalid docker name characters:
    # - `/` makes sense because we already use it to separate repository/formula.
    # - `x` makes sense because we already use it in `Formulary`.
    formula_name.tr("@", "/")
                .tr("+", "x")
  end

  def self.image_version_rebuild(version_rebuild)
    unless version_rebuild.match?(VALID_OCI_TAG_REGEX)
      raise ArgumentError, "GitHub Packages versions must match #{VALID_OCI_TAG_REGEX.source}!"
    end

    version_rebuild
  end

  private

  IMAGE_CONFIG_SCHEMA_URI = "https://opencontainers.org/schema/image/config"
  IMAGE_INDEX_SCHEMA_URI = "https://opencontainers.org/schema/image/index"
  IMAGE_LAYOUT_SCHEMA_URI = "https://opencontainers.org/schema/image/layout"
  IMAGE_MANIFEST_SCHEMA_URI = "https://opencontainers.org/schema/image/manifest"

  GITHUB_PACKAGE_TYPE = "homebrew_bottle"
  private_constant :IMAGE_CONFIG_SCHEMA_URI, :IMAGE_INDEX_SCHEMA_URI, :IMAGE_LAYOUT_SCHEMA_URI,
                   :IMAGE_MANIFEST_SCHEMA_URI, :GITHUB_PACKAGE_TYPE

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

  def schema_uri(basename, uris)
    # The current `main` version has an invalid JSON schema.
    # Going forward, this should probably be pinned to tags.
    # We currently use features newer than the last one (v1.0.2).
    url = "https://raw.githubusercontent.com/opencontainers/image-spec/170393e57ed656f7f81c3070bfa8c3346eaa0a5a/schema/#{basename}.json"
    out = Utils::Curl.curl_output(url).stdout
    json = JSON.parse(out)

    @schema_json ||= {}
    Array(uris).each do |uri|
      @schema_json[uri] = json
    end
  end

  def schema_resolver(uri)
    @schema_json[uri.to_s.gsub(/#.*/, "")]
  end

  def validate_schema!(schema_uri, json)
    schema = JSONSchemer.schema(@schema_json[schema_uri], ref_resolver: method(:schema_resolver))
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

  def preupload_check(user, token, skopeo, _formula_full_name, bottle_hash, keep_old:, dry_run:, warn_on_error:)
    formula_name = bottle_hash["formula"]["name"]

    _, org, repo, = *bottle_hash["bottle"]["root_url"].match(URL_REGEX)
    repo = "homebrew-#{repo}" unless repo.start_with?("homebrew-")

    version = bottle_hash["formula"]["pkg_version"]
    rebuild = bottle_hash["bottle"]["rebuild"]
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

    [formula_name, org, repo, version, rebuild, version_rebuild, image_name, image_uri, keep_old]
  end

  def upload_bottle(user, token, skopeo, formula_full_name, bottle_hash, keep_old:, dry_run:, warn_on_error:)
    # We run the preupload check twice to prevent TOCTOU bugs.
    result = preupload_check(user, token, skopeo, formula_full_name, bottle_hash,
                             keep_old:, dry_run:, warn_on_error:)
    # Skip upload if preupload check returned early.
    return if result.nil?

    formula_name, org, repo, version, rebuild, version_rebuild, image_name, image_uri, keep_old = *result

    root = Pathname("#{formula_name}--#{version_rebuild}")
    FileUtils.rm_rf root
    root.mkpath

    if keep_old
      download(user, token, skopeo, image_uri, root, dry_run:)
    else
      write_image_layout(root)
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
      image_license = if license.length <= 256
        license
      else
        # TODO: Consider generating a truncated license when over the limit
        require "utils/spdx"
        SPDX.license_expression_to_string(:cannot_represent)
      end

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
        "org.opencontainers.image.version"       => version,
      }.compact_blank
      manifests = []
    end

    processed_image_refs = Set.new
    manifests.each do |manifest|
      processed_image_refs << manifest["annotations"]["org.opencontainers.image.ref.name"]
    end

    manifests += bottle_hash["bottle"]["tags"].map do |bottle_tag, tag_hash|
      bottle_tag = Utils::Bottles::Tag.from_symbol(bottle_tag.to_sym)

      tag = GitHubPackages.version_rebuild(version, rebuild, bottle_tag.to_s)

      if processed_image_refs.include?(tag)
        puts
        odie "A bottle JSON for #{bottle_tag} is present, but it is already in the image index!"
      else
        processed_image_refs << tag
      end

      local_file = tag_hash["local_filename"]
      odebug "Uploading #{local_file}"

      tar_gz_sha256 = write_tar_gz(local_file, blobs)

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

      config_json_sha256, config_json_size = write_image_config(platform_hash, tar_sha256.hexdigest, blobs)

      documentation = "https://formulae.brew.sh/formula/#{formula_name}" if formula_core_tap

      local_file_size = File.size(local_file)

      path_exec_files_string = if (path_exec_files = tag_hash["path_exec_files"].presence)
        path_exec_files.join(",")
      end

      descriptor_annotations_hash = {
        "org.opencontainers.image.ref.name" => tag,
        "sh.brew.bottle.cpu.variant"        => cpu_variant,
        "sh.brew.bottle.digest"             => tar_gz_sha256,
        "sh.brew.bottle.glibc.version"      => glibc_version,
        "sh.brew.bottle.size"               => local_file_size.to_s,
        "sh.brew.bottle.installed_size"     => tag_hash["installed_size"].to_s,
        "sh.brew.license"                   => license,
        "sh.brew.tab"                       => tab.to_json,
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
        platform:    platform_hash,
        annotations: descriptor_annotations_hash,
      }
    end

    index_json_sha256, index_json_size = write_image_index(manifests, blobs, formula_annotations_hash)
    raise "Image index too large!" if index_json_size >= 4 * 1024 * 1024 # GitHub will error 500 if too large

    write_index_json(index_json_sha256, index_json_size, root,
                     "org.opencontainers.image.ref.name" => version_rebuild)

    puts
    args = ["copy", "--retry-times=3", "--format=oci", "--all", "oci:#{root}", image_uri.to_s]
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
        sleep 2 ** retry_count
        retry
      end

      package_name = "#{GitHubPackages.repo_without_prefix(repo)}/#{image_name}"
      ohai "Uploaded to https://github.com/orgs/#{org}/packages/container/package/#{package_name}"
    end
  end

  def write_image_layout(root)
    image_layout = { imageLayoutVersion: "1.0.0" }
    validate_schema!(IMAGE_LAYOUT_SCHEMA_URI, image_layout)
    write_hash(root, image_layout, "oci-layout")
  end

  def write_tar_gz(local_file, blobs)
    tar_gz_sha256 = Digest::SHA256.file(local_file)
                                  .hexdigest
    FileUtils.ln local_file, blobs/tar_gz_sha256, force: true
    tar_gz_sha256
  end

  def write_image_config(platform_hash, tar_sha256, blobs)
    image_config = platform_hash.merge({
      rootfs: {
        type:     "layers",
        diff_ids: ["sha256:#{tar_sha256}"],
      },
    })
    validate_schema!(IMAGE_CONFIG_SCHEMA_URI, image_config)
    write_hash(blobs, image_config)
  end

  def write_image_index(manifests, blobs, annotations)
    image_index = {
      schemaVersion: 2,
      manifests:,
      annotations:,
    }
    validate_schema!(IMAGE_INDEX_SCHEMA_URI, image_index)
    write_hash(blobs, image_index)
  end

  def write_index_json(index_json_sha256, index_json_size, root, annotations)
    index_json = {
      schemaVersion: 2,
      manifests:     [{
        mediaType:   "application/vnd.oci.image.index.v1+json",
        digest:      "sha256:#{index_json_sha256}",
        size:        index_json_size,
        annotations:,
      }],
    }
    validate_schema!(IMAGE_INDEX_SCHEMA_URI, index_json)
    write_hash(root, index_json, "index.json")
  end

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
