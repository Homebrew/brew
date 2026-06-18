# typed: strict
# frozen_string_literal: true

# Strategy for downloading a file from an GitHub Packages URL.
#
# @api public
class CurlGitHubPackagesDownloadStrategy < CurlDownloadStrategy
  sig { params(resolved_basename: String).returns(T.nilable(String)) }
  attr_writer :resolved_basename

  sig { params(url: String, name: String, version: T.nilable(T.any(String, Version)), meta: T.untyped).void }
  def initialize(url, name, version, **meta)
    meta[:headers] ||= []
    # GitHub Packages authorization header.
    # HOMEBREW_GITHUB_PACKAGES_AUTH set in brew.sh
    # If using a private GHCR mirror with no Authentication set or HOMEBREW_GITHUB_PACKAGES_AUTH is empty
    # then do not add the header. In all other cases add it.
    if HOMEBREW_GITHUB_PACKAGES_AUTH.presence && (
       !Homebrew::EnvConfig.artifact_domain.presence ||
       Homebrew::EnvConfig.docker_registry_basic_auth_token.presence ||
       Homebrew::EnvConfig.docker_registry_token.presence
     )
      meta[:headers] << "Authorization: #{HOMEBREW_GITHUB_PACKAGES_AUTH}"
    end
    super
  end

  sig { override.returns(Pathname) }
  def cached_location
    return super unless immutable_bottle_blob?

    cached_location = @cached_location
    return cached_location unless cached_location.nil?

    @cached_location = HOMEBREW_CACHE/"downloads/#{Digest::SHA256.hexdigest(url)}--#{Utils.safe_filename(@resolved_basename.to_s)}"
  end

  sig { returns(T::Boolean) }
  def immutable_bottle_blob?
    return false if meta[:bottle] != true
    return false unless mirrors.empty?
    return false if @resolved_basename.blank?

    !bottle_blob_sha256.nil?
  end

  sig { returns(T.nilable(String)) }
  def bottle_blob_sha256
    url[%r{/blobs/sha256:([0-9a-f]{64})(?:[?#]|$)}i, 1]&.downcase
  end

  private

  sig { override.params(url: String, timeout: T.nilable(T.any(Float, Integer))).returns(URLMetadata) }
  def resolve_url_basename_time_file_size(url, timeout: nil)
    return super if @resolved_basename.blank?

    [url, @resolved_basename, nil, nil, nil, false]
  end
end
