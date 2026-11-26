# typed: strict
# frozen_string_literal: true

require "utils/github"

module GitHub
  # Checks whether an upstream commit patch is included in an explicitly identified release.
  # Ancestry does not guarantee that the commit's changes have not subsequently been reverted.
  class PatchInclusion
    include Utils::Output::Mixin

    sig { void }
    def initialize
      @commits = T.let({}, T::Hash[String, T.nilable(String)])
      @comparisons = T.let({}, T::Hash[String, T::Boolean])
      @unavailable = T.let(false, T::Boolean)
    end

    # Returns PR-ready evidence, or nil when inclusion cannot be established.
    sig {
      params(patch_url: String, source_url: String, tag: T.nilable(String), revision: T.nilable(String))
        .returns(T.nilable(String))
    }
    def removal_reason(patch_url, source_url:, tag: nil, revision: nil)
      return unless available?

      patch = patch_url.match(%r{\Ahttps://github\.com/(?<repository>[\w.-]+/[\w.-]+)/commit/(?<sha>[a-fA-F0-9]{40})\.(?:patch|diff)(?:\?full_index=1)?\z})
      return unless patch

      source = source_url.match(%r{\Ahttps://github\.com/(?<repository>[\w.-]+/[\w.-]+?)(?:\.git)?(?:/(?<path>.*))?\z})
      return unless source
      return unless source[:repository]&.casecmp?(patch[:repository].to_s)

      repository = patch[:repository].to_s
      patch_sha = patch[:sha].to_s.downcase
      path = source[:path].to_s
      if path.empty?
        return if revision.blank? && tag.blank?
        return if revision.present? && !revision.match?(/\A[a-fA-F0-9]{40}\z/)

        ref = revision.presence || "refs/tags/#{tag}"
        label = tag.presence || revision.to_s
      else
        release_tag = path[%r{\Aarchive/(?:refs/tags/)?(?<tag>.+)\.(?:tar\.gz|tar\.bz2|tar\.xz|tgz|zip)\z}, :tag] ||
                      path[%r{\Areleases/download/(?<tag>[^/]+)/[^/]+\z}, :tag]
        return if release_tag.blank? || release_tag.start_with?("refs/")

        label = URI::DEFAULT_PARSER.unescape(release_tag)
        ref = "refs/tags/#{label}"
      end

      release_sha = included_in_ref(repository, patch_sha, ref:)
      return unless release_sha

      "Removed patch [`#{patch_sha}`](https://github.com/#{repository}/commit/#{patch_sha}): " \
        "the commit is included in `#{label.delete("`")}` (`#{release_sha}`). " \
        "[Compare commits](https://github.com/#{repository}/compare/#{patch_sha}...#{release_sha})."
    rescue API::Error, ErrorDuringExecution => e
      opoo "Retaining patch because GitHub inclusion could not be checked:\n#{patch_url}\n#{e.message}"
      nil
    end

    sig { returns(T::Boolean) }
    def available? = !@unavailable && !Homebrew::EnvConfig.no_github_api?

    # Returns the resolved commit of ref if it contains the given commit.
    sig { params(repository: String, commit: String, ref: String).returns(T.nilable(String)) }
    def included_in_ref(repository, commit, ref:)
      return unless available?

      commit_url = "#{API_URL}/repos/#{repository}/commits/#{URI.encode_www_form_component(ref)}"
      unless @commits.key?(commit_url)
        @commits[commit_url] = nil
        sha = API.open_rest(commit_url)["sha"]
        @commits[commit_url] = sha.downcase if sha.is_a?(String) && sha.match?(/\A\h{40}\z/)
      end
      release_sha = @commits[commit_url]
      return unless release_sha

      comparison = "#{repository}/compare/#{commit}...#{release_sha}"
      unless @comparisons.key?(comparison)
        @comparisons[comparison] = false
        @comparisons[comparison] =
          %w[ahead identical].include?(API.open_rest("#{API_URL}/repos/#{comparison}?per_page=1")["status"])
      end
      release_sha if @comparisons[comparison]
    rescue API::RateLimitExceededError, API::AuthenticationFailedError, API::MissingAuthenticationError
      @unavailable = true
      raise
    end
  end
end
