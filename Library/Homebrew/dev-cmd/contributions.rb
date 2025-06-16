# typed: strict
# frozen_string_literal: true

require "abstract_command"

module Homebrew
  module DevCmd
    class Contributions < AbstractCommand
      PRIMARY_REPOS = T.let(%w[brew core cask].freeze, T::Array[String])
      SUPPORTED_REPOS = T.let([
        PRIMARY_REPOS,
        OFFICIAL_CMD_TAPS.keys.map { |t| t.delete_prefix("homebrew/") },
        OFFICIAL_CASK_TAPS.reject { |t| t == "cask" },
      ].flatten.freeze, T::Array[String])
      MAX_REPO_COMMITS = 1000

      cmd_args do
        usage_banner "`contributions` [--user=<email|username>] [<--repositories>`=`] [<--csv>]"
        description <<~EOS
          Summarise contributions to Homebrew repositories.
        EOS

        comma_array "--repositories",
                    description: "Specify a comma-separated list of repositories to search. " \
                                 "Supported repositories: #{SUPPORTED_REPOS.map { |t| "`#{t}`" }.to_sentence}. " \
                                 "Omitting this flag, or specifying `--repositories=primary`, searches only the " \
                                 "main repositories: brew,core,cask. " \
                                 "Specifying `--repositories=all`, searches all repositories. "
        flag "--from=",
             description: "Date (ISO-8601 format) to start searching contributions. " \
                          "Omitting this flag searches the last year."

        flag "--to=",
             description: "Date (ISO-8601 format) to stop searching contributions."

        comma_array "--user=",
                    description: "Specify a comma-separated list of GitHub usernames or email addresses to find " \
                                 "contributions from. Omitting this flag searches maintainers."

        switch "--csv",
               description: "Print a CSV of contributions across repositories over the time period."
      end

      sig { override.void }
      def run
        Homebrew.install_bundler_gems!(groups: ["contributions"]) if args.csv?

        results = {}
        grand_totals = {}

        repos = T.must(
          if args.repositories.blank? || args.repositories&.include?("primary")
            PRIMARY_REPOS
          elsif args.repositories&.include?("all")
            SUPPORTED_REPOS
          else
            args.repositories
          end,
        )

        repos.each do |repo|
          if SUPPORTED_REPOS.exclude?(repo)
            odie "Unsupported repository: #{repo}. Try one of #{SUPPORTED_REPOS.join(", ")}."
          end
        end

        from = args.from.presence || Date.today.prev_year.iso8601

        contribution_types = [:author, :committer, :coauthor, :review]

        require "utils/github"
        users = args.user.presence || GitHub.members_by_team("Homebrew", "maintainers").keys
        users.each do |username|
          # TODO: Using the GitHub username to scan the `git log` undercounts some
          # contributions as people might not always have configured their Git
          # committer details to match the ones on GitHub.
          # TODO: Switch to using the GitHub APIs instead of `git log` if
          # they ever support trailers.
          results[username] = scan_repositories(repos, username, from:)
          grand_totals[username] = total(results[username])

          contributions = contribution_types.filter_map do |type|
            type_count = grand_totals[username][type]
            next if type_count.to_i.zero?

            "#{Utils.pluralize("time", type_count, include_count: true)} (#{type})"
          end
          contributions <<
            "#{Utils.pluralize("time", grand_totals[username].values.sum, include_count: true)} (total)"

          contributions_string = [
            "#{username} contributed",
            *contributions.to_sentence,
            "#{time_period(from:, to: args.to)}.",
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

      sig { params(repo: String).returns(Pathname) }
      def find_repo_path_for_repo(repo)
        return HOMEBREW_REPOSITORY if repo == "brew"

        require "tap"
        Tap.fetch("homebrew", repo).path
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
          csv << %w[user repo author committer coauthor review total]

          totals.sort_by { |_, v| -v.values.sum }.each do |user, total|
            csv << grand_total_row(user, total)
          end
        end
      end

      sig {
        params(
          user:        String,
          grand_total: T::Hash[Symbol, Integer],
        ).returns(
          [String, String, T.nilable(Integer), T.nilable(Integer), T.nilable(Integer), T.nilable(Integer), Integer],
        )
      }
      def grand_total_row(user, grand_total)
        [
          user,
          "all",
          grand_total[:author],
          grand_total[:committer],
          grand_total[:coauthor],
          grand_total[:review],
          grand_total.values.sum,
        ]
      end

      sig {
        params(
          repos:  T::Array[String],
          person: String,
          from:   String,
        ).returns(T::Hash[Symbol, T.untyped])
      }
      def scan_repositories(repos, person, from:)
        data = {}
        return data if repos.blank?

        require "tap"
        require "utils/github"
        repos.each do |repo|
          repo_path = find_repo_path_for_repo(repo)
          tap = Tap.fetch("homebrew", repo)
          unless repo_path.exist?
            opoo "Repository #{repo} not yet tapped! Tapping it now..."
            tap.install
          end

          repo_full_name = if repo == "brew"
            "homebrew/brew"
          else
            tap.full_name
          end

          puts "Determining contributions for #{person} on #{repo_full_name}..." if args.verbose?

          author_commits, committer_commits = GitHub.count_repo_commits(repo_full_name, person,
                                                                        from:, to: args.to, max: MAX_REPO_COMMITS)
          data[repo] = {
            author:    author_commits,
            committer: committer_commits,
            coauthor:  git_log_trailers_cmd(repo_path, person, "Co-authored-by", from:, to: args.to),
            review:    count_reviews(repo_full_name, person, from:, to: args.to),
          }
        end

        data
      end

      sig { params(results: T::Hash[Symbol, T.untyped]).returns(T::Hash[Symbol, Integer]) }
      def total(results)
        totals = { author: 0, committer: 0, coauthor: 0, review: 0 }

        results.each_value do |counts|
          counts.each do |kind, count|
            totals[kind] += count
          end
        end

        totals
      end

      sig {
        params(repo_path: Pathname, person: String, trailer: String, from: T.nilable(String),
               to: T.nilable(String)).returns(Integer)
      }
      def git_log_trailers_cmd(repo_path, person, trailer, from:, to:)
        cmd = ["git", "-C", repo_path, "log", "--oneline"]
        cmd << "--format='%(trailers:key=#{trailer}:)'"
        cmd << "--before=#{to}" if to
        cmd << "--after=#{from}" if from

        Utils.safe_popen_read(*cmd).lines.count { |l| l.include?(person) }
      end

      sig {
        params(repo_full_name: String, person: String, from: T.nilable(String),
               to: T.nilable(String)).returns(Integer)
      }
      def count_reviews(repo_full_name, person, from:, to:)
        require "utils/github"
        GitHub.count_issues("", is: "pr", repo: repo_full_name, reviewed_by: person, review: "approved", from:, to:)
      rescue GitHub::API::ValidationFailedError
        if args.verbose?
          onoe "Couldn't search GitHub for PRs by #{person}. Their profile might be private. Defaulting to 0."
        end
        0 # Users who have made their contributions private are not searchable to determine counts.
      end
    end
  end
end
