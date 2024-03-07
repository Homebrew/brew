# typed: true
# frozen_string_literal: true

require "uri"
require "utils/github/actions"
require "utils/github/api"

require "system_command"

# Wrapper functions for the GitHub API.
#
# @api private
module GitHub
  extend SystemCommand::Mixin

  def self.check_runs(repo: nil, commit: nil, pull_request: nil)
    if pull_request
      repo = pull_request.fetch("base").fetch("repo").fetch("full_name")
      commit = pull_request.fetch("head").fetch("sha")
    end

    API.open_rest(url_to("repos", repo, "commits", commit, "check-runs"))
  end

  def self.create_check_run(repo:, data:)
    API.open_rest(url_to("repos", repo, "check-runs"), data: data)
  end

  def self.issues(repo:, **filters)
    uri = url_to("repos", repo, "issues")
    uri.query = URI.encode_www_form(filters)
    API.open_rest(uri)
  end

  def self.search_issues(query, **qualifiers)
    search_results_items("issues", query, **qualifiers)
  end

  def self.count_issues(query, **qualifiers)
    search_results_count("issues", query, **qualifiers)
  end

  def self.create_gist(files, description, private:)
    url = "#{API_URL}/gists"
    data = { "public" => !private, "files" => files, "description" => description }
    API.open_rest(url, data: data, scopes: CREATE_GIST_SCOPES)["html_url"]
  end

  def self.create_issue(repo, title, body)
    url = "#{API_URL}/repos/#{repo}/issues"
    data = { "title" => title, "body" => body }
    API.open_rest(url, data: data, scopes: CREATE_ISSUE_FORK_OR_PR_SCOPES)["html_url"]
  end

  def self.repository(user, repo)
    API.open_rest(url_to("repos", user, repo))
  end

  def self.issues_for_formula(name, tap: CoreTap.instance, tap_remote_repo: tap&.full_name, state: nil, type: nil)
    return [] unless tap_remote_repo

    search_issues(name, repo: tap_remote_repo, state: state, type: type, in: "title")
  end

  def self.user
    @user ||= API.open_rest("#{API_URL}/user")
  end

  def self.permission(repo, user)
    API.open_rest("#{API_URL}/repos/#{repo}/collaborators/#{user}/permission")
  end

  def self.write_access?(repo, user = nil)
    user ||= self.user["login"]
    ["admin", "write"].include?(permission(repo, user)["permission"])
  end

  def self.branch_exists?(user, repo, branch)
    API.open_rest("#{API_URL}/repos/#{user}/#{repo}/branches/#{branch}")
    true
  rescue API::HTTPNotFoundError
    false
  end

  def self.pull_requests(repo, **options)
    url = "#{API_URL}/repos/#{repo}/pulls?#{URI.encode_www_form(options)}"
    API.open_rest(url)
  end

  def self.merge_pull_request(repo, number:, sha:, merge_method:, commit_message: nil)
    url = "#{API_URL}/repos/#{repo}/pulls/#{number}/merge"
    data = { sha: sha, merge_method: merge_method }
    data[:commit_message] = commit_message if commit_message
    API.open_rest(url, data: data, request_method: :PUT, scopes: CREATE_ISSUE_FORK_OR_PR_SCOPES)
  end

  def self.print_pull_requests_matching(query, only = nil)
    open_or_closed_prs = search_issues(query, is: only, type: "pr", user: "Homebrew")

    open_prs, closed_prs = open_or_closed_prs.partition { |pr| pr["state"] == "open" }
                                             .map { |prs| prs.map { |pr| "#{pr["title"]} (#{pr["html_url"]})" } }

    if open_prs.present?
      ohai "Open pull requests"
      open_prs.each { |pr| puts pr }
    end

    if closed_prs.present?
      puts if open_prs.present?

      ohai "Closed pull requests"
      closed_prs.take(20).each { |pr| puts pr }

      puts "..." if closed_prs.count > 20
    end

    puts "No pull requests found for #{query.inspect}" if open_prs.blank? && closed_prs.blank?
  end

  def self.create_fork(repo, org: nil)
    url = "#{API_URL}/repos/#{repo}/forks"
    data = {}
    data[:organization] = org if org
    scopes = CREATE_ISSUE_FORK_OR_PR_SCOPES
    API.open_rest(url, data: data, scopes: scopes)
  end

  def self.fork_exists?(repo, org: nil)
    _, reponame = repo.split("/")

    username = org || API.open_rest(url_to("user")) { |json| json["login"] }
    json = API.open_rest(url_to("repos", username, reponame))

    return false if json["message"] == "Not Found"

    true
  end

  def self.create_pull_request(repo, title, head, base, body)
    url = "#{API_URL}/repos/#{repo}/pulls"
    data = { title: title, head: head, base: base, body: body, maintainer_can_modify: true }
    scopes = CREATE_ISSUE_FORK_OR_PR_SCOPES
    API.open_rest(url, data: data, scopes: scopes)
  end

  def self.private_repo?(full_name)
    uri = url_to "repos", full_name
    API.open_rest(uri) { |json| json["private"] }
  end

  def self.search_query_string(*main_params, **qualifiers)
    params = main_params

    if (args = qualifiers.fetch(:args, nil))
      params << if args.from && args.to
        "created:#{args.from}..#{args.to}"
      elsif args.from
        "created:>=#{args.from}"
      elsif args.to
        "created:<=#{args.to}"
      end
    end

    params += qualifiers.except(:args).flat_map do |key, value|
      Array(value).map { |v| "#{key.to_s.tr("_", "-")}:#{v}" }
    end

    "q=#{URI.encode_www_form_component(params.compact.join(" "))}&per_page=100"
  end

  def self.url_to(*subroutes)
    URI.parse([API_URL, *subroutes].join("/"))
  end

  def self.search(entity, *queries, **qualifiers)
    uri = url_to "search", entity
    uri.query = search_query_string(*queries, **qualifiers)
    API.open_rest(uri)
  end

  def self.search_results_items(entity, *queries, **qualifiers)
    json = search(entity, *queries, **qualifiers)
    json.fetch("items", [])
  end

  def self.search_results_count(entity, *queries, **qualifiers)
    json = search(entity, *queries, **qualifiers)
    json.fetch("total_count", 0)
  end

  def self.approved_reviews(user, repo, pull_request, commit: nil)
    query = <<~EOS
      { repository(name: "#{repo}", owner: "#{user}") {
          pullRequest(number: #{pull_request}) {
            reviews(states: APPROVED, first: 100) {
              nodes {
                author {
                  ... on User { email login name databaseId }
                  ... on Organization { email login name databaseId }
                }
                authorAssociation
                commit { oid }
              }
            }
          }
        }
      }
    EOS

    result = API.open_graphql(query, scopes: ["user:email"])
    reviews = result["repository"]["pullRequest"]["reviews"]["nodes"]

    valid_associations = %w[MEMBER OWNER]
    reviews.filter_map do |r|
      next if commit.present? && commit != r["commit"]["oid"]
      next unless valid_associations.include? r["authorAssociation"]

      email = r["author"]["email"].presence ||
              "#{r["author"]["databaseId"]}+#{r["author"]["login"]}@users.noreply.github.com"

      name = r["author"]["name"].presence ||
             r["author"]["login"]

      {
        "email" => email,
        "name"  => name,
        "login" => r["author"]["login"],
      }
    end
  end

  def self.dispatch_event(user, repo, event, **payload)
    url = "#{API_URL}/repos/#{user}/#{repo}/dispatches"
    API.open_rest(url, data:           { event_type: event, client_payload: payload },
                       request_method: :POST,
                       scopes:         CREATE_ISSUE_FORK_OR_PR_SCOPES)
  end

  def self.workflow_dispatch_event(user, repo, workflow, ref, **inputs)
    url = "#{API_URL}/repos/#{user}/#{repo}/actions/workflows/#{workflow}/dispatches"
    API.open_rest(url, data:           { ref: ref, inputs: inputs },
                       request_method: :POST,
                       scopes:         CREATE_ISSUE_FORK_OR_PR_SCOPES)
  end

  def self.get_release(user, repo, tag)
    url = "#{API_URL}/repos/#{user}/#{repo}/releases/tags/#{tag}"
    API.open_rest(url, request_method: :GET)
  end

  def self.get_latest_release(user, repo)
    url = "#{API_URL}/repos/#{user}/#{repo}/releases/latest"
    API.open_rest(url, request_method: :GET)
  end

  def self.generate_release_notes(user, repo, tag, previous_tag: nil)
    url = "#{API_URL}/repos/#{user}/#{repo}/releases/generate-notes"
    data = { tag_name: tag }
    data[:previous_tag_name] = previous_tag if previous_tag.present?
    API.open_rest(url, data: data, request_method: :POST, scopes: CREATE_ISSUE_FORK_OR_PR_SCOPES)
  end

  def self.create_or_update_release(user, repo, tag, id: nil, name: nil, body: nil, draft: false)
    url = "#{API_URL}/repos/#{user}/#{repo}/releases"
    method = if id
      url += "/#{id}"
      :PATCH
    else
      :POST
    end
    data = {
      tag_name: tag,
      name:     name || tag,
      draft:    draft,
    }
    data[:body] = body if body.present?
    API.open_rest(url, data: data, request_method: method, scopes: CREATE_ISSUE_FORK_OR_PR_SCOPES)
  end

  def self.upload_release_asset(user, repo, id, local_file: nil, remote_file: nil)
    url = "https://uploads.github.com/repos/#{user}/#{repo}/releases/#{id}/assets"
    url += "?name=#{remote_file}" if remote_file
    API.open_rest(url, data_binary_path: local_file, request_method: :POST, scopes: CREATE_ISSUE_FORK_OR_PR_SCOPES)
  end

  def self.get_workflow_run(user, repo, pull_request, workflow_id: "tests.yml", artifact_name: "bottles")
    scopes = CREATE_ISSUE_FORK_OR_PR_SCOPES

    # GraphQL unfortunately has no way to get the workflow yml name, so we need an extra REST call.
    workflow_api_url = "#{API_URL}/repos/#{user}/#{repo}/actions/workflows/#{workflow_id}"
    workflow_payload = API.open_rest(workflow_api_url, scopes: scopes)
    workflow_id_num = workflow_payload["id"]

    query = <<~EOS
      query ($user: String!, $repo: String!, $pr: Int!) {
        repository(owner: $user, name: $repo) {
          pullRequest(number: $pr) {
            commits(last: 1) {
              nodes {
                commit {
                  checkSuites(first: 100) {
                    nodes {
                      status,
                      workflowRun {
                        databaseId,
                        url,
                        workflow {
                          databaseId
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    EOS
    variables = {
      user: user,
      repo: repo,
      pr:   pull_request.to_i,
    }
    result = API.open_graphql(query, variables: variables, scopes: scopes)

    commit_node = result["repository"]["pullRequest"]["commits"]["nodes"].first
    check_suite = if commit_node.present?
      commit_node["commit"]["checkSuites"]["nodes"].select do |suite|
        suite.dig("workflowRun", "workflow", "databaseId") == workflow_id_num
      end
    else
      []
    end

    [check_suite, user, repo, pull_request, workflow_id, scopes, artifact_name]
  end

  def self.get_artifact_url(workflow_array)
    check_suite, user, repo, pr, workflow_id, scopes, artifact_name = *workflow_array
    if check_suite.empty?
      raise API::Error, <<~EOS
        No matching check suite found for these criteria!
          Pull request: #{pr}
          Workflow:     #{workflow_id}
      EOS
    end

    status = check_suite.last["status"].sub("_", " ").downcase
    if status != "completed"
      raise API::Error, <<~EOS
        The newest workflow run for ##{pr} is still #{status}!
          #{Formatter.url check_suite.last["workflowRun"]["url"]}
      EOS
    end

    run_id = check_suite.last["workflowRun"]["databaseId"]
    artifacts = API.open_rest("#{API_URL}/repos/#{user}/#{repo}/actions/runs/#{run_id}/artifacts", scopes: scopes)

    artifact = artifacts["artifacts"].select do |art|
      art["name"] == artifact_name
    end

    if artifact.empty?
      raise API::Error, <<~EOS
        No artifact with the name `#{artifact_name}` was found!
          #{Formatter.url check_suite.last["workflowRun"]["url"]}
      EOS
    end

    artifact.last["archive_download_url"]
  end

  def self.public_member_usernames(org, per_page: 100)
    url = "#{API_URL}/orgs/#{org}/public_members"
    members = []

    API.paginate_rest(url, per_page: per_page) do |result|
      result = result.map { |member| member["login"] }
      members.concat(result)

      return members if result.length < per_page
    end
  end

  def self.members_by_team(org, team)
    query = <<~EOS
        { organization(login: "#{org}") {
          teams(first: 100) {
            nodes {
              ... on Team { name }
            }
          }
          team(slug: "#{team}") {
            members(first: 100) {
              nodes {
                ... on User { login name }
              }
            }
          }
        }
      }
    EOS
    result = API.open_graphql(query, scopes: ["read:org", "user"])

    if result["organization"]["teams"]["nodes"].blank?
      raise API::Error,
            "Your token needs the 'read:org' scope to access this API"
    end
    raise API::Error, "The team #{org}/#{team} does not exist" if result["organization"]["team"].blank?

    result["organization"]["team"]["members"]["nodes"].to_h { |member| [member["login"], member["name"]] }
  end

  sig {
    params(user: String)
      .returns(
        T::Array[{
          closest_tier_monthly_amount: Integer,
          login:                       String,
          monthly_amount:              Integer,
          name:                        String,
        }],
      )
  }
  def self.sponsorships(user)
    has_next_page = T.let(true, T::Boolean)
    after = ""
    sponsorships = T.let([], T::Array[Hash])
    errors = T.let([], T::Array[Hash])
    while has_next_page
      query = <<~EOS
          { organization(login: "#{user}") {
            sponsorshipsAsMaintainer(first: 100 #{after}) {
              pageInfo {
                startCursor
                hasNextPage
                endCursor
              }
              totalCount
              nodes {
                tier {
                  monthlyPriceInDollars
                  closestLesserValueTier {
                    monthlyPriceInDollars
                  }
                }
                sponsorEntity {
                  __typename
                  ... on Organization { login name }
                  ... on User { login name }
                }
              }
            }
          }
        }
      EOS
      # Some organisations do not permit themselves to be queried through the
      # API like this and raise an error so handle these errors later.
      # This has been reported to GitHub.
      result = API.open_graphql(query, scopes: ["user"], raise_errors: false)
      errors += result["errors"] if result["errors"].present?

      current_sponsorships = result["data"]["organization"]["sponsorshipsAsMaintainer"]

      # The organisations mentioned above will show up as nil nodes.
      if (nodes = current_sponsorships["nodes"].compact.presence)
        sponsorships += nodes
      end

      if (page_info = current_sponsorships["pageInfo"].presence) &&
         page_info["hasNextPage"].presence
        after = %Q(, after: "#{page_info["endCursor"]}")
      else
        has_next_page = false
      end
    end

    # Only raise errors if we didn't get any sponsorships.
    if sponsorships.blank? && errors.present?
      raise API::Error, errors.map { |e| "#{e["type"]}: #{e["message"]}" }.join("\n")
    end

    sponsorships.map do |sponsorship|
      sponsor = sponsorship["sponsorEntity"]
      tier = sponsorship["tier"].presence || {}
      monthly_amount = tier["monthlyPriceInDollars"].presence || 0
      closest_tier = tier["closestLesserValueTier"].presence || {}
      closest_tier_monthly_amount = closest_tier["monthlyPriceInDollars"].presence || 0

      {
        name:                        sponsor["name"].presence || sponsor["login"],
        login:                       sponsor["login"],
        monthly_amount:              monthly_amount,
        closest_tier_monthly_amount: closest_tier_monthly_amount,
      }
    end
  end

  def self.get_repo_license(user, repo, ref: nil)
    url = "#{API_URL}/repos/#{user}/#{repo}/license"
    url += "?ref=#{ref}" if ref.present?
    response = API.open_rest(url)
    return unless response.key?("license")

    response["license"]["spdx_id"]
  rescue API::HTTPNotFoundError
    nil
  rescue API::AuthenticationFailedError => e
    raise unless e.message.match?(API::GITHUB_IP_ALLOWLIST_ERROR)
  end

  def self.pull_request_title_regex(name, version = nil)
    return /(^|\s)#{Regexp.quote(name)}(:|,|\s|$)/i if version.blank?

    /(^|\s)#{Regexp.quote(name)}(:|,|\s)(.*\s)?#{Regexp.quote(version)}(:|,|\s|$)/i
  end

  def self.fetch_pull_requests(name, tap_remote_repo, state: nil, version: nil)
    regex = pull_request_title_regex(name, version)
    query = "is:pr #{name} #{version}".strip

    issues_for_formula(query, tap_remote_repo: tap_remote_repo, state: state).select do |pr|
      pr["html_url"].include?("/pull/") && regex.match?(pr["title"])
    end
  rescue API::RateLimitExceededError => e
    opoo e.message
    []
  end

  # WARNING: The GitHub API returns results in a slightly different form here compared to `fetch_pull_requests`.
  def self.fetch_open_pull_requests(name, tap_remote_repo, version: nil)
    return [] if tap_remote_repo.blank?

    # Bust the cache every three minutes.
    cache_expiry = 3 * 60
    cache_epoch = Time.now - (Time.now.to_i % cache_expiry)
    cache_key = "#{tap_remote_repo}_#{cache_epoch.to_i}"

    @open_pull_requests ||= {}
    @open_pull_requests[cache_key] ||= begin
      owner, repo = tap_remote_repo.split("/")
      endpoint = "repos/#{owner}/#{repo}/pulls"
      query_parameters = ["state=open", "direction=desc"]
      pull_requests = []

      API.paginate_rest("#{API_URL}/#{endpoint}", additional_query_params: query_parameters.join("&")) do |page|
        pull_requests.concat(page)
      end

      pull_requests
    end

    regex = pull_request_title_regex(name, version)
    @open_pull_requests[cache_key].select { |pr| regex.match?(pr["title"]) }
  end

  def self.check_for_duplicate_pull_requests(name, tap_remote_repo, state:, file:, quiet:, version: nil)
    # `fetch_open_pull_requests` is more reliable but *really* slow, so let's use it only in CI.
    pull_requests = if state == "open" && ENV["CI"].present?
      fetch_open_pull_requests(name, tap_remote_repo, version: version)
    else
      fetch_pull_requests(name, tap_remote_repo, state: state, version: version)
    end

    pull_requests.select! do |pr|
      get_pull_request_changed_files(
        tap_remote_repo, pr["number"]
      ).any? { |f| f["filename"] == file }
    end
    return if pull_requests.blank?

    duplicates_message = <<~EOS
      These #{state} pull requests may be duplicates:
      #{pull_requests.map { |pr| "#{pr["title"]} #{pr["html_url"]}" }.join("\n")}
    EOS
    error_message = <<~EOS
      Duplicate PRs should not be opened.
      Manually open these PRs if you are sure that they are not duplicates.
    EOS

    if quiet
      odie error_message
    else
      odie <<~EOS
        #{duplicates_message.chomp}
        #{error_message}
      EOS
    end
  end

  def self.get_pull_request_changed_files(tap_remote_repo, pull_request)
    API.open_rest(url_to("repos", tap_remote_repo, "pulls", pull_request, "files"))
  end

  private_class_method def self.add_auth_token_to_url!(url)
    if API.credentials_type == :env_token
      url.sub!(%r{^https://github\.com/}, "https://#{API.credentials}@github.com/")
    end
    url
  end

  def self.forked_repo_info!(tap_remote_repo, org: nil)
    response = create_fork(tap_remote_repo, org: org)
    # GitHub API responds immediately but fork takes a few seconds to be ready.
    sleep 1 until fork_exists?(tap_remote_repo, org: org)
    remote_url = if system("git", "config", "--local", "--get-regexp", "remote..*.url", "git@github.com:.*")
      response.fetch("ssh_url")
    else
      add_auth_token_to_url!(response.fetch("clone_url"))
    end
    username = response.fetch("owner").fetch("login")
    [remote_url, username]
  end

  # @param commits data on commits to apply consisting of the commit message,
  #   the source file path, any additional files, and the old contents of file.
  #   Must be non-empty and all source file paths must be part of same git repo.
  sig {
    params(
      tap:             Tap,
      branch:          String,
      commits:         T::Array[[String, Pathname, T.nilable(T::Array[String]), String]],
      args:            T.untyped,
      pr_message:      T.nilable(String),
      tap_remote_repo: T.nilable(String),
      remote:          T.nilable(String),
      remote_branch:   T.nilable(String),
      previous_branch: T.nilable(String),
    ).void
  }
  def self.create_bump_pr(tap:, branch:, commits:, args:, pr_message: nil, tap_remote_repo: nil,
                          remote: nil, remote_branch: nil, previous_branch: nil)
    tap_remote_repo ||= tap.full_name
    remote ||= "origin"
    remote_branch ||= tap.git_repo.origin_branch_name
    previous_branch ||= "-"

    odie "Unable to create pull request with empty `commits`!" if commits.blank?
    git_dir = ""
    commits.each do |_, sourcefile_path, _, _|
      sourcefile_path.parent.cd do
        sourcefile_git_dir = T.cast(Utils.popen_read("git", "rev-parse", "--git-dir").chomp, String)
        if git_dir.empty?
          git_dir = sourcefile_git_dir
        elsif git_dir != sourcefile_git_dir
          commits.each { |_, sourcefile_path, _, old_contents| sourcefile_path.atomic_write(old_contents) }
          odie "Unable to create pull request with source files in different git repositories!"
        end
      end
    end

    shallow = !git_dir.empty? && File.exist?("#{git_dir}/shallow")
    remote_url = T.let(nil, T.nilable(String))
    username = T.let(nil, T.nilable(String))
    first_sourcefile_path = T.must(commits.first)[1]

    first_sourcefile_path.parent.cd do
      if args.dry_run? || (args.write_only? && !args.commit?)
        remote_url = if args.no_fork?
          Utils.popen_read("git", "remote", "get-url", "--push", "origin").chomp
        else
          fork_message = "try to fork repository with GitHub API" \
                         "#{" into `#{args.fork_org}` organization" if args.fork_org}"
          ohai fork_message
          "FORK_URL"
        end
        ohai "git fetch --unshallow origin" if shallow
        ohai "git checkout --no-track -b #{branch} #{remote}/#{remote_branch}"
      elsif !args.commit?
        if args.no_fork?
          remote_url = Utils.popen_read("git", "remote", "get-url", "--push", "origin").chomp
          add_auth_token_to_url!(remote_url)
          username = tap.user
        else
          begin
            remote_url, username = forked_repo_info!(tap_remote_repo, org: args.fork_org)
          rescue *API::ERRORS => e
            commits.each { |_, sourcefile_path, _, old_contents| sourcefile_path.atomic_write(old_contents) }
            odie "Unable to fork: #{e.message}!"
          end
        end

        safe_system "git", "fetch", "--unshallow", "origin" if shallow
        safe_system "git", "checkout", "--no-track", "-b", branch, "#{remote}/#{remote_branch}"
      end
    end

    commits.each do |commit_message, sourcefile_path, additional_files, _old_contents|
      sourcefile_path.parent.cd do
        changed_files = [sourcefile_path]
        changed_files += additional_files if additional_files.present?

        if args.dry_run? || (args.write_only? && !args.commit?)
          ohai "git add #{changed_files.join(" ")}"
          ohai "git commit --no-edit --verbose --message='#{commit_message}' " \
               "-- #{changed_files.join(" ")}"
        else
          safe_system "git", "add", *changed_files
          safe_system "git", "commit", "--no-edit", "--verbose",
                      "--message=#{commit_message}",
                      "--", *changed_files
        end
      end
    end

    if args.dry_run? || (args.write_only? && !args.commit?)
      ohai "git push --set-upstream #{remote_url} #{branch}:#{branch}"
      ohai "git checkout --quiet #{previous_branch}"
      ohai "create pull request with GitHub API (base branch: #{remote_branch})"
      return
    end
    return if args.commit?

    first_sourcefile_path.parent.cd do
      system_command!("git", args:         ["push", "--set-upstream", remote_url, "#{branch}:#{branch}"],
                             print_stdout: true)
      safe_system "git", "checkout", "--quiet", previous_branch
      pr_message = <<~EOS
        #{pr_message}
      EOS

      commit_messages = commits.map(&:first)
      if commit_messages.length > 1
        pr_message = <<~EOS
          #{commit_messages.drop(1).map { |m| "* #{m}" }.join("\n")}

          ---

          #{pr_message}
        EOS
      end

      user_message = args.message
      if user_message
        pr_message = <<~EOS
          #{user_message}

          ---

          #{pr_message}
        EOS
      end

      begin
        url = create_pull_request(tap_remote_repo, commit_messages.first,
                                  "#{username}:#{branch}", remote_branch, pr_message)["html_url"]
        if args.no_browse?
          puts url
        else
          exec_browser url
        end
      rescue *API::ERRORS => e
        odie "Unable to open pull request: #{e.message}!"
      end
    end
  end

  def self.pull_request_commits(user, repo, pull_request, per_page: 100)
    pr_data = API.open_rest(url_to("repos", user, repo, "pulls", pull_request))
    commits_api = pr_data["commits_url"]
    commit_count = pr_data["commits"]
    commits = []

    if commit_count > API_MAX_ITEMS
      raise API::Error, "Getting #{commit_count} commits would exceed limit of #{API_MAX_ITEMS} API items!"
    end

    API.paginate_rest(commits_api, per_page: per_page) do |result, page|
      commits.concat(result.map { |c| c["sha"] })

      return commits if commits.length == commit_count

      if result.empty? || page * per_page >= commit_count
        raise API::Error, "Expected #{commit_count} commits but actually got #{commits.length}!"
      end
    end
  end

  def self.pull_request_labels(user, repo, pull_request)
    pr_data = API.open_rest(url_to("repos", user, repo, "pulls", pull_request))
    pr_data["labels"].map { |label| label["name"] }
  end

  def self.last_commit(user, repo, ref, version)
    return if Homebrew::EnvConfig.no_github_api?

    output, _, status = Utils::Curl.curl_output(
      "--silent", "--head", "--location",
      "--header", "Accept: application/vnd.github.sha",
      url_to("repos", user, repo, "commits", ref).to_s
    )

    return unless status.success?

    commit = output[/^ETag: "(\h+)"/, 1]
    return if commit.blank?

    version.update_commit(commit)
    commit
  end

  def self.multiple_short_commits_exist?(user, repo, commit)
    return false if Homebrew::EnvConfig.no_github_api?

    output, _, status = Utils::Curl.curl_output(
      "--silent", "--head", "--location",
      "--header", "Accept: application/vnd.github.sha",
      url_to("repos", user, repo, "commits", commit).to_s
    )

    return true unless status.success?
    return true if output.blank?

    output[/^Status: (200)/, 1] != "200"
  end

  def self.repo_commits_for_user(nwo, user, filter, args, max)
    return if Homebrew::EnvConfig.no_github_api?

    params = ["#{filter}=#{user}"]
    params << "since=#{DateTime.parse(args.from).iso8601}" if args.from
    params << "until=#{DateTime.parse(args.to).iso8601}" if args.to

    commits = []
    API.paginate_rest("#{API_URL}/repos/#{nwo}/commits", additional_query_params: params.join("&")) do |result|
      commits.concat(result.map { |c| c["sha"] })
      if max.present? && commits.length >= max
        opoo "#{user} exceeded #{max} #{nwo} commits as #{filter}, stopped counting!"
        break
      end
    end
    commits
  end

  def self.count_repo_commits(nwo, user, args, max: nil)
    odie "Cannot count commits, HOMEBREW_NO_GITHUB_API set!" if Homebrew::EnvConfig.no_github_api?

    author_shas = repo_commits_for_user(nwo, user, "author", args, max)
    committer_shas = repo_commits_for_user(nwo, user, "committer", args, max)
    return [0, 0] if author_shas.blank? && committer_shas.blank?

    author_count = author_shas.count
    # Only count commits where the author and committer are different.
    committer_count = committer_shas.difference(author_shas).count

    [author_count, committer_count]
  end
end
