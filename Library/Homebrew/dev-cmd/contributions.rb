# typed: strict
# frozen_string_literal: true

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
      MAX_PR_SEARCH = 100
      # https://docs.brew.sh/Homebrew-Governance#maintainer
      MAINTAINER_ACTIVITY_THRESHOLD = 50
      # https://docs.brew.sh/Homebrew-Governance#lead-maintainer
      LEAD_REPOSITORY_ACTIVITY_THRESHOLD = 25
      MAX_CONTRIBUTIONS = T.let(MAINTAINER_ACTIVITY_THRESHOLD * 10, Integer)
      QUALIFYING_CONTRIBUTION_TYPES = [:merged_pr, :approved_pr_review, :coauthor].freeze

      cmd_args do
        usage_banner "`contributions` [`--user=`] [`--repositories=`] [`--quarter=`] [`--from=`] [`--to=`] " \
                     "[`--csv`] [`--maintainer-report-csv=`]"
        description <<~EOS
          Summarise contributions to Homebrew repositories.
        EOS
        comma_array "--user=",
                    description: "Specify a comma-separated list of GitHub usernames or email addresses to find " \
                                 "contributions from. Omitting this flag searches Homebrew maintainers."
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
        flag   "--maintainer-report-csv=",
               description: "Print a CSV of Maintainer and Lead Maintainer activity criteria using fetched Git " \
                            "histories and GitHub's existing approved-review search for the Homebrew " \
                            "governance quarter, for example " \
                            "`--maintainer-report-csv=2026-2`. " \
                            "Also write it to `brew-contributions-FROM-to-TO.csv` in the current directory. " \
                            "Only Maintainers listed at the end of that quarter are included. " \
                            "The `new role` value must show a downgrade for two consecutive " \
                            "quarters before a downgrade is applied. " \
                            "Review searches return at most 100 results and other counts are capped at 500 per " \
                            "repository and contribution type. Repository-scoped follow-up searches ensure " \
                            "role activity checks remain accurate when a count is capped. Completed-period " \
                            "GitHub searches are cached in Homebrew's cache and removed by normal cache pruning. " \
                            "`YEAR-1` is December of the previous year through February, `YEAR-2` is March " \
                            "through May, `YEAR-3` is June through August and `YEAR-4` is September through " \
                            "November."
        conflicts "--organisation", "--repositories"
        conflicts "--organisation", "--team"
        conflicts "--user", "--team"
        conflicts "--maintainer-report-csv", "--user"
        conflicts "--maintainer-report-csv", "--repositories"
        conflicts "--maintainer-report-csv", "--organisation"
        conflicts "--maintainer-report-csv", "--team"
        conflicts "--maintainer-report-csv", "--quarter"
        conflicts "--maintainer-report-csv", "--from"
        conflicts "--maintainer-report-csv", "--to"
      end

      sig { override.void }
      def run
        maintainer_report_csv = args.maintainer_report_csv
        odie "Cannot get contributions as `$HOMEBREW_NO_GITHUB_API` is set!" if Homebrew::EnvConfig.no_github_api?
        Homebrew.install_bundler_gems!(groups: ["contributions"]) if args.csv? || maintainer_report_csv

        if maintainer_report_csv
          odie "`--maintainer-report-csv` must be in YEAR-QUARTER format." unless maintainer_report_csv.match?(
            /\A\d{4}-[1-4]\z/,
          )
          quarter_parts = maintainer_report_csv.split("-")
          from, to = reporting_quarter_dates(quarter_parts.fetch(1).to_i, quarter_parts.fetch(0).to_i)
          $stderr.puts "Maintainer report dates: #{from}-to-#{to}"
        else
          quarter = args.quarter.presence.to_i
          odie "Value for `--quarter` must be between 1 and 4." if args.quarter.present? && !quarter.between?(1, 4)
          quarter_dates = reporting_quarter_dates(quarter) unless quarter.zero?
          from = args.from.presence || quarter_dates&.first || Date.today.prev_year.iso8601
          to = args.to.presence || quarter_dates&.last || (Date.today + 1).iso8601
          puts "Date range is #{time_period(from:, to:)}." if args.verbose?
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
        elsif (users = args.user.presence)
          users
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
            results, grand_totals, user_names, lead_maintainers, maintainer_since_dates, to
          )
          File.write("brew-contributions-#{from}-to-#{to}.csv", csv)
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
            *contributions.to_sentence,
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
        quarter_end_ref = Utils.safe_popen_read(
          Utils::Git.git, "-C", brew_path, "rev-list", "-1", "--before=#{to}", brew_ref, "--", "README.md"
        ).strip
        odie "Could not find Homebrew/brew's README at the end of the reporting quarter." if quarter_end_ref.empty?

        user_names = T.let({}, T::Hash[String, String])
        lead_maintainers = T.let({}, T::Hash[String, T::Boolean])
        Utils.safe_popen_read(Utils::Git.git, "-C", brew_path, "show", "#{quarter_end_ref}:README.md")
             .dup.force_encoding(Encoding::UTF_8).each_line do |line|
          lead = line.start_with?("Homebrew's [Lead Maintainers]")
          next if !lead &&
                  !line.start_with?("Homebrew's other Maintainers") &&
                  !line.start_with?("Homebrew's maintainers are")

          line.scan(%r{\[([^\]]+)\]\(https://github\.com/([A-Za-z\d-]+)\)}).each do |match|
            next unless match.is_a?(Array)

            name = match.fetch(0)
            user = match.fetch(1)
            user_names[user] = name
            lead_maintainers[user.downcase] = true if lead
          end
        end
        odie "Could not read the maintainers from Homebrew/brew's README." if user_names.empty?

        $stderr.puts "Scanning contributions for #{user_names.length} maintainers..."
        maintainer_since_dates = user_names.to_h do |user, name|
          [user, maintainer_since(brew_path, quarter_end_ref, user, name)]
        end
        [user_names, lead_maintainers, maintainer_since_dates]
      end

      sig { params(repository_path: Pathname, ref: String, user: String, name: String).returns(T.nilable(String)) }
      def maintainer_since(repository_path, ref, user, name)
        require "utils/git"

        candidates = ["https://github.com/#{user}", name].flat_map do |identity|
          Utils.safe_popen_read(
            Utils::Git.git, "-C", repository_path, "log", ref, "--fixed-strings",
            "-S#{identity}", "--format=%H%x1f%cs", "--", "README.md"
          ).lines(chomp: true)
        end
        candidates.uniq!
        candidates.sort_by! { |candidate| candidate.split("\x1f", 2).fetch(1) }
        candidates.each do |candidate|
          commit, date = candidate.split("\x1f", 2)
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
        git_authored_pull_requests = users.keys.to_h do |user|
          [user, repositories.to_h { |repository| [repository, Set.new] }]
        end
        git_merged_pull_requests = users.keys.to_h do |user|
          [user, repositories.to_h { |repository| [repository, Set.new] }]
        end
        repository_refs.each do |repository, (repository_path, ref)|
          require "utils/git"
          output = Utils.safe_popen_read(
            Utils::Git.git, "-C", repository_path, "log", ref, "--since=#{from}", "--before=#{to}",
            "--format=%H%x1f%P%x1f%an%x1f%ae%x1f%B%x1e"
          )
          authored_pull_requests = users.keys.to_h { |user| [user, Set.new] }
          merged_pull_requests = users.keys.to_h { |user| [user, Set.new] }
          parse_git_log(output, users, authored_pull_requests:, merged_pull_requests:).each do |user, counts|
            results.fetch(user)[repository] = counts
            git_authored_pull_requests.fetch(user)[repository] = authored_pull_requests.fetch(user)
            git_merged_pull_requests.fetch(user)[repository] = merged_pull_requests.fetch(user)
          end
        end

        merged_range = "#{from}..#{Date.iso8601(to).prev_day.iso8601}"
        users.each_key do |user|
          github_user = github_users.fetch(user)
          next if github_user.nil?

          cache_key = ["merged-at", organisation, github_user, merged_range].join("\0")
          merged_pull_requests = github_search_with_rate_limit(cache_key, to:) do
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
            cache_key = ["merged-at", repository, github_user, merged_range].join("\0")
            repository_pull_requests = github_search_with_rate_limit(cache_key, to:) do
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
        review_users.each_with_index do |(user, github_user), index|
          if progress
            $stderr.puts "Querying approved-review search for #{user} (#{index + 1}/#{review_users.length})..."
          end
          cache_key = ["approved", organisation, github_user, from, to].join("\0")
          approved_reviews = github_search_with_rate_limit(cache_key, to:) do
            GitHub.search_approved_pull_requests_in_user_or_organisation(organisation, github_user, from:, to:)
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
            cache_key = ["approved", repository, github_user, from, to].join("\0")
            repository_reviews = github_search_with_rate_limit(cache_key, to:) do
              GitHub.search_issues("", is: "pr", review: "approved", repo: repository, reviewed_by: github_user,
                                   from:, to:)
            end
            repository_counts[:approved_pr_review] = repository_reviews.length
          end
        end

        results
      end

      sig { params(user: String, to: String).returns(T.nilable(String)) }
      def github_username_for(user, to:)
        return user unless user.include?("@")
        if user.end_with?("@users.noreply.github.com")
          return user.delete_suffix("@users.noreply.github.com").sub(/\A\d+\+/,
                                                                     "")
        end

        cache_key = ["public-email", user].join("\0")
        matches = github_search_with_rate_limit(cache_key, to:) do
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

      sig {
        params(cache_key: String, to: String, block: T.proc.returns(T::Array[T::Hash[String, T.untyped]]))
          .returns(T::Array[T::Hash[String, T.untyped]])
      }
      def github_search_with_rate_limit(cache_key, to:, &block)
        cache_path = if Date.iso8601(to) <= Date.today
          HOMEBREW_CACHE/"contributions--#{Digest::SHA256.hexdigest("1\0#{cache_key}")}.json"
        end
        if cache_path&.file?
          begin
            cached_results = JSON.parse(cache_path.read)
            return cached_results if cached_results.is_a?(Array)
          rescue JSON::ParserError, Errno::ENOENT
            nil
          end
          cache_path.unlink if cache_path.exist?
        end

        results = yield
        if cache_path
          HOMEBREW_CACHE.mkpath
          cache_path.atomic_write(JSON.generate(results))
        end
        results
      rescue GitHub::API::RateLimitExceededError => e
        sleep_seconds = [e.reset - Time.now.to_i, 1].max
        opoo "GitHub rate limit exceeded, sleeping for #{sleep_seconds} seconds..."
        sleep sleep_seconds
        retry
      end

      sig {
        params(
          output:                 String,
          users:                  T::Hash[String, String],
          authored_pull_requests: T.nilable(T::Hash[String, T::Set[String]]),
          merged_pull_requests:   T.nilable(T::Hash[String, T::Set[String]]),
        )
          .returns(T::Hash[String, T::Hash[Symbol, Integer]])
      }
      def parse_git_log(output, users, authored_pull_requests: nil, merged_pull_requests: nil)
        counts = users.to_h do |user, _|
          [user, CONTRIBUTION_TYPES.keys.to_h { |type| [type, 0] }]
        end
        identity_users = T.let({}, T::Hash[String, String])
        users.each do |user, name|
          identity_users[user.downcase] = user
          identity_users[name.downcase] = user
          identity_users[user.split("@").first.to_s.sub(/\A\d+\+/, "").downcase] = user
        end
        records = output.split("\x1e").filter_map do |record|
          fields = record.strip.split("\x1f", 5)
          fields if fields.length == 5
        end
        record_identities = records.to_h do |fields|
          [fields.fetch(0), [fields.fetch(2), fields.fetch(3)]]
        end
        records.each do |fields|
          parents = fields.fetch(1).split
          source_owner = fields.fetch(4)[%r{\AMerge pull request #\d+ from ([^/\s]+)/}, 1]
          next if parents.length < 2 || source_owner.nil?

          user = identity_users[source_owner.downcase]
          source_identity = record_identities[parents.fetch(1)]
          next if user.nil? || source_identity.nil?

          name, email = source_identity
          identity_users[name.strip.downcase] ||= user
          identity_users[email.downcase] ||= user
          identity_users[email.split("@").first.to_s.sub(/\A\d+\+/, "").downcase] ||= user
        end
        commit_authors = T.let(records.to_h do |fields|
          sha = fields.fetch(0)
          author_name = fields.fetch(2)
          author_email = fields.fetch(3)
          [sha, user_for_git_identity(author_name, author_email, identity_users)]
        end, T::Hash[String, T.nilable(String)])

        records.each do |fields|
          parents_string = fields.fetch(1)
          author_name = fields.fetch(2)
          author_email = fields.fetch(3)
          body = fields.fetch(4)
          coauthors = body.scan(/^Co-authored-by:\s*(.*?)\s*<([^>]+)>/i).filter_map do |match|
            next unless match.is_a?(Array)

            user_for_git_identity(match.fetch(0), match.fetch(1), identity_users)
          end
          coauthors.uniq.each do |user|
            increment_contribution_count(counts.fetch(user), :coauthor)
          end

          parents = parents_string.split
          pull_request = body.match(%r{\AMerge pull request #(\d+) from ([^/\s]+)/})
          next if parents.length < 2 || pull_request.nil?

          merger = user_for_git_identity(author_name, author_email, identity_users)
          pull_request_id = pull_request[1]
          source_owner = pull_request[2]
          next if pull_request_id.nil? || source_owner.nil?

          author = identity_users[source_owner.downcase] || commit_authors[parents.fetch(1)]
          if author
            increment_contribution_count(counts.fetch(author), :merged_pr_author)
            authored_pull_requests&.fetch(author)&.add(pull_request_id)
          end
          increment_contribution_count(counts.fetch(merger), :merged_pr_merger) if merger
          [author, merger].compact.uniq.each do |user|
            increment_contribution_count(counts.fetch(user), :merged_pr)
            merged_pull_requests&.fetch(user)&.add(pull_request_id)
          end
        end

        counts
      end

      private

      sig {
        params(
          results:                T::Hash[String, T::Hash[String, T::Hash[Symbol, Integer]]],
          grand_totals:           T::Hash[String, T::Hash[Symbol, Integer]],
          user_names:             T::Hash[String, String],
          lead_maintainers:       T::Hash[String, T::Boolean],
          maintainer_since_dates: T::Hash[String, T.nilable(String)],
          to:                     String,
        ).returns(String)
      }
      def generate_maintainer_report_csv(results, grand_totals, user_names, lead_maintainers, maintainer_since_dates,
                                         to)
        require "csv"

        rows = results.sort_by do |user, _|
          qualifying_total = contribution_count(grand_totals.fetch(user).slice(*QUALIFYING_CONTRIBUTION_TYPES))
          [-qualifying_total, user.downcase]
        end
        rows.map! do |user, user_repositories|
          grand_total = grand_totals.fetch(user)
          repository_qualifying_totals = user_repositories.transform_values do |counts|
            contribution_count(counts.slice(*QUALIFYING_CONTRIBUTION_TYPES))
          end
          qualifying_total = contribution_count(grand_total.slice(*QUALIFYING_CONTRIBUTION_TYPES))
          maintainer_activity_met = qualifying_total >= MAINTAINER_ACTIVITY_THRESHOLD
          maintainer_since = maintainer_since_dates.fetch(user)
          maintainer_since_date = Date.iso8601(maintainer_since) if maintainer_since
          period_end = Date.iso8601(to)
          lead_maintainer = lead_maintainers.key?(user.downcase)
          lead_activity_met = lead_activity_met?(user_repositories)
          new_role = if lead_activity_met &&
                        (lead_maintainer ||
                         (maintainer_since_date && maintainer_since_date <= period_end.prev_year(3)))
            "Lead Maintainer"
          elsif maintainer_activity_met
            "Maintainer"
          else
            "None"
          end

          capped = grand_total.fetch(:merged_pr_author_hit_cap, 0).positive? ||
                   grand_total.fetch(:approved_pr_review_hit_cap, 0).positive?
          capped ||= user_repositories.any? do |_, counts|
            counts.fetch(:approved_pr_review) >= MAX_PR_SEARCH ||
              counts.except(:approved_pr_review).values.any? do |count|
                count >= MAX_CONTRIBUTIONS
              end
          end

          [
            user,
            user_names.fetch(user),
            maintainer_since,
            maintainer_since_date ? [(period_end - maintainer_since_date).to_i, 0].max : nil,
            *PRIMARY_REPOS.flat_map do |repository|
              counts = user_repositories.fetch(repository)
              [*counts.values_at(*CONTRIBUTION_TYPES.keys), repository_qualifying_totals.fetch(repository)]
            end,
            qualifying_total,
            maintainer_activity_met,
            lead_activity_met,
            capped,
            lead_maintainer ? "Lead Maintainer" : "Maintainer",
            new_role,
          ]
        end
        CSV.generate do |csv|
          csv << [
            "username", "name", "since", "tenure days",
            *PRIMARY_REPOS.flat_map do |repository|
              repository = repository.delete_prefix("Homebrew/").delete_prefix("homebrew-")
              [
                "#{repository} authored", "#{repository} merged", "#{repository} PRs",
                "#{repository} reviews", "#{repository} coauthored", "#{repository} total"
              ]
            end,
            "total", "maintainer met", "lead met", "capped", "role", "new role"
          ]
          rows.each { |row| csv << row }
        end
      end

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
        identity_users[name.strip.downcase] ||
          identity_users[email.downcase] ||
          identity_users[email.split("@").first.to_s.sub(/\A\d+\+/, "").downcase]
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

      sig { params(totals: T::Hash[String, T::Hash[Symbol, Integer]]).returns(String) }
      def generate_csv(totals)
        require "csv"

        CSV.generate do |csv|
          csv << %w[username repo authored merged PRs reviews coauthored total]

          totals.sort_by { |_, counts| -contribution_count(counts.slice(*QUALIFYING_CONTRIBUTION_TYPES)) }
                .each do |user, total|
            csv << grand_total_row(user, total)
          end
        end
      end

      sig { params(user: String, grand_total: T::Hash[Symbol, Integer]).returns(T::Array[T.any(String, T.nilable(Integer))]) }
      def grand_total_row(user, grand_total)
        grand_totals = grand_total.slice(*CONTRIBUTION_TYPES.keys).values
        qualifying_total = contribution_count(grand_total.slice(*QUALIFYING_CONTRIBUTION_TYPES))
        [user, "all", *grand_totals, qualifying_total]
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
        end >= 2
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
