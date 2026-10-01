# typed: strict
# frozen_string_literal: true

# Strategy for downloading an artifact from GitHub Actions.
class GitHubArtifactDownloadStrategy < AbstractFileDownloadStrategy
  sig { params(url: String, artifact_id: String, token: String).void }
  def initialize(url, artifact_id, token:)
    super(url, "artifact", artifact_id)
    @cache = T.let(HOMEBREW_CACHE/"gh-actions-artifact", Pathname)
    @token = token
  end

  sig { override.params(timeout: T.nilable(T.any(Float, Integer))).void }
  def fetch(timeout: nil)
    ohai "Downloading #{url}"
    if cached_location.exist?
      puts "Already downloaded: #{cached_location}"
    else
      begin
        Utils::Curl.curl_download(url, to:      temporary_path,
                                       header:  "Authorization: token #{@token}",
                                       secrets: [@token],
                                       timeout:)
      rescue ErrorDuringExecution
        raise CurlDownloadStrategyError, url
      end
      cached_location.dirname.mkpath
      temporary_path.rename(cached_location.to_s)
    end

    symlink_location.dirname.mkpath
    FileUtils.ln_s cached_location.relative_path_from(symlink_location.dirname), symlink_location, force: true
  end

  private

  sig { returns(String) }
  def resolved_basename
    "artifact.zip"
  end
end
