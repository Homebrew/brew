# typed: strict
# frozen_string_literal: true

require "utils/curl"
require "utils/github/api"

# Auditing functions for rules common to both casks and formulae.
module SharedAudits
  URL_TYPE_HOMEPAGE = "homepage URL"

  sig { params(product: String, cycle: String).returns(T.nilable(T::Hash[String, T.untyped])) }
  def self.eol_data(product, cycle)
    @eol_data ||= T.let({}, T.nilable(T::Hash[String, T.untyped]))
    @eol_data["#{product}/#{cycle}"] ||= begin
      out, _, status = Utils::Curl.curl_output("--location", "https://endoflife.date/api/#{product}/#{cycle}.json")
      json = JSON.parse(out) if status.success?
      json = nil if json&.dig("message")&.include?("Product not found")
      json
    end
  end

  sig { params(user: String, repo: String).returns(T.nilable(T::Hash[String, T.untyped])) }
  def self.github_repo_data(user, repo)
    @github_repo_data ||= T.let({}, T.nilable(T::Hash[String, T.untyped]))
    @github_repo_data["#{user}/#{repo}"] ||= GitHub.repository(user, repo)

    @github_repo_data["#{user}/#{repo}"]
  rescue GitHub::API::HTTPNotFoundError
    nil
  rescue GitHub::API::AuthenticationFailedError => e
    raise unless e.message.match?(GitHub::API::GITHUB_IP_ALLOWLIST_ERROR)
  end

  sig { params(user: String, repo: String, tag: String).returns(T.nilable(T::Hash[String, T.untyped])) }
  private_class_method def self.github_release_data(user, repo, tag)
    id = "#{user}/#{repo}/#{tag}"
    url = "#{GitHub::API_URL}/repos/#{user}/#{repo}/releases/tags/#{tag}"
    @github_release_data ||= T.let({}, T.nilable(T::Hash[String, T.untyped]))
    @github_release_data[id] ||= GitHub::API.open_rest(url)

    @github_release_data[id]
  rescue GitHub::API::HTTPNotFoundError
    nil
  rescue GitHub::API::AuthenticationFailedError => e
    raise unless e.message.match?(GitHub::API::GITHUB_IP_ALLOWLIST_ERROR)
  end

  sig {
    params(
      user: String, repo: String, tag: String, formula: T.nilable(Formula), cask: T.nilable(Cask::Cask),
    ).returns(
      T.nilable(String),
    )
  }
  def self.github_release(user, repo, tag, formula: nil, cask: nil)
    release = github_release_data(user, repo, tag)
    return unless release

    exception, name, version = if formula
      [formula.tap&.audit_exception(:github_prerelease_allowlist, formula.name), formula.name, formula.version]
    elsif cask
      [cask.tap&.audit_exception(:github_prerelease_allowlist, cask.token), cask.token, cask.version]
    end

    return "#{tag} is a GitHub pre-release." if release["prerelease"] && [version, "all"].exclude?(exception)

    if !release["prerelease"] && exception
      return "#{tag} is not a GitHub pre-release but '#{name}' is in the GitHub prerelease allowlist."
    end

    "#{tag} is a GitHub draft." if release["draft"]
  end

  sig { params(user: String, repo: String).returns(T.nilable(T::Hash[String, T.untyped])) }
  def self.gitlab_repo_data(user, repo)
    @gitlab_repo_data ||= T.let({}, T.nilable(T::Hash[String, T.untyped]))
    @gitlab_repo_data["#{user}/#{repo}"] ||= begin
      out, _, status = Utils::Curl.curl_output("https://gitlab.com/api/v4/projects/#{user}%2F#{repo}")
      json = JSON.parse(out) if status.success?
      json = nil if json&.dig("message")&.include?("404 Project Not Found")
      json
    end
  end

  sig { params(user: String, repo: String, tag: String).returns(T.nilable(T::Hash[String, T.untyped])) }
  private_class_method def self.gitlab_release_data(user, repo, tag)
    id = "#{user}/#{repo}/#{tag}"
    @gitlab_release_data ||= T.let({}, T.nilable(T::Hash[String, T.untyped]))
    @gitlab_release_data[id] ||= begin
      out, _, status = Utils::Curl.curl_output(
        "https://gitlab.com/api/v4/projects/#{user}%2F#{repo}/releases/#{tag}", "--fail"
      )
      JSON.parse(out) if status.success?
    end
  end

  sig {
    params(
      user: String, repo: String, tag: String, formula: T.nilable(Formula), cask: T.nilable(Cask::Cask),
    ).returns(
      T.nilable(String),
    )
  }
  def self.gitlab_release(user, repo, tag, formula: nil, cask: nil)
    release = gitlab_release_data(user, repo, tag)
    return unless release

    return if DateTime.parse(release["released_at"]) <= DateTime.now

    exception, version = if formula
      [formula.tap&.audit_exception(:gitlab_prerelease_allowlist, formula.name), formula.version]
    elsif cask
      [cask.tap&.audit_exception(:gitlab_prerelease_allowlist, cask.token), cask.version]
    end
    return if [version, "all"].include?(exception)

    "#{tag} is a GitLab pre-release."
  end

  sig { params(user: String, repo: String).returns(T.nilable(String)) }
  def self.github(user, repo)
    metadata = github_repo_data(user, repo)

    return if metadata.nil?

    return "GitHub fork (not canonical repository)" if metadata["fork"]

    if (metadata["forks_count"] < 30) && (metadata["subscribers_count"] < 30) &&
       (metadata["stargazers_count"] < 75)
      return "GitHub repository not notable enough (<30 forks, <30 watchers and <75 stars)"
    end

    return if Date.parse(metadata["created_at"]) <= (Date.today - 30)

    "GitHub repository too new (<30 days old)"
  end

  sig { params(user: String, repo: String).returns(T.nilable(String)) }
  def self.gitlab(user, repo)
    metadata = gitlab_repo_data(user, repo)

    return if metadata.nil?

    return "GitLab fork (not canonical repository)" if metadata["fork"]
    if (metadata["forks_count"] < 30) && (metadata["star_count"] < 75)
      return "GitLab repository not notable enough (<30 forks and <75 stars)"
    end

    return if Date.parse(metadata["created_at"]) <= (Date.today - 30)

    "GitLab repository too new (<30 days old)"
  end

  sig { params(user: String, repo: String).returns(T.nilable(String)) }
  def self.bitbucket(user, repo)
    api_url = "https://api.bitbucket.org/2.0/repositories/#{user}/#{repo}"
    out, _, status = Utils::Curl.curl_output("--request", "GET", api_url)
    return unless status.success?

    metadata = JSON.parse(out)
    return if metadata.nil?

    return "Uses deprecated Mercurial support in Bitbucket" if metadata["scm"] == "hg"

    return "Bitbucket fork (not canonical repository)" unless metadata["parent"].nil?

    return "Bitbucket repository too new (<30 days old)" if Date.parse(metadata["created_on"]) >= (Date.today - 30)

    forks_out, _, forks_status = Utils::Curl.curl_output("--request", "GET", "#{api_url}/forks")
    return unless forks_status.success?

    watcher_out, _, watcher_status = Utils::Curl.curl_output("--request", "GET", "#{api_url}/watchers")
    return unless watcher_status.success?

    forks_metadata = JSON.parse(forks_out)
    return if forks_metadata.nil?

    watcher_metadata = JSON.parse(watcher_out)
    return if watcher_metadata.nil?

    return if forks_metadata["size"] >= 30 || watcher_metadata["size"] >= 75

    "Bitbucket repository not notable enough (<30 forks and <75 watchers)"
  end

  sig { params(url: String).returns(T.nilable(String)) }
  def self.github_tag_from_url(url)
    tag = url[%r{^https://github\.com/[\w-]+/[\w.-]+/archive/refs/tags/(.+)\.(tar\.gz|zip)$}, 1]
    tag || url[%r{^https://github\.com/[\w-]+/[\w.-]+/releases/download/([^/]+)/}, 1]
  end

  sig { params(url: String).returns(T.nilable(String)) }
  def self.gitlab_tag_from_url(url)
    url[%r{^https://gitlab\.com/(?:\w[\w.-]*/){2,}-/archive/([^/]+)/}, 1]
  end
end
