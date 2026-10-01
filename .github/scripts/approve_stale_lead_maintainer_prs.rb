# typed: strict
# frozen_string_literal: true

require "date"
require "json"
require "open3"
require "sorbet-runtime"
require "time"
require "uri"

# Approves stale lead maintainer PRs from GitHub Actions.
class StaleLeadMaintainerPrApproval
  # Standalone Ruby does not include T::Sig in Module.
  extend T::Sig # rubocop:disable Sorbet/RedundantExtendTSig

  API_URL = "https://api.github.com"
  MAX_PER_PAGE = 100

  REPOSITORY = "Homebrew/brew"
  GITHUB_ACTIONS_URL = "https://github.com/apps/github-actions"
  APPROVABLE_CHECK_RUN_CONCLUSIONS = ["success", "neutral", "skipped"].freeze
  HUMAN_REVIEW_WINDOW_HOURS = 48
  SENSITIVE_PATH_PREFIXES = [".github/"].freeze
  SENSITIVE_PATHS = [
    "Library/Homebrew/utils/github.rb",
    "README.md",
  ].freeze
  REPORT_BRANCH = "approve-stale-lead-maintainer-prs"
  GitHubPayload = T.type_alias { T::Hash[String, BasicObject] }
  GitHubPayloads = T.type_alias { T::Array[GitHubPayload] }
  GitHubPage = T.type_alias { T.any(GitHubPayload, GitHubPayloads) }
  GitHubResult = T.type_alias { T.any(GitHubPayload, GitHubPayloads) }
  RequestData = T.type_alias { T::Hash[Symbol, String] }

  # Recent qualifying approval for another Homebrew/brew PR.
  class RecentApproval < T::Struct
    const :number, Integer
    const :url, String
  end

  # Decision facts for a stale lead maintainer PR.
  class PullRequestFacts < T::Struct
    const :number, Integer
    const :title, String
    const :author, String
    const :created_at, Time
    const :head_sha, String
    const :pr_url, String
    const :checks_url, String
    const :author_url, String
    const :not_from_fork, T::Boolean
    const :draft, T::Boolean
    const :weekday_approval_window, T::Boolean
    const :old_enough_for_approval, T::Boolean
    prop :lead_maintainer, T::Boolean, default: false
    prop :lead_maintainer_checked, T::Boolean, default: false
    prop :approved_another_pr, T::Boolean, default: false
    prop :approved_another_pr_checked, T::Boolean, default: false
    prop :approved_pr_number, String, default: ""
    prop :approved_pr_url, String, default: ""
    prop :no_human_review_since_creation, T::Boolean, default: false
    prop :reviews_checked, T::Boolean, default: false
    prop :human_reviews_since_creation, T::Array[String], default: []
    prop :copilot_reviewed, T::Boolean, default: false
    prop :already_approved, T::Boolean, default: false
    prop :sensitive_files_unchanged, T::Boolean, default: false
    prop :sensitive_files_checked, T::Boolean, default: false
    prop :changed_sensitive_files, T::Array[String], default: []
    prop :ci_passing, T::Boolean, default: false
    prop :ci_checked, T::Boolean, default: false
    prop :failing_ci_jobs, T::Array[String], default: []
    prop :requirements_met, T::Boolean, default: false
    prop :should_approve, T::Boolean, default: false
    prop :failure_messages, T::Array[String], default: []
  end

  sig { void }
  def initialize
    @repository = T.let(ENV.fetch("GITHUB_REPOSITORY"), String)
    raise "This workflow must only run in #{REPOSITORY}." if @repository != REPOSITORY

    @server_url = T.let(ENV.fetch("GITHUB_SERVER_URL", "https://github.com"), String)
    @event_name = T.let(ENV.fetch("GITHUB_EVENT_NAME"), String)
    @pull_request_number = T.let(ENV.fetch("PR_NUMBER", ""), String)
    lead_maintainers_line = File.read("README.md").each_line.find do |line|
      line.start_with?("Homebrew's [Lead Maintainers]")
    end
    raise "Could not find lead maintainers in README.md." if lead_maintainers_line.nil?

    lead_maintainers = T.let({}, T::Hash[String, T::Boolean])
    lead_maintainers_line.scan(%r{https://github\.com/([A-Za-z0-9-]+)}) do |login|
      lead_maintainers[T.cast(login.fetch(0), String)] = true
    end
    @lead_maintainers = T.let(lead_maintainers, T::Hash[String, T::Boolean])
    @recent_approval_issues = T.let({}, T::Hash[String, GitHubPayloads])
    @recent_approval_search_complete = T.let({}, T::Hash[String, T::Boolean])
    @recent_approval_search_pages = T.let({}, T::Hash[String, Integer])
    @recent_approval_checks = T.let({}, T::Hash[[String, Integer], T.any(RecentApproval, FalseClass)])
    @recent_approval_results = T.let({}, T::Hash[String, T::Array[RecentApproval]])
    @reviews = T.let({}, T::Hash[Integer, GitHubPayloads])
    @printed_pull_request_summary = T.let(false, T::Boolean)
    @weekday_approval_window = T.let((1..5).cover?(Time.now.utc.wday), T::Boolean)
  end

  sig { void }
  def run
    if @event_name == "push"
      report
    else
      approve
    end
  end

  private

  sig { void }
  def approve
    if @event_name == "workflow_dispatch" && @pull_request_number.empty?
      raise "PR_NUMBER must be set for workflow_dispatch."
    end

    pull_requests = if @pull_request_number.empty?
      paginated_rest("#{API_URL}/repos/#{@repository}/pulls", "state=open")
    else
      [T.cast(rest("#{API_URL}/repos/#{@repository}/pulls/#{Integer(@pull_request_number)}"), GitHubPayload)]
    end
    puts "Evaluating #{pull_requests.length} pull request(s)."
    facts = pull_requests.map { |pull_request| evaluate(pull_request, exhaustive: false) }

    if @event_name == "workflow_dispatch"
      requested = facts.fetch(0)
      unless requested.should_approve
        requested.failure_messages.each { |failure| puts "::error::#{failure}" }
        exit 1
      end
    end

    approval_facts = facts.select(&:should_approve)
    puts "Approving #{approval_facts.length} pull request(s)."
    approval_facts.each do |data|
      puts "Approving pull request ##{data.number}."
      rest(
        "#{API_URL}/repos/#{@repository}/pulls/#{data.number}/reviews",
        data:           {
          event: "APPROVE",
          body:  <<~MARKDOWN,
            Automated approval by [github-actions\\[bot\\]](#{GITHUB_ACTIONS_URL}) for [##{data.number}](#{data.pr_url}) because all requirements are met:

            - [##{data.number}](#{data.pr_url}) is not from a fork.
            - [##{data.number}](#{data.pr_url}) is not a draft.
            - The approval workflow is running on a weekday.
            - [@#{data.author}](#{data.author_url}) is listed as a lead maintainer in [README.md](#{@server_url}/#{@repository}/blob/HEAD/README.md).
            - [@#{data.author}](#{data.author_url}) approved Homebrew/brew PR [##{data.approved_pr_number}](#{data.approved_pr_url}) in the last 7 days.
            - [##{data.number}](#{data.pr_url}) was created at least #{HUMAN_REVIEW_WINDOW_HOURS} hours ago and has had no human review since creation.
            - Copilot has already reviewed [##{data.number}](#{data.pr_url}).
            - [##{data.number}](#{data.pr_url}) does not modify `.github/` or other sensitive files.
            - All [CI jobs](#{data.checks_url}) are passing, including non-required jobs.
          MARKDOWN
        },
        request_method: :POST,
      )
      puts "Approved pull request ##{data.number}."
    end
    summarise(facts)
  end

  sig { void }
  def report
    branch = ENV.fetch("GITHUB_REF_NAME", REPORT_BRANCH)
    query = URI.encode_www_form(state: "open", head: "Homebrew:#{branch}", per_page: 1)
    pull_requests = T.cast(rest("#{API_URL}/repos/#{@repository}/pulls?#{query}"), GitHubPayloads)
    raise "No open pull request found for branch #{branch}." if pull_requests.empty?

    data = evaluate(pull_requests.fetch(0), exhaustive: true)

    puts "Reported stale lead maintainer PR approval facts for pull request ##{data.number}."
  end

  sig { params(pull_request: GitHubPayload, exhaustive: T::Boolean).returns(PullRequestFacts) }
  def evaluate(pull_request, exhaustive:)
    number = T.cast(pull_request.fetch("number"), Integer)
    title = T.cast(pull_request.fetch("title"), String)
    author = T.cast(T.cast(pull_request.fetch("user"), GitHubPayload).fetch("login"), String)
    created_at = Time.parse(T.cast(pull_request.fetch("created_at"), String))
    draft = T.cast(pull_request.fetch("draft"), T::Boolean)
    head = T.cast(pull_request.fetch("head"), GitHubPayload)
    head_sha = T.cast(head.fetch("sha"), String)
    head_repo = T.cast(head.fetch("repo"), GitHubPayload)
    data = PullRequestFacts.new(
      number:,
      title:,
      author:,
      created_at:,
      head_sha:,
      pr_url:                  "#{@server_url}/#{@repository}/pull/#{number}",
      checks_url:              "#{@server_url}/#{@repository}/commit/#{head_sha}/checks",
      author_url:              "#{@server_url}/#{author}",
      not_from_fork:           T.cast(head_repo.fetch("full_name"), String) == @repository &&
                     !T.cast(head_repo.fetch("fork"), T::Boolean),
      draft:,
      weekday_approval_window: @weekday_approval_window,
      old_enough_for_approval: created_at <= Time.now.utc - (HUMAN_REVIEW_WINDOW_HOURS * 60 * 60),
    )
    raw_failures = []
    raw_failures << "Pull request ##{data.number} is from a fork." unless data.not_from_fork
    raw_failures << "Pull request ##{data.number} is a draft." if data.draft
    return finish(data, raw_failures) if raw_failures.any?

    if !exhaustive && !data.weekday_approval_window
      return finish(data, ["Stale lead maintainer PR approvals do not run on Saturdays or Sundays."])
    end

    data.lead_maintainer_checked = true
    data.lead_maintainer = @lead_maintainers.fetch(data.author, false)
    if !exhaustive && !data.lead_maintainer
      return finish(data, ["@#{data.author} is not listed as a lead maintainer in README.md."])
    end

    approved_pr = T.let(
      @recent_approval_results[data.author]&.find { |approval| approval.number != data.number },
      T.nilable(RecentApproval),
    )
    unless approved_pr
      @recent_approval_results[data.author] ||= []
      @recent_approval_issues[data.author] ||= []

      loop do
        @recent_approval_issues.fetch(data.author).each do |issue|
          number = T.cast(issue.fetch("number"), Integer)
          next if number == data.number

          unless @recent_approval_checks.key?([data.author, number])
            cutoff = Time.now.utc - (7 * 24 * 60 * 60)
            @recent_approval_checks[[data.author, number]] = if reviews_for(number).any? do |review|
              review_user = T.cast(review.fetch("user"),
                                   GitHubPayload)
              T.cast(review_user.fetch("login"), String) ==
              data.author &&
              T.cast(review.fetch("state"), String) == "APPROVED" &&
              Time.parse(
                T.cast(review.fetch("submitted_at"), String),
              ) >= cutoff
            end
              RecentApproval.new(
                number:,
                url:    "#{@server_url}/#{@repository}/pull/#{number}",
              )
            else
              false
            end
          end

          approval = @recent_approval_checks.fetch([data.author, number])
          next unless approval

          approval_results = @recent_approval_results.fetch(data.author)
          approval_results << approval unless approval_results.include?(approval)
          approved_pr = approval
          break
        end
        break if approved_pr || @recent_approval_search_complete[data.author]

        page = @recent_approval_search_pages.fetch(data.author, 0) + 1
        cutoff_date = (Time.now.utc - (7 * 24 * 60 * 60)).to_date.iso8601
        query = "repo:#{@repository} is:pr reviewed-by:#{data.author} review:approved updated:>=#{cutoff_date}"
        issues = T.cast(
          T.cast(
            rest(
              "#{API_URL}/search/issues?#{URI.encode_www_form(q: query, per_page: MAX_PER_PAGE, page:)}",
            ),
            GitHubPayload,
          ).fetch("items"),
          GitHubPayloads,
        )
        @recent_approval_search_pages[data.author] = page
        @recent_approval_issues.fetch(data.author).concat(issues)
        @recent_approval_search_complete[data.author] = true if issues.length < MAX_PER_PAGE
      end
    end
    data.approved_another_pr_checked = true
    data.approved_another_pr = !approved_pr.nil?
    data.approved_pr_number = approved_pr&.number.to_s
    data.approved_pr_url = approved_pr&.url.to_s
    if !exhaustive && !data.approved_another_pr
      return finish(data, [
        "@#{data.author} has not approved another Homebrew/brew PR in the last 7 days.",
      ])
    end

    if !exhaustive && !data.old_enough_for_approval
      return finish(data, [
        "Pull request ##{data.number} was created less than #{HUMAN_REVIEW_WINDOW_HOURS} hours ago.",
      ])
    end

    reviews = reviews_for(data.number)
    data.reviews_checked = true
    data.human_reviews_since_creation = reviews.filter_map do |review|
      review_user = T.cast(review.fetch("user"), GitHubPayload)
      submitted_at = Time.parse(T.cast(review.fetch("submitted_at"), String))
      next if submitted_at < data.created_at
      next if T.cast(review_user.fetch("type"), String) == "Bot"

      "@#{T.cast(review_user.fetch("login"), String)} #{T.cast(review.fetch("state"), String).downcase} " \
        "at #{submitted_at.utc.iso8601}"
    end
    data.no_human_review_since_creation = data.human_reviews_since_creation.empty?
    data.copilot_reviewed = reviews.any? do |review|
      review_user = T.cast(review.fetch("user"), GitHubPayload)
      T.cast(review_user.fetch("type"), String) == "Bot" &&
        T.cast(review_user.fetch("login"), String).downcase.include?("copilot")
    end
    data.already_approved = reviews.any? do |review|
      review_user = T.cast(review.fetch("user"), GitHubPayload)
      T.cast(review_user.fetch("login"), String) == "github-actions[bot]" &&
        T.cast(review.fetch("state"), String) == "APPROVED" &&
        T.cast(review.fetch("commit_id"), String) == data.head_sha
    end
    if !exhaustive &&
       (!data.old_enough_for_approval || !data.no_human_review_since_creation || !data.copilot_reviewed ||
        data.already_approved)
      return finish(data, failures_for(data, include_ci: false))
    end

    changed_files = paginated_rest("#{API_URL}/repos/#{@repository}/pulls/#{data.number}/files")
    data.sensitive_files_checked = true
    data.changed_sensitive_files = changed_files.filter_map do |file|
      filename = T.cast(file.fetch("filename"), String)
      # Homebrew's core extensions are not available in this standalone script.
      # rubocop:disable Homebrew/NegateInclude
      next if SENSITIVE_PATH_PREFIXES.none? { |prefix| filename.start_with?(prefix) } &&
              !SENSITIVE_PATHS.include?(filename)
      # rubocop:enable Homebrew/NegateInclude

      filename
    end
    data.sensitive_files_unchanged = data.changed_sensitive_files.empty?
    if !exhaustive && !data.sensitive_files_unchanged
      return finish(data,
                    failures_for(data, include_ci: false))
    end

    check_runs = paginated_rest("#{API_URL}/repos/#{@repository}/commits/#{data.head_sha}/check-runs")
                 .flat_map do |page|
                   T.cast(page.fetch("check_runs"), GitHubPayloads)
                 end
    commit_status = T.cast(rest("#{API_URL}/repos/#{@repository}/commits/#{data.head_sha}/status"),
                           GitHubPayload)
    data.ci_checked = true
    data.failing_ci_jobs = check_runs.filter_map do |check_run|
      status = T.cast(check_run.fetch("status"), String)
      conclusion = T.cast(check_run.fetch("conclusion", nil), T.nilable(String))
      next if status == "completed" && !conclusion.nil? && APPROVABLE_CHECK_RUN_CONCLUSIONS.include?(conclusion)

      name = T.cast(check_run.fetch("name"), String)
      url = T.cast(check_run.fetch("html_url", nil), T.nilable(String))
      "#{name}: #{status}#{"/#{conclusion}" unless conclusion.nil?}" \
        "#{" (#{url})" unless url.nil?}"
    end
    data.failing_ci_jobs << "No check runs found." if check_runs.empty?
    T.cast(commit_status.fetch("statuses"), GitHubPayloads).each do |status|
      next if T.cast(status.fetch("state"), String) == "success"

      context = T.cast(status.fetch("context"), String)
      url = T.cast(status.fetch("target_url", nil), T.nilable(String))
      data.failing_ci_jobs << "#{context}: #{T.cast(status.fetch("state"), String)}" \
                              "#{" (#{url})" unless url.nil?}"
    end
    data.ci_passing = data.failing_ci_jobs.empty?

    finish(data, failures_for(data))
  end

  sig { params(data: PullRequestFacts, failure_messages: T::Array[String]).returns(PullRequestFacts) }
  def finish(data, failure_messages)
    data.requirements_met = data.not_from_fork &&
                            !data.draft &&
                            data.weekday_approval_window &&
                            data.lead_maintainer &&
                            data.approved_another_pr &&
                            data.old_enough_for_approval &&
                            data.no_human_review_since_creation &&
                            data.copilot_reviewed &&
                            data.sensitive_files_unchanged &&
                            data.ci_passing
    data.should_approve = data.requirements_met && !data.already_approved
    data.failure_messages = failure_messages
    puts if @printed_pull_request_summary
    @printed_pull_request_summary = true
    result = if @event_name == "push"
      data.should_approve ? "would approve" : "would not approve"
    elsif data.should_approve
      "will approve"
    else
      "will not approve"
    end
    puts "==> Pull request ##{data.number}: #{data.title}"
    puts "- Result: #{result}"
    puts "- Author: @#{data.author}"
    puts "- Not from a fork: #{status_label(data.not_from_fork)}"
    puts "- Not a draft: #{status_label(!data.draft)}"
    puts "- Weekday approval window: #{status_label(data.weekday_approval_window)}"
    puts "- Created at: #{data.created_at.utc.iso8601}"
    puts "- Created at least #{HUMAN_REVIEW_WINDOW_HOURS} hours ago: #{status_label(data.old_enough_for_approval)}"
    lead_maintainer = data.lead_maintainer_checked ? data.lead_maintainer : nil
    puts "- Author listed as a lead maintainer in README.md: #{status_label(lead_maintainer)}"
    approved_another_pr = data.approved_another_pr_checked ? data.approved_another_pr : nil
    puts "- Author approved another Homebrew/brew PR in the last 7 days: #{status_label(approved_another_pr)}"
    no_human_review_since_creation = data.reviews_checked ? data.no_human_review_since_creation : nil
    puts "- No human review since creation: #{status_label(no_human_review_since_creation)}"
    if data.reviews_checked
      puts "- Human reviews since creation:"
      if data.human_reviews_since_creation.empty?
        puts "  - none"
      else
        data.human_reviews_since_creation.each { |review| puts "  - #{review}" }
      end
    else
      puts "- Human reviews since creation: not checked"
    end
    puts "- Copilot reviewed: #{status_label(data.reviews_checked ? data.copilot_reviewed : nil)}"
    sensitive_files_unchanged = data.sensitive_files_checked ? data.sensitive_files_unchanged : nil
    puts "- .github/ and sensitive files unchanged: #{status_label(sensitive_files_unchanged)}"
    if data.sensitive_files_checked && !data.changed_sensitive_files.empty?
      puts "- Changed .github/ or sensitive files:"
      data.changed_sensitive_files.each { |file| puts "  - #{file}" }
    end
    puts "- CI passing: #{status_label(data.ci_checked ? data.ci_passing : nil)}"
    if data.ci_checked
      puts "- Failing CI jobs:"
      if data.failing_ci_jobs.empty?
        puts "  - none"
      else
        data.failing_ci_jobs.each { |job| puts "  - #{job}" }
      end
    else
      puts "- Failing CI jobs: not checked"
    end
    already_approved = data.reviews_checked ? data.already_approved : nil
    puts "- Already approved by github-actions[bot] for this commit: #{status_label(already_approved)}"
    data.failure_messages.each { |failure| puts "- Failure: #{failure}" }
    data
  end

  sig { params(value: T.nilable(T::Boolean)).returns(String) }
  def status_label(value)
    return "not checked" if value.nil?

    value.to_s
  end

  sig { params(data: PullRequestFacts, include_ci: T::Boolean).returns(T::Array[String]) }
  def failures_for(data, include_ci: true)
    failures = []
    failures << "Pull request ##{data.number} is from a fork." unless data.not_from_fork
    failures << "Pull request ##{data.number} is a draft." if data.draft
    unless data.weekday_approval_window
      failures << "Stale lead maintainer PR approvals do not run on Saturdays or Sundays."
    end
    failures << "@#{data.author} is not listed as a lead maintainer in README.md." unless data.lead_maintainer
    unless data.approved_another_pr
      failures << "@#{data.author} has not approved another Homebrew/brew PR in the last 7 days."
    end
    unless data.old_enough_for_approval
      failures << "Pull request ##{data.number} was created less than #{HUMAN_REVIEW_WINDOW_HOURS} hours ago."
    end
    unless data.no_human_review_since_creation
      failures << "Pull request ##{data.number} has a human review since creation."
    end
    failures << "Copilot has not reviewed pull request ##{data.number}." unless data.copilot_reviewed
    unless data.sensitive_files_unchanged
      failures << "Pull request ##{data.number} changes .github/ or other sensitive files: " \
                  "#{data.changed_sensitive_files.join(", ")}."
    end
    failures << "Not all CI jobs are passing for pull request ##{data.number}." if include_ci && !data.ci_passing
    if data.already_approved
      failures << "github-actions[bot] has already approved pull request ##{data.number} for this commit."
    end
    failures
  end

  sig { params(facts: T::Array[PullRequestFacts]).void }
  def summarise(facts)
    summary_path = ENV.fetch("GITHUB_STEP_SUMMARY", nil)
    return if summary_path.nil? || summary_path.match?(/\A[[:space:]]*\z/)

    File.open(summary_path, "a") do |summary|
      summary.puts "## Stale lead maintainer PR approval"
      summary.puts
      facts.each do |data|
        summary.puts "### [##{data.number}](#{data.pr_url})"
        summary.puts
        summary.puts "- Pull request: [##{data.number}](#{data.pr_url})"
        summary.puts "- Author: [@#{data.author}](#{data.author_url})"
        summary.puts "- Not from a fork: #{data.not_from_fork}"
        summary.puts "- Not a draft: #{!data.draft}"
        summary.puts "- Weekday approval window: #{data.weekday_approval_window}"
        summary.puts "- Created at: #{data.created_at.utc.iso8601}"
        summary.puts "- Created at least #{HUMAN_REVIEW_WINDOW_HOURS} hours ago: " \
                     "#{data.old_enough_for_approval}"
        summary.puts "- [@#{data.author}](#{data.author_url}) is listed as a lead maintainer in " \
                     "[README.md](#{@server_url}/#{@repository}/blob/HEAD/README.md): #{data.lead_maintainer}"
        summary.puts "- [@#{data.author}](#{data.author_url}) approved another " \
                     "[Homebrew/brew PR](#{@server_url}/#{@repository}/pulls) in the last 7 days: " \
                     "#{data.approved_another_pr} (#{approved_pr_link(data)})"
        summary.puts "- No human review on [##{data.number}](#{data.pr_url}) since creation: " \
                     "#{data.no_human_review_since_creation}"
        summary.puts "- Copilot has reviewed [##{data.number}](#{data.pr_url}): " \
                     "#{data.copilot_reviewed}"
        summary.puts "- `.github/` and sensitive files are unchanged in " \
                     "[##{data.number}](#{data.pr_url}): " \
                     "#{data.sensitive_files_unchanged}"
        summary.puts "- All [CI jobs](#{data.checks_url}) are passing: #{data.ci_passing}"
        summary.puts "- Requirements met: #{data.requirements_met}"
        summary.puts "- Already approved by [github-actions\\[bot\\]](#{GITHUB_ACTIONS_URL}) for " \
                     "`#{data.head_sha}`: #{data.already_approved}"
        summary.puts "- Eligible for approval: #{data.should_approve}"
        summary.puts "- Approved by this run: #{data.should_approve}"
        summary.puts
      end
    end
  end

  sig { params(data: PullRequestFacts).returns(String) }
  def approved_pr_link(data)
    return "none" if data.approved_pr_number.empty?

    "[##{data.approved_pr_number}](#{data.approved_pr_url})"
  end

  sig { params(number: Integer).returns(GitHubPayloads) }
  def reviews_for(number)
    @reviews[number] ||= paginated_rest("#{API_URL}/repos/#{@repository}/pulls/#{number}/reviews")
  end

  sig { params(url: T.any(String, URI::Generic), additional_query_params: String).returns(GitHubPayloads) }
  def paginated_rest(url, additional_query_params = "")
    pages = T.cast(
      JSON.parse(gh_api("#{url}?per_page=#{MAX_PER_PAGE}&#{additional_query_params}", "--paginate", "--slurp")),
      T::Array[GitHubPage],
    )
    pages.flat_map do |page|
      page.is_a?(Array) ? page : [page]
    end
  end

  sig {
    params(
      url:            T.any(String, URI::Generic),
      data:           RequestData,
      request_method: Symbol,
    ).returns(GitHubResult)
  }
  def rest(url, data: {}, request_method: :GET)
    T.cast(JSON.parse(gh_api(url.to_s, "--method", request_method.to_s, data:)), GitHubResult)
  end

  sig { params(args: String, data: RequestData).returns(String) }
  def gh_api(*args, data: {})
    args += ["--input", "-"] unless data.empty?
    stdout, stderr, status = Open3.capture3("gh", "api", *args, stdin_data: JSON.generate(data))
    # `Open3` tags output with the default external encoding, which is US-ASCII when
    # the runner has no UTF-8 locale. `gh` always emits UTF-8.
    stdout.force_encoding(Encoding::UTF_8)
    stderr.force_encoding(Encoding::UTF_8)
    raise "GitHub API request failed: #{stderr.strip}" unless status.success?

    stdout
  end
end

StaleLeadMaintainerPrApproval.new.run if $PROGRAM_NAME == __FILE__
