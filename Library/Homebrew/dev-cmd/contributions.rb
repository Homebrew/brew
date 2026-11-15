# typed: strict
# frozen_string_literal: true

require "utils/text"

require "abstract_command"
require "digest"
require "json"
require "system_command"
require "tap"

module Homebrew
  module DevCmd
    class Contributions < AbstractCommand
      include SystemCommand::Mixin

      PRIMARY_REPOS = %w[
        Homebrew/brew
        Homebrew/homebrew-core
        Homebrew/homebrew-cask
      ].freeze
      CONTRIBUTION_TYPES = T.let({
        merged_pr_author:   "merged PRs authored",
        merged_pr_merger:   "PRs merged",
        merged_pr:          "qualifying merged PRs",
        approved_pr_review: "approved-review search matches",
        coauthor:           "co-authored commits",
      }.freeze, T::Hash[Symbol, String])
      MAINTAINER_CONTRIBUTION_TYPES = [:merged_pr_merger, :approved_pr_review, :closed_issue].freeze
      MAINTAINER_USER_RENAMES = T.let({ "branchvincent" => "branchv" }.freeze, T::Hash[String, String])
      MAX_RATE_LIMIT_RETRIES = 3
      SECONDARY_RATE_LIMIT_DELAY = 60
      MAX_PR_SEARCH = 100
      MAX_PR_AUTHOR_BATCH = 100
      MAX_SEARCH_RESULTS = 1000
      # https://docs.brew.sh/Homebrew-Governance#maintainer
      ACTIVITY_PERIOD_MONTHS = 3
      MAINTAINER_ACTIVITY_THRESHOLD = 40
      # https://docs.brew.sh/Homebrew-Governance#lead-maintainer
      LEAD_ACTIVITY_PERIODS = 4
      LEAD_ACTIVITY_REPOSITORIES = 2
      LEAD_REPOSITORY_ACTIVITY_THRESHOLD = 20
      MAX_CONTRIBUTIONS = 500
      QUALIFYING_CONTRIBUTION_TYPES = [:merged_pr, :approved_pr_review, :coauthor].freeze
      GIT_LOG_FIELD_SEPARATOR = "\x1f"
      GIT_LOG_RECORD_SEPARATOR = "\x1e"
      GIT_LOG_COMMIT_HASH_FORMAT = "%H"
      GIT_LOG_PARENT_HASHES_FORMAT = "%P"
      GIT_LOG_AUTHOR_NAME_FORMAT = "%an"
      GIT_LOG_AUTHOR_EMAIL_FORMAT = "%ae"
      GIT_LOG_COMMITTER_NAME_FORMAT = "%cn"
      GIT_LOG_COMMITTER_EMAIL_FORMAT = "%ce"
      GIT_LOG_COMMITTER_DATE_SHORT_FORMAT = "%cs"
      GIT_LOG_COMMIT_MESSAGE_FORMAT = "%B"
      GIT_LOG_FIELDS = T.let({
        commit_hash: 0, parent_hashes: 1, author_name: 2, author_email: 3,
        committer_name: 4, committer_email: 5, commit_message: 6
      }.freeze, T::Hash[Symbol, Integer])

      require "contributions/reporting"
      include Reporting

      cmd_args do
        usage_banner "`contributions` [`--user=`] [`--repositories=`] [`--quarter=`] [`--from=`] [`--to=`] " \
                     "[`--csv`] [`--maintainer-report-csv`]"
        description <<~EOS
          Summarise contributions to Homebrew repositories.
        EOS
        comma_array "--user=",
                    description: "Specify a comma-separated list of GitHub usernames or email addresses to find " \
                                 "contributions from. Omitting this flag searches Homebrew maintainers and " \
                                 "requires access to the `Homebrew/maintainers` team. " \
                                 "With `--maintainer-report-csv`, only matching period-end Maintainers are included."
        comma_array "--repositories",
                    description: "Specify a comma-separated list of repositories to search. " \
                                 "All repositories must be under the same user or organisation. " \
                                 "Omitting this flag, or specifying `--repositories=primary`, searches only the " \
                                 "main repositories: `Homebrew/brew`, `Homebrew/homebrew-core`, " \
                                 "`Homebrew/homebrew-cask`."
        flag   "--organisation=", "--organization=", "--org=",
               description: "Specify the organisation to populate sources repositories from. " \
                            "Omitting this flag searches the Homebrew primary repositories."
        flag   "--team=",
               description: "Specify the team to populate users from. " \
                            "The first part of the team name will be used as the organisation."
        flag   "--quarter=",
               description: "Homebrew contributions quarter to search (1-4). " \
                            "Omitting this flag searches the past year. " \
                            "If `--from` or `--to` are set, they take precedence."
        flag   "--from=",
               description: "Date (ISO 8601 format) to start searching contributions. " \
                            "Omitting this flag searches the past year."
        flag   "--to=",
               description: "Date (ISO 8601 format) to stop searching contributions."
        switch "--csv",
               description: "Print a CSV of contributions across repositories over the time period."
        flag   "--maintainer-report-csv",
               description: "Print a CSV of Maintainer and Lead Maintainer activity criteria using fetched Git " \
                            "histories, verified GitHub approvals and issue closures for the Homebrew " \
                            "governance quarter, for example `--maintainer-report-csv=2026-2`. " \
                            "Alternatively, omit the value and set `--from` and `--to` for any reporting period. " \
                            "Also write it in the current directory as `brew-contributions-FROM-to-TO.csv`, or " \
                            "`brew-contributions-FROM-to-TO-USER.csv` when filtered with `--user`, beside a " \
                            "matching `.md` summary of activity in the latest completed and current quarters " \
                            "with each Maintainer's numerical gap. " \
                            "Only Maintainers listed at the end of that period are included. " \
                            "Activity checks use the latest completed governance quarter; " \
                            "role recommendations use up to four full quarters of reports. " \
                            "Counts are capped at 500 per repository and contribution type. " \
                            "Merge and approval checks stop once the activity thresholds are met. " \
                            "Historical reports using older criteria must be regenerated. Completed-period " \
                            "GitHub searches are cached in Homebrew's cache and removed by normal cache pruning. " \
                            "`YEAR-1` is December of the previous year through February, `YEAR-2` is March " \
                            "through May, `YEAR-3` is June through August and `YEAR-4` is September through " \
                            "November."
        comma_array "--maintainer-exempt=",
                    description: "GitHub usernames exempt from Maintainer inactivity removal, such as " \
                                 "Security Team members. Lead Maintainer activity requirements still apply."
        conflicts "--organisation", "--repositories"
        conflicts "--organisation", "--team"
        conflicts "--user", "--team"
        conflicts "--maintainer-report-csv", "--repositories"
        conflicts "--maintainer-report-csv", "--organisation"
        conflicts "--maintainer-report-csv", "--team"
        conflicts "--maintainer-report-csv", "--quarter"
      end

      sig { override.void }
      def run
        maintainer_report_csv = args.maintainer_report_csv
        if args.maintainer_exempt && !maintainer_report_csv
          odie "`--maintainer-exempt` requires `--maintainer-report-csv`."
        end
        requested_users = args.user || []
        odie "`--user` must not contain empty values." if requested_users.compact.length != requested_users.length

        odie "Cannot get contributions as `$HOMEBREW_NO_GITHUB_API` is set!" if Homebrew::EnvConfig.no_github_api?
        Utils::GemSetup.install_bundler_gems!(groups: ["contributions"]) if args.csv? || maintainer_report_csv

        if maintainer_report_csv && !args.from && !args.to
          unless maintainer_report_csv.to_s.match?(/\A\d{4}-[1-4]\z/)
            odie "`--maintainer-report-csv` requires YEAR-QUARTER or both `--from` and `--to`."
          end
          quarter_parts = maintainer_report_csv.to_s.split("-")
          from, to = reporting_quarter_dates(quarter_parts.fetch(1).to_i, quarter_parts.fetch(0).to_i)
        else
          if maintainer_report_csv
            if args.from.nil? || args.to.nil?
              odie "`--maintainer-report-csv` requires both `--from` and `--to`."
            end
            if maintainer_report_csv.is_a?(String)
              odie "Use `--maintainer-report-csv` without a value with `--from` and `--to`."
            end
          end
          quarter = args.quarter.presence.to_i
          odie "Value for `--quarter` must be between 1 and 4." if args.quarter.present? && !quarter.between?(1, 4)
          quarter_dates = reporting_quarter_dates(quarter) unless quarter.zero?
          from = args.from.presence || quarter_dates&.first || Date.today.prev_year.iso8601
          to = args.to.presence || quarter_dates&.last || (Date.today + 1).iso8601
        end
        if maintainer_report_csv
          from = Date.iso8601(from).iso8601
          to = Date.iso8601(to).iso8601
          odie "`--from` must precede `--to`." if from >= to
          $stderr.puts "Maintainer report dates: #{from}-to-#{to}"
        elsif args.verbose?
          puts "Date range is #{time_period(from:, to:)}."
        end

        require "utils/github"

        organisation = T.let(nil, T.nilable(String))
        users = if maintainer_report_csv
          []
        elsif (team = args.team.presence)
          team_sections = team.split("/")
          organisation = team_sections.first.presence
          team_name = team_sections.last.presence
          if team_sections.length != 2 || organisation.nil? || team_name.nil?
            odie "Team must be in the format `organisation/team`!"
          end

          puts "Getting members for #{organisation}/#{team_name}..." if args.verbose?
          GitHub.members_by_team(organisation, team_name).keys
        elsif requested_users.present?
          requested_users
        else
          puts "Getting members for Homebrew/maintainers..." if args.verbose?
          GitHub.members_by_team("Homebrew", "maintainers").keys
        end
        user_names = users.to_h { |user| [user, user] }

        repositories = if maintainer_report_csv
          organisation = "Homebrew"
          PRIMARY_REPOS
        elsif (org = organisation.presence) || (org = args.organisation.presence)
          organisation = org
          puts "Getting repositories for #{organisation}..." if args.verbose?
          GitHub.organisation_repositories(organisation, from, to, args.verbose?)
        elsif (repos = args.repositories.presence) && repos.length == 1 && (first_repository = repos.first)
          case first_repository
          when "primary"
            PRIMARY_REPOS
          else
            Array(first_repository)
          end
        elsif (repos = args.repositories.presence)
          organisations = repos.map { |repository| repository.split("/").first }.uniq
          odie "All repositories must be under the same user or organisation!" if organisations.length > 1

          repos
        else
          PRIMARY_REPOS
        end
        organisation ||= repositories.fetch(0).split("/").fetch(0)
        repository_refs = prepare_contribution_repositories(repositories, required: maintainer_report_csv.present?)

        lead_maintainers = T.let({}, T::Hash[String, T::Boolean])
        maintainer_since_dates = T.let({}, T::Hash[String, T.nilable(String)])
        if maintainer_report_csv
          user_names, lead_maintainers, maintainer_since_dates = maintainer_report_users(repository_refs, to)
        end

        results = scan_contributions(
          organisation, repositories, repository_refs, user_names, from:, to:,
          skip_reviews_if_lead_met: maintainer_report_csv.present?,
          progress:                 maintainer_report_csv.present? || args.verbose?
        )
        grand_totals = results.transform_values { |user_results| total(user_results) }

        if maintainer_report_csv
          csv = generate_maintainer_report_csv(
            results, grand_totals, user_names, lead_maintainers, maintainer_since_dates, from, to
          )
          filename = "brew-contributions-#{from}-to-#{to}"
          filename += "-#{user_names.keys.map(&:downcase).sort.join("-")}" if requested_users.present?
          File.write("#{filename}.csv", csv)
          File.write("#{filename}.md", generate_maintainer_report_summary(csv, from, to))
          puts csv
          return
        end

        user_names.each_key do |username|
          grand_total = grand_totals.fetch(username)
          greater_than_total = T.let(grand_total.fetch(:merged_pr_author_hit_cap, 0).positive?, T::Boolean)
          contributions = CONTRIBUTION_TYPES.keys.filter_map do |type|
            type_count = grand_total[type]
            next if type_count.nil? || type_count.zero?

            count_prefix = ""
            if ([:merged_pr_author, :merged_pr].include?(type) && grand_total.fetch(:merged_pr_author_hit_cap,
                                                                                    0).positive?) ||
               (type == :approved_pr_review && type_count >= MAX_PR_SEARCH) || type_count >= MAX_CONTRIBUTIONS
              greater_than_total ||= true
              count_prefix = ">="
            end

            pretty_type = CONTRIBUTION_TYPES.fetch(type)
            "#{count_prefix}#{Utils.pluralize("time", type_count, include_count: true)} (#{pretty_type})"
          end
          qualifying_total = contribution_count(
            grand_total.slice(*QUALIFYING_CONTRIBUTION_TYPES),
          )
          total = Utils.pluralize("time", qualifying_total, include_count: true)
          total_prefix = ">=" if greater_than_total
          contributions << "#{total_prefix}#{total} (total)"

          contributions_string = [
            "#{username} contributed",
            Utils::Text.to_sentence(contributions),
            "#{time_period(from:, to:)}.",
          ].join(" ")
          if args.csv?
            $stderr.puts contributions_string
          else
            puts contributions_string
          end
        end

        return unless args.csv?

        $stderr.puts
        puts generate_csv(grand_totals)
      end

      sig {
        params(repository_refs: T::Hash[String, [Pathname, String]], to: String)
          .returns([T::Hash[String, String], T::Hash[String, T::Boolean], T::Hash[String, T.nilable(String)]])
      }
      def maintainer_report_users(repository_refs, to)
        brew_path, brew_ref = repository_refs.fetch("Homebrew/brew")
        require "utils/git"
        period_end_ref = Utils.safe_popen_read(
          Utils::Git.git, "-C", brew_path, "rev-list", "-1", "--before=#{to}", brew_ref, "--", "README.md"
        ).strip
        odie "Could not find Homebrew/brew's README at the end of the reporting period." if period_end_ref.empty?

        user_names = T.let({}, T::Hash[String, String])
        lead_maintainers = T.let({}, T::Hash[String, T::Boolean])
        Utils.safe_popen_read(Utils::Git.git, "-C", brew_path, "show", "#{period_end_ref}:README.md")
             .dup.force_encoding(Encoding::UTF_8).each_line do |line|
          lead = line.start_with?("Homebrew's [Lead Maintainers]")
          next if !lead &&
                  !line.start_with?("Homebrew's other Maintainers") &&
                  !line.start_with?("Homebrew's maintainers are")

          line.scan(%r{\[([^\]]+)\]\(https://github\.com/([A-Za-z\d-]+)\)}).each do |match|
            next unless match.is_a?(Array)

            name = match.fetch(0)
            user = match.fetch(1)
            user = MAINTAINER_USER_RENAMES.fetch(user.downcase, user)
            user_names[user] = name
            lead_maintainers[user.downcase] = true if lead
          end
        end
        odie "Could not read the maintainers from Homebrew/brew's README." if user_names.empty?

        if (users = args.user.presence)
          requested_usernames = users.to_h do |user|
            [user, github_username_for(user, to:)&.downcase]
          end
          unresolved_users = requested_usernames.filter_map { |user, username| user if username.nil? }
          odie "Could not resolve GitHub usernames for: #{Utils::Text.to_sentence(unresolved_users)}." \
            if unresolved_users.present?

          maintainer_usernames = user_names.keys.map(&:downcase)
          non_maintainers = requested_usernames.filter_map do |user, username|
            user if username && maintainer_usernames.exclude?(username)
          end
          unless non_maintainers.empty?
            odie "Not listed as #{Utils.pluralize("Maintainer", non_maintainers.length)} at the end of the " \
                 "reporting period: #{Utils::Text.to_sentence(non_maintainers)}."
          end

          selected_usernames = requested_usernames.values.compact
          user_names.select! { |user| selected_usernames.include?(user.downcase) }
        end

        maintainer_count = Utils.pluralize("maintainer", user_names.length, include_count: true)
        $stderr.puts "Scanning contributions for #{maintainer_count}..."
        maintainer_since_dates = user_names.to_h do |user, name|
          [user, maintainer_since(brew_path, period_end_ref, user, name)]
        end
        [user_names, lead_maintainers, maintainer_since_dates]
      end

      sig { params(repository_path: Pathname, ref: String, user: String, name: String).returns(T.nilable(String)) }
      def maintainer_since(repository_path, ref, user, name)
        require "utils/git"

        git_log_format = [GIT_LOG_COMMIT_HASH_FORMAT, GIT_LOG_COMMITTER_DATE_SHORT_FORMAT]
                         .join(GIT_LOG_FIELD_SEPARATOR)
        candidates = ["https://github.com/#{user}", name].flat_map do |identity|
          Utils.safe_popen_read(
            Utils::Git.git, "-C", repository_path, "log", ref, "--fixed-strings",
            "-S#{identity}", "--format=#{git_log_format}", "--", "README.md"
          ).lines(chomp: true)
        end
        candidates.uniq!
        candidates.sort_by! { |candidate| candidate.split(GIT_LOG_FIELD_SEPARATOR, 2).fetch(1) }
        candidates.each do |candidate|
          commit, date = candidate.split(GIT_LOG_FIELD_SEPARATOR, 2)
          next if date.nil?

          readme = Utils.safe_popen_read(Utils::Git.git, "-C", repository_path, "show", "#{commit}:README.md")
          parent_readme = system_command(Utils::Git.git,
                                         args:         ["-C", repository_path, "show", "#{commit}^:README.md"],
                                         print_stderr: false).stdout
          return date if readme_mentions?(readme, user, name) && !readme_mentions?(parent_readme, user, name)
        end

        nil
      end

      sig {
        params(
          organisation:             String,
          repositories:             T::Array[String],
          repository_refs:          T::Hash[String, [Pathname, String]],
          users:                    T::Hash[String, String],
          from:                     String,
          to:                       String,
          skip_reviews_if_lead_met: T::Boolean,
          progress:                 T::Boolean,
        ).returns(T::Hash[String, T::Hash[String, T::Hash[Symbol, Integer]]])
      }
      def scan_contributions(organisation, repositories, repository_refs, users, from:, to:,
                             skip_reviews_if_lead_met:, progress:)
        results = users.to_h do |user, _|
          user_results = repositories.to_h do |repository|
            [repository, CONTRIBUTION_TYPES.keys.to_h { |type| [type, 0] }]
          end
          [user, user_results]
        end

        require "utils/github"
        github_users = users.keys.to_h { |user| [user, github_username_for(user, to:)] }
        # Usernames, real names and public emails, so commits under a maintainer's Git identity are matched.
        github_identities = github_users.filter_map do |user, github_user|
          [user, github_identities_for_username(github_user, to:)] if github_user
        end.to_h
        git_authored_pull_requests = users.keys.to_h do |user|
          [user, repositories.to_h { |repository| [repository, Set.new] }]
        end
        git_merged_pull_requests = users.keys.to_h do |user|
          [user, repositories.to_h { |repository| [repository, Set.new] }]
        end
        git_merger_pull_requests = users.keys.to_h do |user|
          [user, repositories.to_h { |repository| [repository, Set.new] }]
        end
        git_log_format_fields = [
          GIT_LOG_COMMIT_HASH_FORMAT, GIT_LOG_PARENT_HASHES_FORMAT, GIT_LOG_AUTHOR_NAME_FORMAT,
          GIT_LOG_AUTHOR_EMAIL_FORMAT, GIT_LOG_COMMITTER_NAME_FORMAT, GIT_LOG_COMMITTER_EMAIL_FORMAT,
          GIT_LOG_COMMIT_MESSAGE_FORMAT
        ]
        repository_refs.each do |repository, (repository_path, ref)|
          require "utils/git"
          git_log_format = git_log_format_fields.join(GIT_LOG_FIELD_SEPARATOR) + GIT_LOG_RECORD_SEPARATOR
          output = Utils.safe_popen_read(
            Utils::Git.git, "-C", repository_path, "log", ref, "--since=#{from}", "--before=#{to}",
            "--format=#{git_log_format}"
          )
          authored_pull_requests = users.keys.to_h { |user| [user, Set.new] }
          merged_pull_requests = users.keys.to_h { |user| [user, Set.new] }
          merger_pull_requests = users.keys.to_h { |user| [user, Set.new] }
          parse_git_log(output, users, github_identities:, authored_pull_requests:, merged_pull_requests:,
                        merger_pull_requests:)
            .each do |user, counts|
            results.fetch(user)[repository] = counts
            git_authored_pull_requests.fetch(user)[repository] = authored_pull_requests.fetch(user)
            git_merged_pull_requests.fetch(user)[repository] = merged_pull_requests.fetch(user)
            git_merger_pull_requests.fetch(user)[repository] = merger_pull_requests.fetch(user)
          end
        end

        if args.maintainer_report_csv
          results.each_value do |user_results|
            user_results.transform_values! do |counts|
              MAINTAINER_CONTRIBUTION_TYPES.to_h { |type| [type, counts.fetch(type, 0)] }
            end
          end
          return scan_maintainer_contributions(repositories, results, github_users, git_merger_pull_requests,
                                               from:, to:, skip_reviews_if_lead_met:, progress:)
        end

        merged_range = "#{from}..#{Date.iso8601(to).prev_day.iso8601}"
        users.each_key do |user|
          github_user = github_users.fetch(user)
          next if github_user.nil?

          merged_pull_requests = cached_github_request(Array, "merged-at", organisation, github_user, merged_range,
                                                       to:) do
            GitHub.search_issues("", is: "merged", user: organisation, author: github_user, merged: merged_range)
          rescue GitHub::API::ValidationFailedError
            opoo "Couldn't search GitHub for PRs authored by #{github_user}. Their profile might be private. " \
                 "Defaulting to 0."
            []
          end
          capped_merged_pull_requests = merged_pull_requests.length >= MAX_PR_SEARCH
          if capped_merged_pull_requests
            results.fetch(user).fetch(repositories.fetch(0))[:merged_pr_author_hit_cap] =
              1
          end
          merged_pull_requests.each do |pull_request|
            repository = pull_request.fetch("repository_url").delete_prefix("#{GitHub::API_URL}/repos/")
            next unless repositories.include?(repository)

            authored_pull_requests = git_authored_pull_requests.fetch(user).fetch(repository)
            merged_pull_request_ids = git_merged_pull_requests.fetch(user).fetch(repository)
            add_merged_pull_request_id(pull_request, authored_pull_requests, merged_pull_request_ids)
          end
          repositories.each do |repository|
            counts = results.fetch(user).fetch(repository)
            authored_pull_requests = git_authored_pull_requests.fetch(user).fetch(repository)
            merged_pull_request_ids = git_merged_pull_requests.fetch(user).fetch(repository)
            update_merged_pull_request_counts(counts, authored_pull_requests, merged_pull_request_ids)
          end
          next unless skip_reviews_if_lead_met
          next unless capped_merged_pull_requests
          next if lead_activity_met?(results.fetch(user))

          repositories.each do |repository|
            break if lead_activity_met?(results.fetch(user))

            repository_counts = results.fetch(user).fetch(repository)
            repository_total = contribution_count(repository_counts.slice(*QUALIFYING_CONTRIBUTION_TYPES))
            qualifying_total = contribution_count(total(results.fetch(user)).slice(*QUALIFYING_CONTRIBUTION_TYPES))
            next if repository_total >= LEAD_REPOSITORY_ACTIVITY_THRESHOLD &&
                    qualifying_total >= MAINTAINER_ACTIVITY_THRESHOLD

            $stderr.puts "Querying merged-PR search for #{user} in #{repository}..." if progress
            repository_pull_requests = cached_github_request(Array, "merged-at", repository, github_user,
                                                             merged_range, to:) do
              GitHub.search_issues("", is: "merged", repo: repository, author: github_user, merged: merged_range)
            end
            authored_pull_requests = git_authored_pull_requests.fetch(user).fetch(repository)
            merged_pull_request_ids = git_merged_pull_requests.fetch(user).fetch(repository)
            repository_pull_requests.each do |pull_request|
              add_merged_pull_request_id(pull_request, authored_pull_requests, merged_pull_request_ids)
            end
            update_merged_pull_request_counts(repository_counts, authored_pull_requests, merged_pull_request_ids)
          end
        end

        review_users = github_users.filter_map { |user, github_user| [user, github_user] if github_user }
        review_users.reject! { |user, _| lead_activity_met?(results.fetch(user)) } if skip_reviews_if_lead_met
        approved_to = Date.iso8601(to).prev_day.iso8601
        review_users.each_with_index do |(user, github_user), index|
          if progress
            $stderr.puts "Querying approved-review search for #{user} (#{index + 1}/#{review_users.length})..."
          end
          approved_reviews = cached_github_request(Array, "approved", organisation, github_user, from, approved_to,
                                                   to:) do
            GitHub.search_approved_pull_requests_in_user_or_organisation(organisation, github_user,
                                                                         from:, to: approved_to)
          end
          capped_reviews = approved_reviews.length >= MAX_PR_SEARCH
          results.fetch(user).fetch(repositories.fetch(0))[:approved_pr_review_hit_cap] = 1 if capped_reviews
          approved_reviews.each do |pull_request|
            repository = pull_request.fetch("repository_url").delete_prefix("#{GitHub::API_URL}/repos/")
            next unless repositories.include?(repository)

            increment_contribution_count(results.fetch(user).fetch(repository), :approved_pr_review)
          end
          next unless skip_reviews_if_lead_met
          next unless capped_reviews
          next if lead_activity_met?(results.fetch(user))

          repositories.each do |repository|
            break if lead_activity_met?(results.fetch(user))

            repository_counts = results.fetch(user).fetch(repository)
            repository_total = contribution_count(repository_counts.slice(*QUALIFYING_CONTRIBUTION_TYPES))
            qualifying_total = contribution_count(total(results.fetch(user)).slice(*QUALIFYING_CONTRIBUTION_TYPES))
            next if repository_total >= LEAD_REPOSITORY_ACTIVITY_THRESHOLD &&
                    qualifying_total >= MAINTAINER_ACTIVITY_THRESHOLD

            $stderr.puts "Querying approved-review search for #{user} in #{repository}..." if progress
            repository_reviews = cached_github_request(Array, "approved", repository, github_user,
                                                       from, approved_to, to:) do
              GitHub.search_issues("", is: "pr", review: "approved", repo: repository, reviewed_by: github_user,
                                   from:, to: approved_to)
            end
            repository_counts[:approved_pr_review] = repository_reviews.length
          end
        end

        results
      end

      sig {
        params(
          repositories: T::Array[String],
          results: T::Hash[String, T::Hash[String, T::Hash[Symbol, Integer]]],
          github_users: T::Hash[String, T.nilable(String)],
          git_merged_pull_requests: T::Hash[String, T::Hash[String, T::Set[String]]],
          from: String, to: String, skip_reviews_if_lead_met: T::Boolean, progress: T::Boolean
        ).returns(T::Hash[String, T::Hash[String, T::Hash[Symbol, Integer]]])
      }
      def scan_maintainer_contributions(repositories, results, github_users, git_merged_pull_requests, from:, to:,
                                        skip_reviews_if_lead_met:, progress:)
        github_users.each do |user, github_user|
          next if github_user.nil?

          repositories.each do |repository|
            merged_pull_requests = git_merged_pull_requests.fetch(user).fetch(repository)
            next if merged_pull_requests.empty?

            $stderr.puts "Excluding self-merges for #{user} in #{repository}..." if progress
            counts = results.fetch(user).fetch(repository)
            verified_merges = Set.new
            numbers = merged_pull_requests.sort_by(&:to_i)
            numbers.each_slice(MAX_PR_AUTHOR_BATCH) do |batch|
              authors = cached_github_request(Hash, "pull-request-authors", repository, *batch, to:) do
                owner, name = repository.split("/", 2)
                query = <<~GRAPHQL
                  query($owner: String!, $name: String!) {
                    repository(owner: $owner, name: $name) {
                      #{batch.map { |number| "pr#{number}: pullRequest(number: #{number}) { author { login } }" }.join(" ")}
                    }
                  }
                GRAPHQL
                response = GitHub::API.open_graphql(query, variables: { owner:, name: }, raise_errors: false)
                errors = response.fetch("errors", []).reject do |error|
                  error["type"] == "NOT_FOUND" &&
                    batch.any? { |number| error["path"] == ["repository", "pr#{number}"] }
                end
                raise GitHub::API::Error, errors.map { |error| error.fetch("message") }.join("\n") if errors.present?

                response.fetch("data").fetch("repository")
              end
              batch.each do |number|
                author = authors.fetch("pr#{number}")&.dig("author", "login")
                if author.nil?
                  counts[:unverified_merges] = counts.fetch(:unverified_merges, 0) + 1
                  next
                end
                next if author.casecmp?(github_user)

                verified_merges << number
              end
              limit = skip_reviews_if_lead_met ? MAINTAINER_ACTIVITY_THRESHOLD : MAX_CONTRIBUTIONS
              next if verified_merges.length < limit

              counts[:merges_skipped] = 1 if batch.last != numbers.last
              break
            end
            merged_pull_requests.replace(verified_merges)
            counts[:merged_pr_merger] = [verified_merges.length, MAX_CONTRIBUTIONS].min
          end
        end

        repositories.each do |repository|
          $stderr.puts "Querying issue closures in #{repository}..." if progress
          closures = closed_issue_counts(repository, from:, to:)
          github_users.each do |user, github_user|
            next if github_user.nil?

            results.fetch(user).fetch(repository)[:closed_issue] =
              [closures.fetch(github_user.downcase, 0), MAX_CONTRIBUTIONS].min
          end
        end

        github_users.each do |user, github_user|
          next if github_user.nil?

          repositories.each do |repository|
            counts = results.fetch(user).fetch(repository)
            if skip_reviews_if_lead_met && review_checks_complete?(results.fetch(user), repository)
              counts[:reviews_skipped] = 1
              next
            end

            $stderr.puts "Querying PR approvals for #{user} in #{repository}..." if progress
            page = 1
            loop do
              matches = cached_github_request(Hash, "merged-review-candidates", repository, github_user, from, to,
                                              page.to_s, to:) do
                uri = GitHub.url_to("search", "issues")
                uri.query = "#{GitHub.search_query_string("-author:#{github_user}", is: "merged", repo: repository,
                                                         reviewed_by: github_user,
                                                         merged: "#{from}..#{Date.iso8601(to).prev_day.iso8601}")}" \
                            "&page=#{page}"
                GitHub::API.open_rest(uri)
              end
              matches.fetch("items").each do |pull_request|
                number = pull_request.fetch("number")
                next if git_merged_pull_requests.fetch(user).fetch(repository).include?(number.to_s)
                next unless approved_pull_request?(repository, number, github_user, from:, to:)

                increment_contribution_count(counts, :approved_pr_review)
                break if skip_reviews_if_lead_met && review_checks_complete?(results.fetch(user), repository)
              end
              if skip_reviews_if_lead_met && review_checks_complete?(results.fetch(user), repository)
                counts[:reviews_skipped] = 1
                break
              end
              break if counts.fetch(:approved_pr_review) >= MAX_CONTRIBUTIONS

              if matches["incomplete_results"] ||
                 (page * MAX_PR_SEARCH >= MAX_SEARCH_RESULTS && page * MAX_PR_SEARCH < matches.fetch("total_count"))
                odie "Incomplete review search for #{user} in #{repository}.\nUse a shorter reporting period."
              end
              break if page * MAX_PR_SEARCH >= matches.fetch("total_count")

              page += 1
            end
          end
        end

        results.each do |user, user_results|
          assessments = [false, true].freeze.map do |include_unverified|
            activity_met(user_results.values.map do |counts|
              contribution_count(counts.slice(*MAINTAINER_CONTRIBUTION_TYPES)) +
                (include_unverified ? counts.fetch(:unverified_merges, 0) : 0)
            end)
          end
          next if assessments.uniq.one?

          odie "#{user}: unavailable PRs could change the activity assessment."
        end
        results
      end

      sig { params(repository: String, number: Integer, user: String, from: String, to: String).returns(T::Boolean) }
      def approved_pull_request?(repository, number, user, from:, to:)
        activity = cached_github_request(Hash, "merged-pr-activity", repository, number.to_s, to:) do
          query = <<~GRAPHQL
            query($owner: String!, $name: String!, $number: Int!, $after: String) {
              repository(owner: $owner, name: $name) {
                pullRequest(number: $number) {
                  mergedAt
                  author { login }
                  timelineItems(itemTypes: [PULL_REQUEST_REVIEW, REVIEW_DISMISSED_EVENT], first: 100, after: $after) {
                    nodes {
                      ...ReviewFields
                      ... on ReviewDismissedEvent {
                        createdAt
                        previousReviewState
                        review { ...ReviewFields }
                      }
                    }
                    pageInfo { hasNextPage endCursor }
                  }
                }
              }
            }
            fragment ReviewFields on PullRequestReview {
              id
              author { login }
              submittedAt
              state
              authorCanPushToRepository
            }
          GRAPHQL
          owner, name = repository.split("/", 2)
          merged_at = T.let("", String)
          review_events = T.let([], T::Array[[String, String, String, String]])
          GitHub::API.paginate_graphql(query, variables: { owner:, name:, number: }) do |result|
            pull_request = result.fetch("repository").fetch("pullRequest")
            merged_at = pull_request["mergedAt"].to_s
            next({ "hasNextPage" => false }) if merged_at.empty?

            timeline = pull_request.fetch("timelineItems")
            timeline.fetch("nodes").each do |event|
              review = event["review"] || event
              reviewer = review.dig("author", "login")
              date = review["submittedAt"]
              next unless reviewer.is_a?(String)
              next unless date.is_a?(String)
              next if date > merged_at || reviewer.casecmp?(pull_request.dig("author", "login").to_s)
              next unless review.fetch("authorCanPushToRepository")

              state = event["previousReviewState"] || review.fetch("state")
              next unless ["APPROVED", "CHANGES_REQUESTED"].include?(state)

              review_events << [date, review.fetch("id"), reviewer.downcase, state]
              if event["previousReviewState"] && event.fetch("createdAt") <= merged_at
                review_events << [event.fetch("createdAt"), review.fetch("id"), reviewer.downcase, "DISMISSED"]
              end
            end
            timeline.fetch("pageInfo")
          end
          approvals = T.let({}, T::Hash[String, [String, String]])
          review_events.sort_by(&:first).each do |date, id, reviewer, state|
            if state == "APPROVED"
              approvals[id] = [reviewer, date]
            elsif repository == "Homebrew/brew"
              if state == "CHANGES_REQUESTED"
                approvals.reject! { |_, (author, _)| author == reviewer }
              elsif state == "DISMISSED"
                approvals.delete(id)
              end
            end
          end
          approvers = if repository == "Homebrew/brew"
            first_approval = approvals.values.min_by { |_, date| date }
            first_approval ? [first_approval.first] : []
          else
            approvals.values.map(&:first).uniq
          end
          { "merged_at" => merged_at, "approvers" => approvers }
        end
        activity.fetch("merged_at") >= "#{from}T00:00:00Z" &&
          activity.fetch("merged_at") < "#{to}T00:00:00Z" && activity.fetch("approvers").include?(user.downcase)
      end

      sig { params(repository: String, from: String, to: String).returns(T::Hash[String, Integer]) }
      def closed_issue_counts(repository, from:, to:)
        cached_github_request(Hash, "separate-issue-closures", repository, from, to, to:) do
          query = <<~GRAPHQL
            query($owner: String!, $name: String!, $since: DateTime!, $after: String) {
              repository(owner: $owner, name: $name) {
                issues(first: 100, after: $after, filterBy: {since: $since},
                       orderBy: {field: CREATED_AT, direction: ASC}) {
                  nodes {
                    createdAt
                    author { login }
                    timelineItems(first: 100, itemTypes: [CLOSED_EVENT], since: $since) {
                      nodes {
                        ... on ClosedEvent {
                          actor { login }
                          createdAt
                          closer {
                            __typename
                            ... on Commit { associatedPullRequests(first: 1) { nodes { merged } } }
                          }
                        }
                      }
                      pageInfo { hasNextPage }
                    }
                  }
                  pageInfo { hasNextPage endCursor }
                }
              }
            }
          GRAPHQL
          owner, name = repository.split("/", 2)
          counts = T.let({}, T::Hash[String, Integer])
          GitHub::API.paginate_graphql(query, variables: { owner:, name:, since: "#{from}T00:00:00Z" }) do |result|
            issues = result.fetch("repository").fetch("issues")
            nodes = issues.fetch("nodes")
            relevant_issues = nodes.take_while { |issue| issue.fetch("createdAt") < "#{to}T00:00:00Z" }
            relevant_issues.each do |issue|
              timeline = issue.fetch("timelineItems")
              if timeline.fetch("pageInfo").fetch("hasNextPage")
                odie "Too many issue closures in #{repository}; use a shorter reporting period."
              end
              closers = timeline.fetch("nodes").filter_map do |event|
                date = event.fetch("createdAt")
                next if date < "#{from}T00:00:00Z" || date >= "#{to}T00:00:00Z"

                next if event.dig("closer", "__typename") == "PullRequest"
                next if event.dig("closer", "associatedPullRequests", "nodes")&.any? { |pr| pr.fetch("merged") }

                user = event.dig("actor", "login")
                next unless user.is_a?(String)
                next if user.casecmp?(issue.dig("author", "login").to_s)

                user.downcase
              end
              closers.uniq.each do |user|
                counts[user] = counts.fetch(user, 0) + 1
              end
            end
            (relevant_issues.length == nodes.length) ? issues.fetch("pageInfo") : { "hasNextPage" => false }
          end
          counts
        end
      end

      sig { params(user: String, to: String).returns(T.nilable(String)) }
      def github_username_for(user, to:)
        user = MAINTAINER_USER_RENAMES.fetch(user.downcase, user) if args.maintainer_report_csv
        return user unless user.include?("@")

        noreply_username = github_noreply_username(user)
        return github_username_for(noreply_username, to:) if noreply_username

        matches = cached_github_request(Array, "public-email", user, to, to:) do
          GitHub.search("users", "\"#{user}\" in:email").fetch("items", [])
        end
        if matches.one?
          login = matches.fetch(0)["login"]
          return login if login.is_a?(String)
        end

        opoo "Could not find a unique public GitHub account for #{user}; skipping GitHub PR searches."
        nil
      rescue GitHub::API::ValidationFailedError
        opoo "Could not search for a public GitHub account for #{user}; skipping GitHub PR searches."
        nil
      end

      sig { params(username: String, to: String).returns(T::Array[String]) }
      def github_identities_for_username(username, to:)
        profile = cached_github_request(Hash, "user-profile", username, to, to:) do
          GitHub::API.open_rest(GitHub.url_to("users", username))
        rescue GitHub::API::HTTPNotFoundError
          {}
        end
        aliases = if args.maintainer_report_csv
          MAINTAINER_USER_RENAMES.filter_map { |former, current| former if current.casecmp?(username) }
        else
          []
        end
        [username, *aliases, profile["name"], profile["email"]].compact
      end

      # Returns the block's result, caching it as JSON for completed periods and waiting out rate limits.
      # `type` is the JSON class the block returns so unexpected cached data is discarded rather than returned.
      sig {
        type_parameters(:U).params(
          type:      T::Class[T.type_parameter(:U)],
          key_parts: String,
          to:        String,
          block:     T.proc.returns(T.type_parameter(:U)),
        ).returns(T.type_parameter(:U))
      }
      def cached_github_request(type, *key_parts, to:, &block)
        cache_path = if Date.iso8601(to) <= Date.today
          # NUL cannot appear in usernames, repositories or dates so joining with it keeps key parts distinct.
          cache_key = ["1", *key_parts].join("\0")
          HOMEBREW_CACHE/"contributions--#{Digest::SHA256.hexdigest(cache_key)}.json"
        end
        if cache_path&.file?
          begin
            cached = JSON.parse(cache_path.read)
            return cached if cached.is_a?(type)

            opoo "Deleting contributions cache #{cache_path} containing #{cached.class} rather than #{type}."
          rescue JSON::ParserError, Errno::ENOENT => e
            opoo "Deleting unreadable contributions cache #{cache_path}: #{e}"
          end
          cache_path.unlink if cache_path.exist?
        end

        rate_limit_retries = 0
        result = begin
          yield
        rescue GitHub::API::RateLimitExceededError => e
          minimum = 1
          if e.resource == "secondary"
            raise if rate_limit_retries >= MAX_RATE_LIMIT_RETRIES

            minimum = SECONDARY_RATE_LIMIT_DELAY * (2**rate_limit_retries).to_i
            rate_limit_retries += 1
          end
          GitHub::API.sleep_for_rate_limit(e, minimum:)
          retry
        end
        if cache_path
          HOMEBREW_CACHE.mkpath
          cache_path.atomic_write(JSON.generate(result))
        end
        result
      end

      sig {
        params(
          output:                 String,
          users:                  T::Hash[String, String],
          github_identities:      T.nilable(T::Hash[String, T::Array[String]]),
          authored_pull_requests: T.nilable(T::Hash[String, T::Set[String]]),
          merged_pull_requests:   T.nilable(T::Hash[String, T::Set[String]]),
          merger_pull_requests:   T.nilable(T::Hash[String, T::Set[String]]),
        )
          .returns(T::Hash[String, T::Hash[Symbol, Integer]])
      }
      def parse_git_log(output, users, github_identities: nil, authored_pull_requests: nil, merged_pull_requests: nil,
                        merger_pull_requests: nil)
        counts = users.to_h do |user, _|
          [user, CONTRIBUTION_TYPES.keys.to_h { |type| [type, 0] }]
        end
        identity_users = T.let({}, T::Hash[String, String])
        users.each do |user, name|
          identity_users[user.downcase] = user
          identity_users[name.downcase] = user
        end
        # GitHub profile names are not unique so only match those belonging to one requested user.
        github_identity_users = T.let({}, T::Hash[String, T.nilable(String)])
        github_identities&.each do |user, identities|
          identities.map(&:downcase).uniq.each do |identity|
            github_identity_users[identity] = github_identity_users.key?(identity) ? nil : user
          end
        end
        github_identity_users.each do |identity, user|
          identity_users[identity] ||= user if user
        end
        merger_identities = args.maintainer_report_csv ? identity_users.dup : identity_users
        records = output.split(GIT_LOG_RECORD_SEPARATOR).filter_map do |record|
          values = record.strip.split(GIT_LOG_FIELD_SEPARATOR, GIT_LOG_FIELDS.length)
          next if values.length != GIT_LOG_FIELDS.length

          GIT_LOG_FIELDS.to_h { |field, index| [field, values.fetch(index)] }
        end
        record_identities = records.to_h do |fields|
          [fields.fetch(:commit_hash), [fields.fetch(:author_name), fields.fetch(:author_email)]]
        end

        # Resolve identities for each commit based on the author and committer information
        records.each do |fields|
          parents = fields.fetch(:parent_hashes).split
          source_owner = fields.fetch(:commit_message)[%r{\AMerge pull request #\d+ from ([^/\s]+)/}, 1]
          next if parents.length < 2 || source_owner.nil?

          user = identity_users[source_owner.downcase]
          source_identity = record_identities[parents.fetch(1)]
          next if user.nil? || source_identity.nil?

          name, email = source_identity
          identity_users[name.strip.downcase] ||= user
          identity_users[email.downcase] ||= user
        end

        # Map commit SHAs to their respective authors based on identity resolution
        commit_authors = T.let(records.to_h do |fields|
          [fields.fetch(:commit_hash), user_for_git_identity(
            fields.fetch(:author_name), fields.fetch(:author_email), identity_users
          )]
        end, T::Hash[String, T.nilable(String)])

        # Coauthor contributions with "Co-authored-by" in body
        records.each do |fields|
          coauthors = fields.fetch(:commit_message)
                            .scan(/^Co-authored-by:\s*(.*?)\s*<([^>]+)>/i).filter_map do |match|
            next unless match.is_a?(Array)

            user_for_git_identity(match.fetch(0), match.fetch(1), identity_users)
          end

          # Coauthor information from amended commit fields
          if [fields.fetch(:author_name), fields.fetch(:author_email)] !=
             [fields.fetch(:committer_name), fields.fetch(:committer_email)]
            coauthor = user_for_git_identity(
              fields.fetch(:committer_name), fields.fetch(:committer_email), identity_users
            )
            coauthors << coauthor if coauthor
          end

          # Increment coauthor contribution counts
          coauthors.uniq.each do |user|
            increment_contribution_count(counts.fetch(user), :coauthor)
          end

          parents = fields.fetch(:parent_hashes).split
          pull_request = fields.fetch(:commit_message).match(%r{\AMerge pull request #(\d+) from ([^/\s]+)/})
          next if parents.length < 2 || pull_request.nil?

          merger = user_for_git_identity(fields.fetch(:author_name), fields.fetch(:author_email), merger_identities)
          pull_request_id = pull_request[1]
          source_owner = pull_request[2]
          next if pull_request_id.nil? || source_owner.nil?

          author = identity_users[source_owner.downcase] || commit_authors[parents.fetch(1)]
          if author
            increment_contribution_count(counts.fetch(author), :merged_pr_author)
            authored_pull_requests&.fetch(author)&.add(pull_request_id)
          end
          if merger
            increment_contribution_count(counts.fetch(merger), :merged_pr_merger)
            merger_pull_requests&.fetch(merger)&.add(pull_request_id)
          end
          [author, merger].compact.uniq.each do |user|
            increment_contribution_count(counts.fetch(user), :merged_pr)
            merged_pull_requests&.fetch(user)&.add(pull_request_id)
          end
        end

        counts
      end

      sig {
        params(from: String)
          .returns(T::Array[T::Hash[String, [T::Boolean, T::Boolean]]])
      }
      def previous_maintainer_reports(from)
        reports = T.let([], T::Array[T::Hash[String, [T::Boolean, T::Boolean]]])
        period_end = Date.iso8601(from)
        (LEAD_ACTIVITY_PERIODS - 1).times do
          period_start = period_end.prev_month(ACTIVITY_PERIOD_MONTHS)
          path = Pathname("brew-contributions-#{period_start.iso8601}-to-#{period_end.iso8601}.csv")
          report = maintainer_activity_report(period_start.iso8601, period_end.iso8601)
          if report.nil?
            if reports.empty?
              opoo "Could not find #{path}; omitting the potential new role column."
            else
              opoo "Could not find #{path}; Lead Maintainer promotion data is incomplete."
            end
            break
          end

          reports << report
          period_end = period_start
        end
        reports
      end

      sig {
        params(
          from:           String,
          to:             String,
          current_report: T.nilable([String, String, T::Hash[String, T::Hash[String, Integer]], T::Array[String]]),
        ).returns(T.nilable(T::Hash[String, [T::Boolean, T::Boolean]]))
      }
      def maintainer_activity_report(from, to, current_report: nil)
        maintainer_activity_totals(from, to, current_report:)&.transform_values do |totals, _capped|
          activity_met(totals.values)
        end
      end

      # Returns each user's per-repository totals and whether any contributing report capped their counts.
      sig {
        params(
          from:           String,
          to:             String,
          current_report: T.nilable([String, String, T::Hash[String, T::Hash[String, Integer]], T::Array[String]]),
        ).returns(T.nilable(T::Hash[String, [T::Hash[String, Integer], T::Boolean]]))
      }
      def maintainer_activity_totals(from, to, current_report: nil)
        require "csv"

        reports = T.let([], T::Array[T::Hash[String, T::Hash[String, Integer]]])
        capped_users = T.let([], T::Array[String])
        while from < to
          if current_report && current_report[0] == from && current_report[1] <= to
            reports << current_report[2]
            capped_users.concat(current_report[3])
            from = current_report[1]
            next
          end

          report_to, path = Dir["brew-contributions-#{from}-to-*.csv"].filter_map do |file|
            date = file[/\Abrew-contributions-\d{4}-\d{2}-\d{2}-to-(\d{4}-\d{2}-\d{2})\.csv\z/, 1]
            [date, file] if date && date > from && date <= to
          end.max
          return if path.nil? || report_to.nil?

          totals = T.let({}, T::Hash[String, T::Hash[String, Integer]])
          CSV.foreach(path, headers: true) do |row|
            next unless row.is_a?(CSV::Row)

            unless row.headers.include?("brew first approvals")
              opoo "#{path} uses obsolete activity criteria; regenerate it before assessing roles."
              return nil
            end

            username = row["username"]
            next unless username.is_a?(String)

            totals[username.downcase] = PRIMARY_REPOS.to_h do |repository|
              [repository, Integer(row.fetch("#{repository_name(repository)} total"))]
            end
            capped_users << username.downcase if row["capped"] == "true"
          end
          reports << totals
          from = report_to
        end
        reports.fetch(0).keys.filter_map do |user|
          next unless reports.all? { |report| report.key?(user) }

          user_totals = PRIMARY_REPOS.to_h do |repository|
            [repository, reports.sum { |report| report.fetch(user).fetch(repository) }]
          end
          [user, [user_totals, capped_users.include?(user)]]
        end.to_h
      end

      sig {
        params(
          user:                  String,
          role:                  String,
          maintainer_since_date: T.nilable(Date),
          period_end:            Date,
          activity:              [T::Boolean, T::Boolean],
          previous_reports:      T::Array[T::Hash[String, [T::Boolean, T::Boolean]]],
        ).returns(T.nilable(String))
      }
      def potential_maintainer_role(user, role, maintainer_since_date, period_end, activity, previous_reports)
        maintainer_activity_met, lead_activity_met = activity
        previous_activity = previous_reports.first&.[](user.downcase)
        return if previous_activity.nil?

        return "None" if !maintainer_activity_met && !previous_activity.fetch(0)

        if role == "Lead Maintainer"
          return "Maintainer" if !lead_activity_met && !previous_activity.fetch(1)

          return role
        end

        return role if maintainer_since_date.nil? || maintainer_since_date > period_end.prev_year(3)
        return role unless lead_activity_met

        previous_lead_activity = previous_reports.map { |report| report[user.downcase]&.fetch(1) }
        return if previous_lead_activity.length < LEAD_ACTIVITY_PERIODS - 1 || previous_lead_activity.any?(&:nil?)

        previous_lead_activity.all?(true) ? "Lead Maintainer" : role
      end

      private

      sig { params(repositories: T::Array[String], required: T::Boolean).returns(T::Hash[String, [Pathname, String]]) }
      def prepare_contribution_repositories(repositories, required:)
        require "utils/git"

        repository_refs = T.let({}, T::Hash[String, [Pathname, String]])
        repositories.each do |repository|
          repository_path, tap = repository_path_and_tap(repository)
          if repository_path && tap && !repository_path.exist?
            opoo "Repository #{repository} not yet tapped! Tapping it now..."
            tap.install(force: true)
          end
          unless repository_path&.exist?
            odie "Could not find a local Git repository for #{repository}." if required
            next
          end

          $stderr.puts "Fetching latest commits for #{repository}..."
          system_command!(Utils::Git.git,
                          args:         ["-C", repository_path, "fetch", "--quiet", "--force", "origin",
                                         "+refs/heads/*:refs/remotes/origin/*"],
                          print_stderr: false)
          system_command!(Utils::Git.git,
                          args:         ["-C", repository_path, "remote", "set-head", "origin", "--auto"],
                          print_stderr: false)

          repository_refs[repository] = [repository_path, "origin/HEAD"]
        end
        repository_refs
      end

      sig { params(readme: String, user: String, name: String).returns(T::Boolean) }
      def readme_mentions?(readme, user, name)
        readme = readme.dup.force_encoding(Encoding::UTF_8)
        readme.include?("https://github.com/#{user}") || readme.include?(name)
      end

      sig {
        params(
          pull_request:           T::Hash[String, T.untyped],
          authored_pull_requests: T::Set[String],
          merged_pull_requests:   T::Set[String],
        ).void
      }
      def add_merged_pull_request_id(pull_request, authored_pull_requests, merged_pull_requests)
        number = pull_request["number"]
        return unless number.is_a?(Integer)

        pull_request_id = number.to_s
        authored_pull_requests << pull_request_id
        merged_pull_requests << pull_request_id
      end

      sig {
        params(
          counts:                 T::Hash[Symbol, Integer],
          authored_pull_requests: T::Set[String],
          merged_pull_requests:   T::Set[String],
        ).void
      }
      def update_merged_pull_request_counts(counts, authored_pull_requests, merged_pull_requests)
        unless authored_pull_requests.empty?
          counts[:merged_pr_author] = [authored_pull_requests.length, MAX_CONTRIBUTIONS].min
        end
        return if merged_pull_requests.empty?

        counts[:merged_pr] = [merged_pull_requests.length, MAX_CONTRIBUTIONS].min
      end

      sig {
        params(name: String, email: String, identity_users: T::Hash[String, String]).returns(T.nilable(String))
      }
      def user_for_git_identity(name, email, identity_users)
        noreply_username = github_noreply_username(email)
        identity_users[email.downcase] ||
          (identity_users[noreply_username.downcase] if noreply_username) ||
          identity_users[name.strip.downcase]
      end

      # Only GitHub no-reply addresses embed a username; other emails' local parts are not identities.
      sig { params(email: String).returns(T.nilable(String)) }
      def github_noreply_username(email)
        email[/\A(?:\d+\+)?([^@]+)@users\.noreply\.github\.com\z/i, 1]
      end

      sig { params(counts: T::Hash[Symbol, Integer], type: Symbol).void }
      def increment_contribution_count(counts, type)
        count = counts.fetch(type)
        counts[type] = count + 1 if count < MAX_CONTRIBUTIONS
      end

      sig { params(repository: String).returns([T.nilable(Pathname), T.nilable(Tap)]) }
      def repository_path_and_tap(repository)
        return [HOMEBREW_REPOSITORY, nil] if repository == "Homebrew/brew"
        return [nil, nil] if repository.exclude?("/homebrew-")

        require "tap"
        tap = Tap.fetch(repository)
        return [nil, nil] if tap.user == "Homebrew" && DEPRECATED_OFFICIAL_TAPS.include?(tap.repository)

        [tap.path, tap]
      end

      sig { params(from: T.nilable(String), to: T.nilable(String)).returns(String) }
      def time_period(from:, to:)
        if from && to
          "between #{from} and #{to}"
        elsif from
          "after #{from}"
        elsif to
          "before #{to}"
        else
          "in all time"
        end
      end

      sig { params(results: T::Hash[String, T::Hash[Symbol, Integer]]).returns(T::Hash[Symbol, Integer]) }
      def total(results)
        totals = {}

        results.each_value do |counts|
          counts.each do |kind, count|
            totals[kind] ||= 0
            totals[kind] += count
          end
        end

        totals
      end

      sig { params(contributions: T::Hash[Symbol, Integer]).returns(Integer) }
      def contribution_count(contributions)
        contributions.values.sum
      end

      sig { params(repositories: T::Hash[String, T::Hash[Symbol, Integer]]).returns(T::Boolean) }
      def lead_activity_met?(repositories)
        repositories.count do |_, counts|
          contribution_count(counts.slice(*QUALIFYING_CONTRIBUTION_TYPES)) >= LEAD_REPOSITORY_ACTIVITY_THRESHOLD
        end >= LEAD_ACTIVITY_REPOSITORIES
      end

      sig { params(totals: T::Array[Integer]).returns([T::Boolean, T::Boolean]) }
      def activity_met(totals)
        [totals.sum >= MAINTAINER_ACTIVITY_THRESHOLD,
         totals.count { |total| total >= LEAD_REPOSITORY_ACTIVITY_THRESHOLD } >= LEAD_ACTIVITY_REPOSITORIES]
      end

      sig { params(period_end: Date).returns(Date) }
      def activity_period_end(period_end)
        Date.new(period_end.year, period_end.month, 1).prev_month(period_end.month % ACTIVITY_PERIOD_MONTHS)
      end

      sig {
        params(repositories: T::Hash[String, T::Hash[Symbol, Integer]], repository: String).returns(T::Boolean)
      }
      def review_checks_complete?(repositories, repository)
        repository_totals = repositories.transform_values do |counts|
          contribution_count(counts.slice(*MAINTAINER_CONTRIBUTION_TYPES))
        end
        _, lead_met = activity_met(repository_totals.values)
        lead_met ||
          (repository_totals.fetch(repository) >= LEAD_REPOSITORY_ACTIVITY_THRESHOLD &&
           repository_totals.values.sum >= MAINTAINER_ACTIVITY_THRESHOLD)
      end

      sig { params(quarter: Integer, current_year: Integer).returns([String, String]) }
      def reporting_quarter_dates(quarter, current_year = Date.today.year)
        # These aren't standard quarterly dates. We've chosen our own so that we
        # can use recent maintainer activity stats as part of checking
        # eligibility for expensed attendance at the AGM in February each year.
        last_year = current_year - 1
        dates = {
          1 => [Date.new(last_year, 12, 1).iso8601, Date.new(current_year, 3, 1).iso8601],
          2 => [Date.new(current_year, 3, 1).iso8601, Date.new(current_year,  6, 1).iso8601],
          3 => [Date.new(current_year, 6, 1).iso8601, Date.new(current_year,  9, 1).iso8601],
          4 => [Date.new(current_year, 9, 1).iso8601, Date.new(current_year, 12, 1).iso8601],
        }
        dates.fetch(quarter)
      end
    end
  end
end
