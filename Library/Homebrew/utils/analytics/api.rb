# typed: strict
# frozen_string_literal: true

require "api"
require "fileutils"
require "github_packages"
require "utils/analytics"
require "utils/analytics/influx"
require "utils/analytics/formula_history"
require "utils/analytics/repository"
require "utils/analytics/releases"
require "utils/github"

module Utils
  module Analytics
    # Assemble cached analytics reports and write their API data.
    class API
      CATEGORIES = %w[
        build-error install install-on-request
        core-build-error core-install core-install-on-request
        cask-install core-cask-install os-version
        homebrew-devcmdrun-developer homebrew-env-config homebrew-os-arch-ci
        homebrew-prefixes homebrew-versions
        brew-command-run brew-command-run-options brew-test-bot-test
      ].freeze

      DAYS = %w[30 90 365].freeze
      MAX_RETRIES = 3

      sig {
        params(history: T.nilable(String), homebrew_site: T.nilable(String), legacy_homebrew: T.nilable(String),
               github_packages_limit: Integer).void
      }
      def initialize(history: nil, homebrew_site: nil, legacy_homebrew: nil, github_packages_limit: 1000)
        @history = history
        @homebrew_site = homebrew_site
        @legacy_homebrew = legacy_homebrew
        @github_packages_limit = github_packages_limit
        @github_query_credit = T.let(0, Integer)
      end

      sig { void }
      def generate
        generate_influx
        generate_repositories
        generate_releases
        generate_formula_history
        generate_github_packages
      end

      sig { void }
      def generate_influx
        influx = Utils::Analytics::Influx.new
        influx.setup_python
        SystemCommand.safe_system influx.venv_python, influx.influxdb_query_script, "--check"

        CATEGORIES.map { |category| category.delete_prefix("core-") }.uniq.each do |category|
          FileUtils.rm_rf ["_data/analytics/#{category}", "api/analytics/#{category}"]
        end

        CATEGORIES.each do |category|
          category_name = category.delete_prefix("core-")
          all_core = category != category_name
          data_source = ((category_name == "cask-install") ? "homebrew-cask" : "homebrew-core") if all_core
          measurement = case category_name
          when "install" then :formula_install
          when "install-on-request" then :formula_install_on_request
          when "os-version" then :os_versions
          when "brew-command-run" then :command_run
          when "brew-command-run-options" then :command_run_options
          when "brew-test-bot-test" then :test_bot_test
          else category_name.tr("-", "_").to_sym
          end
          DAYS.each do |days|
            next if days != "30" && category_name == "build-error" && all_core

            puts "Querying #{category} analytics over #{days} days"
            retries = 0
            begin
              data = influx.query(categories: [measurement], days_ago: days.to_i,
                                  all_core_formulae_json: all_core).fetch(0)
            rescue SystemExit
              raise if retries >= MAX_RETRIES

              sleep 4**(retries + 2)
              retries += 1
              puts "Retrying #{category} (#{retries}/#{MAX_RETRIES})..."
              retry
            end
            Utils::Analytics.write_api(category_name, "#{days}d", data, data_source:)
          end
        end
      end

      sig { returns(T::Array[T::Hash[String, String]]) }
      def blog_posts
        path = @homebrew_site
        return [] unless path

        Utils.safe_popen_read("git", "-C", path, "ls-tree", "-r", "--name-only", "HEAD", "--", "_posts")
             .lines(chomp: true).filter_map do |file|
          match = file.match(
            %r{\A_posts/(\d{4})-(\d{2})-(\d{2})-(homebrew-\d+\.\d+\.\d+|security-incident-disclosure)\.md\z},
          )
          next unless match

          post = { "date" => match.captures.first(3).join("-"),
                   "url"  => "https://brew.sh/#{match.captures.join("/")}/" }
          post["version"] = match[4].to_s.delete_prefix("homebrew-") if match[4].to_s.start_with?("homebrew-")
          post
        end
      end

      sig { void }
      def generate_releases
        data = Utils::Analytics::Releases.new(HOMEBREW_REPOSITORY).report
        if @history
          archived = archived_report("releases")
          %w[releases aggregates years].each do |key|
            data[key] = Array(data[key]).reject do |row|
              historical_row?(row, archived)
            end + Array(archived.fetch(key, [])).select { |row| historical_row?(row, archived) }
          end
        end
        announcements = blog_posts.filter_map do |post|
          [post.fetch("version"), post.fetch("url")] if post.key?("version")
        end.to_h
        %w[releases aggregates].each do |key|
          Array(data[key]).each do |row|
            case row
            when Hash
              row["blog_url"] = announcements[row.fetch("version")] if announcements.key?(row.fetch("version"))
            end
          end
        end
        Utils::Analytics.write_api("releases", "history", data)
      end

      sig { void }
      def generate_formula_history
        archived = archived_report("formula-history")
        data = Utils::Analytics::FormulaHistory.new(CoreTap.instance.path).report(
          start_year: case start_year = archived["start_year"]
          when Integer then start_year
          end,
        )
        catalogues = Utils::Analytics::Repository.new(CoreTap.instance.path, "Homebrew/homebrew-core").rows
        case rows = data.fetch("rows")
        when Array
          rows.each do |row|
            next unless row.is_a?(Hash)

            row["formulae"] = if data["complete"]
              catalogues.find { |catalogue| catalogue["period"] == row["period"] }&.fetch("formulae")
            end
          end
        else
          raise "Invalid formula history rows"
        end
        if @history
          data["rows"] = Array(data["rows"]).reject do |row|
            historical_row?(row, archived)
          end + Array(archived.fetch("rows", [])).select { |row| historical_row?(row, archived) }
        end
        case rows = data["rows"]
        when Array
          if (current = rows.find { |row| row.fetch("period") == "current" })
            Utils::Analytics::FormulaHistory::METRICS.each do |metric|
              values = rows.reject { |row| row.fetch("period") == "current" }.map { |row| row[metric] }
              current[metric] = values.sum if values.all?(Integer)
            end
          end
        end
        data["historical_backfill"] = archived["historical_backfill"] if archived["historical_backfill"]
        Utils::Analytics.write_api("formula-history", "history", data)
      end

      sig { void }
      def generate_github_packages
        analytics = JSON.parse(Pathname("_data/analytics/install/homebrew-core/30d.json").read)
        names = if CoreTap.instance.installed?
          Homebrew::API.with_no_api_env { CoreTap.instance.formula_names }
        else
          Homebrew::API::Formula.all_formulae.keys
        end
        counts = names.to_h do |name|
          [name, analytics.fetch("formulae").fetch(name, []).sum { |item| item.fetch("count").delete(",").to_i }]
        end
        names = download_formula_names(counts, limit: @github_packages_limit)
        pending = Queue.new
        results = Queue.new
        names.each { |name| pending << name }
        Array.new(4) do
          Thread.new do
            loop do
              name = begin
                pending.pop(true)
              rescue ThreadError
                break
              end
              downloads = GitHubPackages.downloads(name)
              unless downloads
                results << [name, nil]
                next
              end

              count = counts.fetch(name)
              results << [name, downloads.serialize.merge(
                "analytics_30d"        => count,
                "analytics_start_date" => analytics.fetch("start_date"),
                "analytics_end_date"   => analytics.fetch("end_date"),
                "analytics_ratio"      => ((downloads.last_30_days.to_f / count).round(2) if count.positive?),
              )]
            end
          end
        end.each(&:join)

        formulae = Array.new(results.size) { results.pop }.to_h
        data = {
          catalog_formulae:           counts.length,
          selected_formulae:          names.length,
          analytics_coverage_percent: if counts.values.sum.positive?
                                        (100.0 * names.sum { |name| counts.fetch(name) } / counts.values.sum).round(2)
          end,
          unavailable_formulae:       names.select { |name| formulae[name].nil? }.sort,
          formulae:                   formulae.compact.sort.to_h,
          totals:                     {
            all_time:        formulae.compact.values.sum { |row| row.fetch("all_time") },
            last_30_days:    formulae.compact.values.sum { |row| row.fetch("last_30_days") },
            analytics_30d:   formulae.compact.values.sum { |row| row.fetch("analytics_30d") },
            analytics_ratio: if (ratios = formulae.compact.values.filter_map { |row| row["analytics_ratio"] }).any?
                               (ratios.sum / ratios.size).round(2)
            end,
          },
        }
        Utils::Analytics.write_api("github-packages", "30d", data)
      end

      sig { params(counts: T::Hash[String, Integer], limit: Integer).returns(T::Array[String]) }
      def download_formula_names(counts, limit:)
        counts.keys.sort_by { |name| [-counts.fetch(name), name] }.first(limit)
      end

      sig { params(repository: String, from: String, to: String).returns(T::Hash[String, T.any(String, Integer)]) }
      def github_activity(repository, from:, to:)
        cache = HOMEBREW_CACHE/"analytics/github/#{repository}/#{from}-#{to}.json"
        if cache.exist?
          cached = JSON.parse(cache.read)
          if cached.fetch("github_fetched_at") >= to ||
             cached.fetch("github_fetched_at").start_with?(Time.now.utc.strftime("%F"))
            return cached.merge("github_queries" => 0)
          end
        end
        if from >= to
          return { "pull_requests_opened" => 0, "issues_opened" => 0,
                   "github_fetched_at" => Time.now.utc.iso8601, "github_queries" => 0 }
        end

        raise "Repository analytics require the GitHub API" if Homebrew::EnvConfig.no_github_api?

        # Share spare requests across repositories, reserving two searches for fallback.
        budget = 4 + @github_query_credit
        requests = 0
        previous = cache.dirname.glob("#{from}-*.json").sort.rfind do |path|
          cutoff = path.basename.to_s.delete_prefix("#{from}-").delete_suffix(".json")
          cutoff < to && JSON.parse(path.read).fetch("github_fetched_at") >= cutoff
        end
        if previous && Date.iso8601(from).year == Date.iso8601(to).year
          cutoff = previous.basename.to_s.delete_prefix("#{from}-").delete_suffix(".json")
          records = {}
          (budget - 2).times do |page|
            entries = GitHub::API.open_rest("https://api.github.com/repos/#{repository}/issues?" \
                                            "state=all&sort=created&direction=desc&per_page=100&page=#{page + 1}" \
                                            "&since=#{cutoff}T00:00:00Z")
            requests += 1
            entries.each do |entry|
              date = entry.fetch("created_at")
              next if date < cutoff || date >= to

              records[entry.fetch("number")] = entry.key?("pull_request") ? "pull_requests_opened" : "issues_opened"
            end
            next if entries.length >= 100 && entries.last.fetch("created_at") >= cutoff

            counts = JSON.parse(previous.read).slice("pull_requests_opened", "issues_opened")
            records.values.tally.each { |metric, count| counts[metric] += count }
            counts.merge!("github_fetched_at" => Time.now.utc.iso8601, "github_queries" => requests,
                          "github_method" => "incremental list")
            @github_query_credit = budget - requests
            cache.atomic_write(JSON.generate(counts))
            return counts
          end
        end

        counts = {
          "pull_requests_opened" => ["pr", "created"],
          "issues_opened"        => ["issue", "created"],
        }.to_h do |metric, (type, date)|
          # Search has a separate limit: 30 requests/minute authenticated, 10 otherwise.
          sleep GitHub::API.credentials ? 2.1 : 6.1
          query = "repo:#{repository} is:#{type} #{date}:#{from}..#{Date.iso8601(to) - 1}"
          result = GitHub::API.open_rest("https://api.github.com/search/issues?" \
                                         "q=#{URI.encode_www_form_component(query)}&per_page=1")
          raise "Incomplete GitHub search for #{repository}: #{metric}" if result.fetch("incomplete_results")

          [metric, Integer(result.fetch("total_count").to_s, 10)]
        end.merge("github_fetched_at" => Time.now.utc.iso8601, "github_queries" => requests + 2,
                  "github_method" => "search baseline")
        @github_query_credit = budget - requests - 2
        cache.dirname.mkpath
        cache.atomic_write(JSON.generate(counts))
        counts
      end

      sig { params(repository: String).returns(T::Array[String]) }
      def repository_advisories(repository)
        cache = HOMEBREW_CACHE/"analytics/github/#{repository}/advisories.json"
        if cache.exist?
          cached = JSON.parse(cache.read)
          return cached.fetch("dates") if cached.fetch("fetched_at").start_with?(Time.now.utc.strftime("%F"))
        end

        raise "Advisory analytics require the GitHub API" if Homebrew::EnvConfig.no_github_api?

        endpoint = "https://api.github.com/repos/#{repository}/security-advisories?"
        url = "#{endpoint}state=published&per_page=100"
        dates = T.let([], T::Array[String])
        loop do
          advisories, headers = GitHub::API.open_rest(url, return_headers: true)
          dates.concat(advisories.map { |advisory| Date.iso8601(advisory.fetch("published_at")).iso8601 })
          next_url = String(headers)[/^link:.*?<([^>]+)>;\s*rel="next"/i, 1]
          break if next_url.nil?
          if next_url == url || (!next_url.start_with?(endpoint) &&
                                !next_url.match?(%r{\Ahttps://api\.github\.com/repositories/\d+/security-advisories\?}))
            raise "Invalid advisory pagination URL"
          end

          url = next_url
        end
        cache.dirname.mkpath
        cache.atomic_write(JSON.generate({ fetched_at: Time.now.utc.iso8601, dates: }))
        dates
      end

      sig { params(name: String).returns(T::Hash[String, T.anything]) }
      def archived_report(name)
        history = @history
        return {} unless history

        report = JSON.parse(Pathname(history).read).fetch(name, {})
        unless (0...Time.now.utc.year).cover?(report.fetch("through_year", 0))
          raise UsageError, "Historical aggregates must exclude the current and future years"
        end

        report
      end

      sig { params(row: T.anything, archived: T::Hash[String, T.anything]).returns(T::Boolean) }
      def historical_row?(row, archived)
        case row
        when Hash
          period = row.fetch("period") { row.fetch("date")[0, 4] }
          period != "current" && period.to_i <= archived.fetch("through_year", 0)
        else false
        end
      end

      sig { params(repositories: T::Hash[String, Pathname]).void }
      def generate_repositories(repositories: {
        "Homebrew/brew"          => HOMEBREW_REPOSITORY,
        "Homebrew/homebrew-core" => CoreTap.instance.path,
        "Homebrew/homebrew-cask" => CoreCaskTap.instance.path,
      })
        if (legacy = @legacy_homebrew)
          repositories = repositories.merge("Homebrew/legacy-homebrew" => Pathname(legacy).expand_path)
        end
        git_repositories = repositories.to_h do |name, path|
          [name, Utils::Analytics::Repository.new(path, name)]
        end
        today = Time.now.utc.to_date
        archived = archived_report("github")
        cumulative_metrics = %w[pull_requests_opened pull_requests_merged issues_opened security_advisories
                                security_disclosures]
        disclosures = blog_posts.reject { |post| post.key?("version") }
        data = {
          generated_at: Time.now.utc.iso8601,
          start_year:   2009,
          repositories: git_repositories.to_h do |repo, repository|
            puts "Generating repository analytics for #{repo}"
            historical_rows = case saved_repositories = archived["repositories"]
            when Hash
              Array(saved_repositories.dig(repo, "rows")).select { |row| historical_row?(row, archived) }
            else []
            end
            advisories = if repo == "Homebrew/legacy-homebrew" && historical_rows.any?
              []
            else
              repository_advisories(repo)
            end
            rows = repository.rows.map do |row|
              period = row.fetch("period").to_s
              next row if period == "current"
              if (saved = historical_rows.find { |entry| entry.fetch("period") == period })
                next saved
              end

              from = "#{period}-01-01"
              to = if period == today.year.to_s
                today.iso8601
              else
                "#{period.to_i + 1}-01-01"
              end
              activity = if repo == "Homebrew/legacy-homebrew" && historical_rows.any?
                { "pull_requests_opened" => 0, "issues_opened" => 0 }
              else
                github_activity(repo, from:, to:).except("pull_requests_merged")
              end
              activity.merge(
                row, "security_advisories" => advisories.count { |date| date >= from && date < to },
                "security_disclosures" => disclosures.count do |post|
                  repo == "Homebrew/brew" && post.fetch("date") >= from && post.fetch("date") < to
                end,
                "start_date" => from, "end_date" => to
              )
            end
            if (current = rows.find { |row| row["period"] == "current" })
              cumulative_metrics.each do |metric|
                current[metric] = rows.reject { |row| row["period"] == "current" }.sum { |row| row.fetch(metric, 0) }
              end
              current["start_date"] = "2009-01-01"
              current["end_date"] = today.iso8601
            end
            [repo, { source: "https://github.com/#{repo}", rows: }]
          end,
        }
        data[:security_disclosures] = disclosures
        data[:maintainer_history] = archived["maintainer_history"] if archived["maintainer_history"]
        combined = git_repositories.slice("Homebrew/brew", "Homebrew/homebrew-core", "Homebrew/homebrew-cask")
        first_years = combined.values.flat_map { |repository| repository.author_identities.keys }.uniq.sort
                              .each_with_object({}) do |period, first|
          combined.each_value do |repository|
            repository.author_identities.fetch(period, []).each { |identity| first[identity] ||= period }
          end
        end.values.tally
        data[:combined_contributors] = {
          repositories: combined.keys,
          rows:         ["current", *(2009..today.year).to_a.reverse.map(&:to_s)].map do |period|
            identities = combined.values.flat_map do |repository|
              if period == "current"
                repository.author_identities.values.flatten
              else
                repository.author_identities.fetch(period, [])
              end
            end
            { period:, contributors: identities.uniq.size,
              new_contributors: (period == "current") ? identities.uniq.size : first_years.fetch(period, 0) }
          end,
        }
        case saved = archived["combined_contributors"]
        when Hash
          data[:combined_contributors][:rows].map! do |row|
            next row if row[:period] == "current" || row[:period].to_i > archived.fetch("through_year", 0)

            saved.fetch("rows").find { |entry| entry.fetch("period") == row[:period] } || row
          end
        end
        Utils::Analytics.write_api("github", "history", data)
      end
    end
  end
end
