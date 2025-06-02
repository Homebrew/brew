# typed: strict
# frozen_string_literal: true

require "utils/github"
require "json"

# GitHub Releases client.
class GitHubReleases
  include Context

  URL_REGEX = %r{https://github\.com/([\w-]+)/([\w-]+)?/releases/download/(.+)}

  sig { params(bottles_hash: T::Hash[String, T.untyped]).void }
  def upload_bottles(bottles_hash)
    bottles_hash.each_value do |bottle_hash|
      root_url = bottle_hash["bottle"]["root_url"]
      url_match = root_url.match URL_REGEX
      _, user, repo, tag = *url_match

      # Ensure a release is created.
      release = begin
        rel = GitHub.get_release user, repo, tag
        odebug "Existing GitHub release \"#{tag}\" found"
        rel
      rescue GitHub::API::HTTPNotFoundError
        odebug "Creating new GitHub release \"#{tag}\""
        GitHub.create_or_update_release user, repo, tag
      end

      # Upload bottles as release assets.
      bottle_hash["bottle"]["tags"].each_value do |tag_hash|
        remote_file = tag_hash["filename"]
        local_file = tag_hash["local_filename"]
        odebug "Uploading #{remote_file}"
        GitHub.upload_release_asset user, repo, release["id"], local_file:, remote_file:
      end
    end
  end
end
