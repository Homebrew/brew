# typed: strict
# frozen_string_literal: true

require "utils/github"
require "utils/output"
require "json"

# GitHub Releases client.
class GitHubReleases
  include Context
  include Utils::Output::Mixin

  URL_REGEX = %r{https://github\.com/([\w-]+)/([\w-]+)?/releases/download/(.+)}

  sig { params(bottles_hash: T::Hash[String, T.untyped]).void }
  def upload_bottles(bottles_hash)
    bottles_by_release = bottles_hash.values.group_by do |bottle_hash|
      _, user, repo, tag = *bottle_hash["bottle"]["root_url"].match(URL_REGEX)
      [user.downcase, repo.downcase, tag]
    end
    bottle_count = bottles_by_release.values.sum(&:count)
    uploaded_count = 0
    bottles_by_release.each do |(user, repo, tag), bottles|
      # Ensure a release is created or reused. Bottles are uploaded to a draft
      # release which is published afterwards, so that uploads also work on
      # repositories with immutable releases enabled, where assets cannot be
      # added to a release after it has been published.
      release, draft_release = find_or_create_release(user, repo, tag)

      bottles.each do |bottle_hash|
        # Upload bottles as release assets.
        bottle_hash["bottle"]["tags"].each_value do |tag_hash|
          remote_file = tag_hash["filename"]
          local_file = tag_hash["local_filename"]
          if draft_release && (asset = release.fetch("assets", []).find { |a| a["name"] == remote_file })
            if !File.file?(local_file) || !File.readable?(local_file)
              raise GitHub::API::Error, "Cannot replace #{remote_file}: #{local_file} is not a readable file."
            end

            # open_rest only sets the HTTP method when a payload is supplied.
            GitHub::API.open_rest(
              "#{GitHub::API_URL}/repos/#{user}/#{repo}/releases/assets/#{asset.fetch("id")}",
              data: {}, request_method: :DELETE, scopes: GitHub::CREATE_ISSUE_FORK_OR_PR_SCOPES,
            )
          end
          odebug "Uploading #{remote_file}"
          GitHub.upload_release_asset user, repo, release["id"], local_file:, remote_file:
        end

        uploaded_count += 1
        next if bottle_count < 3

        ohai "Upload progress: #{uploaded_count} formula(e) uploaded, #{bottle_count - uploaded_count} remaining"
      end

      # Publish the release (and thereby create its tag) now that all bottle
      # assets have been uploaded.
      if draft_release
        GitHub.create_or_update_release(user, repo, tag, id: release["id"], draft: false)
      end
    end
  end

  private

  # Returns a release to upload bottle assets to, together with whether it is
  # a draft release that still needs to be published after uploading. An
  # existing release for the tag is reused so that failed uploads can be
  # repaired. Otherwise, a new draft release is created, reusing a leftover
  # draft release for the tag if there is one.
  sig {
    params(user: String, repo: String, tag: String)
      .returns([T::Hash[String, T.untyped], T::Boolean])
  }
  def find_or_create_release(user, repo, tag)
    release = begin
      rel = GitHub.get_release user, repo, tag
      odebug "Existing GitHub release \"#{tag}\" found"
      rel
    rescue GitHub::API::HTTPNotFoundError
      nil
    end
    return [release, false] if release

    begin
      odebug "Creating new draft GitHub release \"#{tag}\""
      [GitHub.create_or_update_release(user, repo, tag, draft: true), true]
    rescue GitHub::API::Error
      # Draft releases are not returned by the tag lookup above, so a leftover
      # draft release for this tag makes creating a new release fail.
      release = GitHub.get_draft_release user, repo, tag
      raise if release.nil?

      odebug "Existing draft GitHub release \"#{tag}\" found"
      [release, true]
    end
  end
end
