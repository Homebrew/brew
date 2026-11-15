# typed: strict
# frozen_string_literal: true

require "livecheck/livecheck"
require "system_command"
require "utils/curl"
require "utils/github/api"

# Auditing functions for rules common to both casks and formulae.
module SharedAudits
  URL_TYPE_HOMEPAGE = "homepage URL"
  SELF_SUBMISSION_THRESHOLD_MULTIPLIER = 3
  GITHUB_NOTABILITY_THRESHOLDS = T.let({ forks: 30, watchers: 30, stars: 75 }.freeze, T::Hash[Symbol, Integer])
  GITLAB_NOTABILITY_THRESHOLDS = T.let({ forks: 30, stars: 75 }.freeze, T::Hash[Symbol, Integer])
  BITBUCKET_NOTABILITY_THRESHOLDS = T.let({ forks: 30, watchers: 75 }.freeze, T::Hash[Symbol, Integer])
  FORGEJO_NOTABILITY_THRESHOLDS = T.let({ forks: 30, watchers: 30, stars: 75 }.freeze, T::Hash[Symbol, Integer])
  NOTABILITY_REPOSITORY_REGEXES = T.let({
    github:    %r{\Ahttps?://github\.com/([^/]+)/([^/]+)/?.*},
    gitlab:    %r{\Ahttps?://gitlab\.com/([^/]+)/([^/]+)/?.*},
    bitbucket: %r{\Ahttps?://bitbucket\.org/([^/]+)/([^/]+)/?.*},
    forgejo:   %r{\Ahttps?://codeberg\.org/([^/]+)/([^/]+)/?.*},
  }.freeze, T::Hash[Symbol, Regexp])
  NEW_DOMAIN_THRESHOLD_DAYS = 30
  GIT_FORGE_DOMAINS = %w[
    bitbucket.org
    codeberg.org
    github.com
    github.io
    gitlab.com
    gitlab.io
    sr.ht
  ].freeze
  WHOIS_TIMEOUT_SECONDS = 5
  WHOIS_CREATION_DATE_REGEX = /^\s*(?:creation\s+date|created(?:\s+on)?|registered(?:\s+on)?|
                                registration\s+(?:date|time))\s*:\s*(.+)/ix
  # RDAP is the IETF successor to WHOIS: ICANN requires every gTLD registry to serve it
  # and IANA's bootstrap file lists the server for each TLD (gTLD or ccTLD) that does.
  RDAP_BOOTSTRAP_URL = "https://data.iana.org/rdap/dns.json"
  RDAP_TIMEOUT_SECONDS = 10
  RdapServices = T.type_alias { T::Array[[T::Array[String], T::Array[String]]] }
  @pull_request_author = T.let(nil, T.nilable(String))
  @pull_request_author_computed = T.let(false, T::Boolean)
  @self_submission_cache = T.let({}, T::Hash[String, T::Boolean])
  @pull_request_commit_email_domains = T.let(nil, T.nilable(T::Array[String]))
  @rdap_services = T.let(nil, T.nilable(RdapServices))

  class << self
    sig {
      params(pull_request_commit_email_domains: T.nilable(T::Array[String]))
        .returns(T.nilable(T::Array[String]))
    }
    attr_writer :pull_request_commit_email_domains

    sig { params(rdap_services: T.nilable(RdapServices)).returns(T.nilable(RdapServices)) }
    attr_writer :rdap_services
  end

  sig { params(browsed: T.nilable(Date)).returns(T::Boolean) }
  def self.homepage_browsed_recently?(browsed)
    return false unless browsed

    today = Date.today
    browsed <= today && browsed.next_year > today
  end

  sig { params(homepage: String).returns(T.nilable(String)) }
  def self.new_domain_problem(homepage)
    domain = url_domain(homepage)
    return if domain.nil? || git_forge_domain?(domain)

    @rdap_services ||= begin
      result = Utils::Curl.curl_output(RDAP_BOOTSTRAP_URL, max_time: RDAP_TIMEOUT_SECONDS)
      (JSON.parse(result.stdout).fetch("services") if result.status.success?) || []
    rescue JSON::ParserError, KeyError, TypeError
      []
    end

    registered_domain = domain
    registered_on = T.let(nil, T.nilable(Date))
    tld = domain.split(".").last
    rdap_urls = @rdap_services.find { |tlds, _| tlds.include?(tld) }&.fetch(1)
    if rdap_urls.present?
      rdap_base_url = (rdap_urls.find { |url| url.start_with?("https://") } || rdap_urls.fetch(0)).delete_suffix("/")
      # Registries answer 4xx for subdomains, so walk up to the registered domain.
      labels = domain.split(".")
      while labels.length >= 2
        candidate = labels.join(".")
        result = Utils::Curl.curl_output(
          "--include", "--location", "#{rdap_base_url}/domain/#{candidate}",
          header: "Accept: application/rdap+json", max_time: RDAP_TIMEOUT_SECONDS
        )
        break unless result.status.success?

        parsed = Utils::Curl.parse_curl_output(result.stdout)
        status_code = parsed.fetch(:responses).last&.fetch(:status_code).to_i
        if (400..499).cover?(status_code)
          labels.shift
          next
        end
        break if status_code != 200

        registered_on = begin
          events = JSON.parse(parsed.fetch(:body)).fetch("events", [])
          registration = events.find { |event| event["eventAction"] == "registration" }
          Date.parse(registration.fetch("eventDate")) unless registration.nil?
        rescue JSON::ParserError, KeyError, TypeError, Date::Error
          nil
        end
        registered_domain = candidate unless registered_on.nil?
        break
      end
    end

    if registered_on.nil? && which("whois")
      whois = begin
        SystemCommand.run("whois", args: [domain], print_stderr: false, timeout: WHOIS_TIMEOUT_SECONDS)
      rescue Timeout::Error
        nil
      end
      lines = if whois.nil? || !whois.status.success?
        []
      else
        whois.stdout.scrub.lines
      end
      # `whois` may print the IANA record for the TLD (whose creation date is always ancient)
      # before following its referral to the registry, so only look after the referral marker:
      # `# whois.nic.sh` on macOS, `Found a referral to whois.nic.sh.` on Linux.
      if lines.first&.start_with?("% IANA WHOIS server")
        referral_index = lines.index { |line| line.start_with?("# whois.", "Found a referral to ") }
        lines = referral_index ? lines.drop(referral_index + 1) : []
      end

      lines.each do |line|
        value = line[WHOIS_CREATION_DATE_REGEX, 1]
        next if value.nil?

        registered_on = Date.parse(value)
        break
      rescue Date::Error
        nil
      end
    end
    return if registered_on.nil?
    return if (Date.today - registered_on) >= NEW_DOMAIN_THRESHOLD_DAYS

    "`homepage` domain `#{registered_domain}` was registered on #{registered_on}: " \
      "homepages should exist for at least #{NEW_DOMAIN_THRESHOLD_DAYS} days before inclusion"
  end

  sig { returns(T.nilable(String)) }
  def self.pull_request_author
    return @pull_request_author if @pull_request_author_computed

    @pull_request_author_computed = true
    @pull_request_author = github_event_pull_request_value("user", "login")
  end

  sig { returns(T::Array[String]) }
  def self.pull_request_commit_email_domains
    @pull_request_commit_email_domains ||= begin
      commits_url = github_event_pull_request_value("commits_url")
      commits = []
      if commits_url.present?
        GitHub::API.paginate_rest(commits_url) do |page_commits, _page|
          commits.concat(page_commits)
        end
      end
      commits.filter_map { |commit| commit.dig("commit", "author", "email").to_s.split("@").last&.downcase }
    rescue GitHub::API::Error
      []
    end
  end

  sig { params(urls: T::Hash[Symbol, T.nilable(String)]).returns(T.nilable([Symbol, String])) }
  def self.commit_email_domain_match(urls)
    urls.each do |stanza, url|
      next unless url

      domain = url_domain(url)
      next if domain.nil? || git_forge_domain?(domain)
      next if pull_request_commit_email_domains.none? { |email_domain| domain_or_subdomain?(domain, email_domain) }

      return [stanza, domain]
    end
    nil
  end

  sig { params(urls: T::Hash[Symbol, T.nilable(String)]).returns(T.nilable(String)) }
  def self.self_submission_problem(urls)
    return if urls.values.compact.grep(Regexp.union(NOTABILITY_REPOSITORY_REGEXES.values)).any?

    match = commit_email_domain_match(urls)
    return if match.nil?

    stanza, domain = match
    "Self-submitted (a commit author's email address matches the `#{stanza}` domain `#{domain}`) " \
      "without a GitHub, GitLab, Bitbucket or Codeberg repository to assess its notability. " \
      "This is not an automatic rejection, but the pull request author must provide evidence that it is notable."
  end

  sig { params(submitter: T.nilable(String), repo_owner: String).returns(T::Boolean) }
  def self.self_submission?(submitter, repo_owner)
    return false if submitter.blank?
    return false if repo_owner.empty?

    submitter.casecmp?(repo_owner)
  end

  sig { params(repo_owner: String).returns(T::Boolean) }
  def self.self_submission_for_repo_owner?(repo_owner)
    return false if repo_owner.blank?

    submitter = pull_request_author
    return false if submitter.blank?

    key = repo_owner.downcase
    return @self_submission_cache.fetch(key) if @self_submission_cache.key?(key)

    @self_submission_cache[key] = self_submission?(submitter, repo_owner)
  end

  sig { params(thresholds: T::Hash[Symbol, Integer], self_submission: T::Boolean).returns(T::Hash[Symbol, Integer]) }
  def self.notability_thresholds_for(thresholds, self_submission)
    return thresholds unless self_submission

    thresholds.transform_values { |value| value * SELF_SUBMISSION_THRESHOLD_MULTIPLIER }
  end

  sig { params(keys: String).returns(T.nilable(String)) }
  private_class_method def self.github_event_pull_request_value(*keys)
    github_event_path = ENV.fetch("GITHUB_EVENT_PATH", nil)
    return if github_event_path.blank?

    JSON.parse(File.read(github_event_path)).dig("pull_request", *keys)
  rescue Errno::ENOENT, JSON::ParserError
    nil
  end

  sig { params(url: String).returns(T.nilable(String)) }
  private_class_method def self.url_domain(url)
    host = begin
      URI(url).host
    rescue URI::InvalidURIError
      nil
    end
    host.downcase.delete_prefix("www.") if host.present?
  end

  sig { params(domain: String).returns(T::Boolean) }
  private_class_method def self.git_forge_domain?(domain)
    GIT_FORGE_DOMAINS.any? { |forge| domain_or_subdomain?(domain, forge) }
  end

  sig { params(domain: String, parent: String).returns(T::Boolean) }
  private_class_method def self.domain_or_subdomain?(domain, parent)
    domain == parent || domain.end_with?(".#{parent}")
  end

  sig { params(product: String, cycle: String).returns(T.nilable(T::Hash[String, T.untyped])) }
  def self.eol_data(product, cycle)
    @eol_data ||= T.let({}, T.nilable(T::Hash[String, T.untyped]))
    key = "#{product}/#{cycle}"
    return @eol_data[key] if @eol_data.key?(key)

    result = Utils::Curl.curl_output(
      "--location",
      "https://endoflife.date/api/v1/products/#{product}/releases/#{cycle}",
    )
    return unless result.status.success?

    @eol_data[key] = begin
      JSON.parse(result.stdout)
    rescue JSON::ParserError
      nil
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

    return "#{tag} is a GitHub pre-release." if release["prerelease"] && [version, "all", "any"].exclude?(exception)

    if !release["prerelease"] && exception && [version, "any"].exclude?(exception)
      return "#{tag} is not a GitHub pre-release but '#{name}' is in the GitHub prerelease allowlist."
    end

    "#{tag} is a GitHub draft." if release["draft"]
  end

  sig { params(user: String, repo: String).returns(T.nilable(T::Hash[String, T.untyped])) }
  def self.gitlab_repo_data(user, repo)
    @gitlab_repo_data ||= T.let({}, T.nilable(T::Hash[String, T.untyped]))
    @gitlab_repo_data["#{user}/#{repo}"] ||= begin
      result = Utils::Curl.curl_output("https://gitlab.com/api/v4/projects/#{user}%2F#{repo}")
      json = JSON.parse(result.stdout) if result.status.success?
      json = nil if json&.dig("message")&.include?("404 Project Not Found")
      json
    end
  end

  sig { params(user: String, repo: String).returns(T.nilable(T::Hash[String, T.untyped])) }
  def self.forgejo_repo_data(user, repo)
    @forgejo_repo_data ||= T.let({}, T.nilable(T::Hash[String, T.untyped]))
    @forgejo_repo_data["#{user}/#{repo}"] ||= begin
      result = Utils::Curl.curl_output("https://codeberg.org/api/v1/repos/#{user}/#{repo}", "--fail")

      JSON.parse(result.stdout) if result.status.success?
    end
  end

  sig { params(user: String, repo: String, tag: String).returns(T.nilable(T::Hash[String, T.untyped])) }
  private_class_method def self.gitlab_release_data(user, repo, tag)
    id = "#{user}/#{repo}/#{tag}"
    @gitlab_release_data ||= T.let({}, T.nilable(T::Hash[String, T.untyped]))
    @gitlab_release_data[id] ||= begin
      result = Utils::Curl.curl_output(
        "https://gitlab.com/api/v4/projects/#{user}%2F#{repo}/releases/#{tag}", "--fail"
      )
      JSON.parse(result.stdout) if result.status.success?
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

  sig { params(user: String, repo: String, tag: String).returns(T.nilable(T::Hash[String, T.untyped])) }
  private_class_method def self.forgejo_release_data(user, repo, tag)
    id = "#{user}/#{repo}/#{tag}"
    @forgejo_release_data ||= T.let({}, T.nilable(T::Hash[String, T.untyped]))
    @forgejo_release_data[id] ||= begin
      result = Utils::Curl.curl_output(
        "https://codeberg.org/api/v1/repos/#{user}/#{repo}/releases/tags/#{tag}", "--fail"
      )
      JSON.parse(result.stdout) if result.status.success?
    end
  end

  sig {
    params(
      user: String, repo: String, tag: String, formula: T.nilable(Formula), cask: T.nilable(Cask::Cask),
    ).returns(
      T.nilable(String),
    )
  }
  def self.forgejo_release(user, repo, tag, formula: nil, cask: nil)
    release = forgejo_release_data(user, repo, tag)
    return unless release
    return unless release["prerelease"]

    exception, version = if formula
      [formula.tap&.audit_exception(:forgejo_prerelease_allowlist, formula.name), formula.version]
    elsif cask
      [cask.tap&.audit_exception(:forgejo_prerelease_allowlist, cask.token), cask.version]
    end
    return if [version, "all"].include?(exception)

    "#{tag} is a Forgejo pre-release."
  end

  sig { params(user: String, repo: String, self_submission: T::Boolean).returns(T.nilable(String)) }
  def self.github(user, repo, self_submission: false)
    metadata = github_repo_data(user, repo)

    return if metadata.nil?

    return "GitHub fork (not canonical repository)" if metadata["fork"]

    notability_thresholds = notability_thresholds_for(GITHUB_NOTABILITY_THRESHOLDS, self_submission)
    notability_prefix = if self_submission
      "Self-submitted GitHub repository not notable enough"
    else
      "GitHub repository not notable enough"
    end
    if (metadata["forks_count"] < notability_thresholds.fetch(:forks)) &&
       (metadata["subscribers_count"] < notability_thresholds.fetch(:watchers)) &&
       (metadata["stargazers_count"] < notability_thresholds.fetch(:stars))
      return "#{notability_prefix} (<#{notability_thresholds.fetch(:forks)} forks, " \
             "<#{notability_thresholds.fetch(:watchers)} watchers and " \
             "<#{notability_thresholds.fetch(:stars)} stars)"
    end

    age_days = (Date.today - Date.parse(metadata["created_at"])).to_i
    return if age_days >= 30

    "GitHub repository too new (#{age_days} days old, 30 days required)"
  end

  sig { params(user: String, repo: String, self_submission: T::Boolean).returns(T.nilable(String)) }
  def self.gitlab(user, repo, self_submission: false)
    metadata = gitlab_repo_data(user, repo)

    return if metadata.nil?

    return "GitLab fork (not canonical repository)" if metadata["fork"]

    notability_thresholds = notability_thresholds_for(GITLAB_NOTABILITY_THRESHOLDS, self_submission)
    notability_prefix = if self_submission
      "Self-submitted GitLab repository not notable enough"
    else
      "GitLab repository not notable enough"
    end
    if (metadata["forks_count"] < notability_thresholds.fetch(:forks)) &&
       (metadata["star_count"] < notability_thresholds.fetch(:stars))
      return "#{notability_prefix} (<#{notability_thresholds.fetch(:forks)} forks and " \
             "<#{notability_thresholds.fetch(:stars)} stars)"
    end

    age_days = (Date.today - Date.parse(metadata["created_at"])).to_i
    return if age_days >= 30

    "GitLab repository too new (#{age_days} days old, 30 days required)"
  end

  sig { params(user: String, repo: String, self_submission: T::Boolean).returns(T.nilable(String)) }
  def self.bitbucket(user, repo, self_submission: false)
    api_url = "https://api.bitbucket.org/2.0/repositories/#{user}/#{repo}"
    result = Utils::Curl.curl_output("--request", "GET", api_url)
    return unless result.status.success?

    metadata = JSON.parse(result.stdout)
    return if metadata.nil?

    return "Uses deprecated Mercurial support in Bitbucket" if metadata["scm"] == "hg"

    return "Bitbucket fork (not canonical repository)" unless metadata["parent"].nil?

    age_days = (Date.today - Date.parse(metadata["created_on"])).to_i
    return "Bitbucket repository too new (#{age_days} days old, 30 days required)" if age_days < 30

    forks_result = Utils::Curl.curl_output("--request", "GET", "#{api_url}/forks")
    return unless forks_result.status.success?

    watcher_result = Utils::Curl.curl_output("--request", "GET", "#{api_url}/watchers")
    return unless watcher_result.status.success?

    forks_metadata = JSON.parse(forks_result.stdout)
    return if forks_metadata.nil?

    watcher_metadata = JSON.parse(watcher_result.stdout)
    return if watcher_metadata.nil?

    notability_thresholds = notability_thresholds_for(BITBUCKET_NOTABILITY_THRESHOLDS, self_submission)
    return if forks_metadata["size"] >= notability_thresholds.fetch(:forks) ||
              watcher_metadata["size"] >= notability_thresholds.fetch(:watchers)

    notability_prefix = if self_submission
      "Self-submitted Bitbucket repository not notable enough"
    else
      "Bitbucket repository not notable enough"
    end
    "#{notability_prefix} (<#{notability_thresholds.fetch(:forks)} forks and " \
      "<#{notability_thresholds.fetch(:watchers)} watchers)"
  end

  sig { params(user: String, repo: String, self_submission: T::Boolean).returns(T.nilable(String)) }
  def self.forgejo(user, repo, self_submission: false)
    metadata = forgejo_repo_data(user, repo)
    return if metadata.nil?

    return "Forgejo fork (not canonical repository)" if metadata["fork"]

    notability_thresholds = notability_thresholds_for(FORGEJO_NOTABILITY_THRESHOLDS, self_submission)
    notability_prefix = if self_submission
      "Self-submitted Forgejo repository not notable enough"
    else
      "Forgejo repository not notable enough"
    end
    if (metadata["forks_count"] < notability_thresholds.fetch(:forks)) &&
       (metadata["watchers_count"] < notability_thresholds.fetch(:watchers)) &&
       (metadata["stars_count"] < notability_thresholds.fetch(:stars))
      return "#{notability_prefix} (<#{notability_thresholds.fetch(:forks)} forks, " \
             "<#{notability_thresholds.fetch(:watchers)} watchers and " \
             "<#{notability_thresholds.fetch(:stars)} stars)"
    end

    age_days = (Date.today - Date.parse(metadata["created_at"])).to_i
    return if age_days >= 30

    "Forgejo repository too new (#{age_days} days old, 30 days required)"
  end

  sig { params(url: String).returns(T.nilable(String)) }
  def self.github_tag_from_url(url)
    tag = url[%r{^https://github\.com/[\w-]+/[\w.-]+/archive/refs/tags/(.+)\.(?:tar\.gz|zip)$}, 1]
    tag || url[%r{^https://github\.com/[\w-]+/[\w.-]+/releases/download/([^/]+)/}, 1]
  end

  sig { params(url: String).returns(T.nilable(String)) }
  def self.gitlab_tag_from_url(url)
    url[%r{^https://gitlab\.com/(?:\w[\w.-]*/){2,}-/archive/([^/]+)/}, 1]
  end

  sig { params(url: String).returns(T.nilable(String)) }
  def self.forgejo_tag_from_url(url)
    url[%r{^https://codeberg\.org/[\w-]+/[\w.-]+/archive/(.+)\.(?:tar\.gz|zip)$}, 1]
  end

  sig { params(formula_or_cask: T.any(Formula, Cask::Cask)).returns(T.nilable(String)) }
  def self.livecheck_required_problem(formula_or_cask)
    reason = if formula_or_cask.livecheck.skip?
      "uses `skip` in its `livecheck` block"
    elsif !formula_or_cask.livecheck_defined? &&
          Homebrew::Livecheck.checkable_urls(formula_or_cask).none? { |url| Homebrew::Livecheck::Strategy.from_url(url).any? }
      "has no URL that `livecheck` can check without a `livecheck` block"
    end
    return if reason.nil?

    noun, nouns = formula_or_cask.is_a?(Formula) ? %w[formula formulae] : %w[cask casks]
    "New #{nouns} must have a working `livecheck` block but this #{noun} #{reason}. " \
      "See #{Formatter.url("https://docs.brew.sh/Brew-Livecheck")}"
  end

  sig { params(formula_or_cask: T.any(Formula, Cask::Cask)).returns(T.nilable(String)) }
  def self.check_deprecate_disable_reason(formula_or_cask)
    return if !formula_or_cask.deprecated? && !formula_or_cask.disabled?

    reason = formula_or_cask.deprecated? ? formula_or_cask.deprecation_reason : formula_or_cask.disable_reason
    return unless reason.is_a?(Symbol)

    reasons = if formula_or_cask.is_a?(Formula)
      DeprecateDisable::FORMULA_DEPRECATE_DISABLE_REASONS
    else
      DeprecateDisable::CASK_DEPRECATE_DISABLE_REASONS
    end

    "#{reason} is not a valid deprecate! or disable! reason" unless reasons.include?(reason)
  end
end
