# typed: strict
# frozen_string_literal: true

require "download_strategy"
require "utils/github"

module GitHub
  # Download an artifact from GitHub Actions and unpack it into the current working directory.
  #
  # @param url [String] URL to download from
  # @param artifact_id [String] a value that uniquely identifies the downloaded artifact
  sig { params(url: String, artifact_id: String).void }
  def self.download_artifact(url, artifact_id)
    token = API.credentials
    raise API::MissingAuthenticationError if token.blank?

    # We use a download strategy here to leverage the Homebrew cache
    # to avoid repeated downloads of (possibly large) bottles.
    downloader = GitHubArtifactDownloadStrategy.new(url, artifact_id, token:)
    downloader.fetch
    downloader.stage
  end
end
require "utils/github/artifacts/github_artifact_download_strategy"
