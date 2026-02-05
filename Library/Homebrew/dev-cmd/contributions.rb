# typed: strict
# frozen_string_literal: true

require "abstract_command"

module Homebrew
  module DevCmd
    class Contributions < AbstractCommand
      PRIMARY_REPOS = T.let(%w[
        Homebrew/brew
        Homebrew/homebrew-core
        Homebrew/homebrew-cask
      ].freeze, T::Array[String])
      CONTRIBUTION_TYPES = T.let({
        merged_pr_author:   "merged PR author",
        approved_pr_review: "approved PR reviewer",
        committer:          "commit author or committer",
        coauthor:           "commit coauthor",
      }.freeze, T::Hash[Symbol, String])
      MAX_COMMITS = T.let(1000, Integer)
      MAX_PR_SEARCH = T.let(100, Integer)

      cmd_args do
        usage_banner "`contributions` [`--user=`] [`--repositories=`] [`--quarter=`] [`--from=`] [`--to=`] [`--csv`]"
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
        conflicts "--organisation", "--repositories"
        conflicts "--organisation", "--team"
        conflicts "--user", "--team"
      end

      sig { override.void }
      def run
        odie "Cannot get contributions as `$HOMEBREW_NO_GITHUB_API` is set!" if Homebrew::EnvConfig.no_github_api?

        Homebrew.install_bundler_gems!(groups: ["contributions"]) if args.csv?

        require "utils/github"

        results = {}
        grand_totals = {}

        quarter = args.quarter.presence.to_i
        odie "Value for `--quarter` must be between 1 and 4." if args.quarter.present? && !quarter.between?(1, 4)
        from = args.from.presence || quarter_dates[quarter]&.first || Date.today.prev_year.iso8601
        to = args.to.presence || quarter_dates[quarter]&.last || (Date.today + 1).iso8601
        puts "Date range is #{time_period(from:, to:)}." if args.verbose?

        organisation = nil

        users = if (team = args.team.presence)
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

        repositories = if (org = organisation.presence) || (org = args.organisation.presence)
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
        organisation ||= T.must(repositories.fetch(0).split("/").first)

        users.each do |username|
          # TODO: Using the GitHub username to scan the `git log` undercounts some
          #       contributions as people might not always have configured their Git
          #       committer details to match the ones on GitHub.
          # TODO: Switch to using the GitHub APIs instead of `git log` if
          #       they ever support trailers.
          results[username] = scan_repositories(organisation, repositories, username, from:, to:)
          grand_totals[username] = total(results[username])

          search_types = [:merged_pr_author, :approved_pr_review].freeze
          greater_than_total = T.let(false, T::Boolean)
          contributions = CONTRIBUTION_TYPES.keys.filter_map do |type|
            type_count = grand_totals[username][type]
            next if type_count.nil? || type_count.zero?

            count_prefix = ""
            if (search_types.include?(type) && type_count == MAX_PR_SEARCH) ||
               (type == :committer && type_count == MAX_COMMITS)
              greater_than_total ||= true
              count_prefix = ">="
            end

            pretty_type = CONTRIBUTION_TYPES.fetch(type)
            "#{count_prefix}#{Utils.pluralize("time", type_count, include_count: true)} (#{pretty_type})"
          end
          total = Utils.pluralize("time", grand_totals[username].values.sum, include_count: true)
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

      private

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
          csv << ["user", "repository", *CONTRIBUTION_TYPES.keys, "total"]

          totals.sort_by { |_, v| -v.values.sum }.each do |user, total|
            csv << grand_total_row(user, total)
          end
        end
      end

      sig { params(user: String, grand_total: T::Hash[Symbol, Integer]).returns(T::Array[T.any(String, T.nilable(Integer))]) }
      def grand_total_row(user, grand_total)
        grand_totals = grand_total.slice(*CONTRIBUTION_TYPES.keys).values
        [user, "all",  *grand_totals, grand_totals.sum]
      end

      sig {
        params(
          organisation: String,
          repositories: T::Array[String],
          person:       String,
          from:         String,
          to:           String,
        ).returns(T::Hash[Symbol, T.untyped])
      }
      def scan_repositories(organisation, repositories, person, from:, to:)
        data = {}
        return data if repositories.blank?

        require "utils/github"

        max = MAX_COMMITS
        verbose = args.verbose?

        puts "Querying pull requests for #{person} in #{organisation}..." if args.verbose?
        organisation_merged_prs =
          GitHub.search_merged_pull_requests_in_user_or_organisation(organisation, person, from:, to:)
        organisation_approved_reviews =
          GitHub.search_approved_pull_requests_in_user_or_organisation(organisation, person, from:, to:)

        require "utils/git"

        repositories.each do |repository|
          repository_path, tap = repository_path_and_tap(repository)
          if repository_path && tap && !repository_path.exist?
            opoo "Repository #{repository} not yet tapped! Tapping it now..."
            tap.install(force: true)
          end

          repository_full_name = tap&.full_name
          repository_full_name ||= repository

          repository_api_url = "#{GitHub::API_URL}/repos/#{repository_full_name}"

          puts "Determining contributions for #{person} on #{repository_full_name}..." if args.verbose?

          merged_pr_author = organisation_merged_prs.count do |pr|
            pr.fetch("repository_url") == repository_api_url
          end
          approved_pr_review = organisation_approved_reviews.count do |pr|
            pr.fetch("repository_url") == repository_api_url
          end
          committer = GitHub.count_repository_commits(repository_full_name, person, max:, verbose:, from:, to:)
          coauthor = Utils::Git.count_coauthors(repository_path, person, from:, to:)

          data[repository] = { merged_pr_author:, approved_pr_review:, committer:, coauthor: }
        rescue GitHub::API::RateLimitExceededError => e
          sleep_seconds = e.reset - Time.now.to_i
          opoo "GitHub rate limit exceeded, sleeping for #{sleep_seconds} seconds..."
          sleep sleep_seconds
          retry
        end

        data
      end

      sig { params(results: T::Hash[Symbol, T.untyped]).returns(T::Hash[Symbol, Integer]) }
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

      sig { returns(T::Hash[Integer, T::Array[String]]) }
      def quarter_dates
        # These aren't standard quarterly dates. We've chosen our own so that we
        # can use recent maintainer activity stats as part of checking
        # eligibility for expensed attendance at the AGM in February each year.
        current_year = Date.today.year
        last_year = current_year - 1
        {
          1 => [Date.new(last_year, 12, 1).iso8601, Date.new(current_year, 3, 1).iso8601],
          2 => [Date.new(current_year, 3, 1).iso8601, Date.new(current_year,  6, 1).iso8601],
          3 => [Date.new(current_year, 6, 1).iso8601, Date.new(current_year,  9, 1).iso8601],
          4 => [Date.new(current_year, 9, 1).iso8601, Date.new(current_year, 12, 1).iso8601],
        }
      end
    end
  end
end
