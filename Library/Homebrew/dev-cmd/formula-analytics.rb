# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "fileutils"

module Homebrew
  module DevCmd
    class FormulaAnalytics < AbstractCommand
      cmd_args do
        usage_banner <<~EOS
          `formula-analytics`

          Query Homebrew's analytics.
        EOS
        flag   "--days-ago=",
               description: "Query from the specified days ago until the present. The default is 30 days."
        switch "--install",
               description: "Output the number of specifically requested installations or installation as " \
                            "dependencies of the formula. This is the default."
        switch "--cask-install",
               description: "Output the number of installations of casks."
        switch "--install-on-request",
               description: "Output the number of specifically requested installations of the formula."
        switch "--build-error",
               description: "Output the number of build errors for the formulae."
        switch "--os-version",
               description: "Output OS versions."
        switch "--homebrew-devcmdrun-developer",
               description: "Output devcmdrun/HOMEBREW_DEVELOPER."
        switch "--homebrew-os-arch-ci",
               description: "Output OS/Architecture/CI."
        switch "--homebrew-prefixes",
               description: "Output Homebrew prefixes."
        switch "--homebrew-versions",
               description: "Output Homebrew versions."
        switch "--brew-command-run",
               description: "Output `brew` commands run."
        switch "--brew-command-run-options",
               description: "Output `brew` commands run with options."
        switch "--brew-test-bot-test",
               description: "Output `brew test-bot` steps run."
        switch "--json",
               description: "Output JSON. This is required: plain text support has been removed."
        switch "--all-core-formulae-json",
               description: "Output a different JSON format containing the JSON data for all " \
                            "Homebrew/homebrew-core formulae."
        switch "--setup",
               description: "Install the necessary gems, require them and exit without running a query."
        conflicts "--install", "--cask-install", "--install-on-request", "--build-error", "--os-version",
                  "--homebrew-devcmdrun-developer", "--homebrew-os-arch-ci", "--homebrew-prefixes",
                  "--homebrew-versions", "--brew-command-run", "--brew-command-run-options", "--brew-test-bot-test"
        conflicts "--json", "--all-core-formulae-json", "--setup"
        named_args :none
      end

      FIRST_INFLUXDB_ANALYTICS_DATE = T.let(Date.new(2023, 03, 27).freeze, Date)

      sig { override.void }
      def run
        Homebrew.install_bundler_gems!(groups: ["formula_analytics"])

        setup_python
        influx_analytics(args)
      end

      sig { void }
      def setup_python
        formula_analytics_root = HOMEBREW_LIBRARY/"Homebrew/formula-analytics"
        vendor_python =  Pathname.new("~/.brew-formula-analytics/vendor/python").expand_path
        python_version = (formula_analytics_root/".python-version").read.chomp

        which_python = which("python#{python_version}", ORIGINAL_PATHS)
        odie <<~EOS if which_python.nil?
          Python #{python_version} is required. Try:
            brew install python@#{python_version}
        EOS

        venv_root = vendor_python/python_version
        vendor_python.children.reject { |path| path == venv_root }.each(&:rmtree) if vendor_python.exist?
        venv_python = venv_root/"bin/python"

        repo_requirements = HOMEBREW_LIBRARY/"Homebrew/formula-analytics/requirements.txt"
        venv_requirements = venv_root/"requirements.txt"
        if !venv_requirements.exist? || !FileUtils.identical?(repo_requirements, venv_requirements)
          safe_system which_python, "-I", "-m", "venv", "--clear", venv_root, out: :err
          safe_system venv_python, "-m", "pip", "install",
                      "--disable-pip-version-check",
                      "--require-hashes",
                      "--requirement", repo_requirements,
                      out: :err
          FileUtils.cp repo_requirements, venv_requirements
        end

        ENV["PATH"] = "#{venv_root}/bin:#{ENV.fetch("PATH")}"
        ENV["__PYVENV_LAUNCHER__"] = venv_python.to_s # support macOS framework Pythons

        require "pycall"
        PyCall.init(venv_python)
        require formula_analytics_root/"pycall-setup"
      end

      sig { params(args: Homebrew::DevCmd::FormulaAnalytics::Args).void }
      def influx_analytics(args)
        require "utils/analytics"
        require "json"

        return if args.setup?

        odie "HOMEBREW_NO_ANALYTICS is set!" if ENV["HOMEBREW_NO_ANALYTICS"]

        token = ENV.fetch("HOMEBREW_INFLUXDB_TOKEN", nil)
        odie "No InfluxDB credentials found in HOMEBREW_INFLUXDB_TOKEN!" unless token

        client = InfluxDBClient3.new(
          token:,
          host:     URI.parse(Utils::Analytics::INFLUX_HOST).host,
          org:      Utils::Analytics::INFLUX_ORG,
          database: Utils::Analytics::INFLUX_BUCKET,
        )

        max_days_ago = (Date.today - FIRST_INFLUXDB_ANALYTICS_DATE).to_s.to_i
        days_ago = (args.days_ago || 30).to_i
        if days_ago > max_days_ago
          opoo "Analytics started #{FIRST_INFLUXDB_ANALYTICS_DATE}. `--days-ago` set to maximum value."
          days_ago = max_days_ago
        end
        if days_ago > 365
          opoo "Analytics are only retained for 1 year, setting `--days-ago=365`."
          days_ago = 365
        end

        all_core_formulae_json = args.all_core_formulae_json?

        categories = []
        categories << :build_error if args.build_error?
        categories << :cask_install if args.cask_install?
        categories << :formula_install if args.install?
        categories << :formula_install_on_request if args.install_on_request?
        categories << :homebrew_devcmdrun_developer if args.homebrew_devcmdrun_developer?
        categories << :homebrew_os_arch_ci if args.homebrew_os_arch_ci?
        categories << :homebrew_prefixes if args.homebrew_prefixes?
        categories << :homebrew_versions if args.homebrew_versions?
        categories << :os_versions if args.os_version?
        categories << :command_run if args.brew_command_run?
        categories << :command_run_options if args.brew_command_run_options?
        categories << :test_bot_test if args.brew_test_bot_test?

        category_matching_buckets = [:build_error, :cask_install, :command_run, :test_bot_test]

        categories.each do |category|
          additional_where = all_core_formulae_json ? " AND tap_name ~ '^homebrew/(core|cask)$'" : ""
          bucket = if category_matching_buckets.include?(category)
            category
          elsif category == :command_run_options
            :command_run
          else
            :formula_install
          end

          case category
          when :homebrew_devcmdrun_developer
            dimension_key = "devcmdrun_developer"
            groups = [:devcmdrun, :developer]
          when :homebrew_os_arch_ci
            dimension_key = "os_arch_ci"
            groups = [:os, :arch, :ci]
          when :homebrew_prefixes
            dimension_key = "prefix"
            groups = [:prefix, :os, :arch]
          when :homebrew_versions
            dimension_key = "version"
            groups = [:version]
          when :os_versions
            dimension_key = :os_version
            groups = [:os_name_and_version]
          when :command_run
            dimension_key = "command_run"
            groups = [:command]
          when :command_run_options
            dimension_key = "command_run_options"
            groups = [:command, :options, :devcmdrun, :developer]
            additional_where += " AND ci = 'false'"
          when :test_bot_test
            dimension_key = "test_bot_test"
            groups = [:command, :passed, :arch, :os]
          when :cask_install
            dimension_key = :cask
            groups = [:package, :tap_name]
          else
            dimension_key = :formula
            additional_where += " AND on_request = 'true'" if category == :formula_install_on_request
            groups = [:package, :tap_name, :options]
          end

          sql_groups = groups.map { |e| "\"#{e}\"" }.join(",")
          query = <<~EOS
            SELECT #{sql_groups}, COUNT(*) AS "count" FROM "#{bucket}" WHERE time >= now() - INTERVAL '#{days_ago} day'#{additional_where} GROUP BY #{sql_groups}
          EOS
          batches = begin
            client.query(query:, language: "sql").to_batches
          rescue PyCall::PyError => e
            if e.message.include?("message: unauthenticated")
              odie "Could not authenticate with InfluxDB! Please check your HOMEBREW_INFLUXDB_TOKEN!"
            end
            raise
          end

          json = T.let({
            category:,
            total_items: 0,
            start_date:  Date.today - days_ago.to_i,
            end_date:    Date.today,
            total_count: 0,
            items:       [],
          }, T::Hash[Symbol, T.untyped])

          batches.each do |batch|
            batch.to_pylist.each do |record|
              dimension = case category
              when :homebrew_devcmdrun_developer
                "devcmdrun=#{record["devcmdrun"]} HOMEBREW_DEVELOPER=#{record["developer"]}"
              when :homebrew_os_arch_ci
                if record["ci"] == "true"
                  "#{record["os"]} #{record["arch"]} (CI)"
                else
                  "#{record["os"]} #{record["arch"]}"
                end
              when :homebrew_prefixes
                if record["prefix"] == "custom-prefix"
                  "#{record["prefix"]} (#{record["os"]} #{record["arch"]})"
                else
                  record["prefix"].to_s
                end
              when :os_versions
                format_os_version_dimension(record["os_name_and_version"])
              when :command_run_options
                options = record["options"].split

                # Cleanup bad data before TODO
                # Can delete this code after 18th July 2025.
                options.reject! { |option| option.match?(/^--with(out)?-/) }
                next if options.any? { |option| option.match?(/^TMPDIR=/) }

                "#{record["command"]} #{options.sort.join(" ")}"
              when :test_bot_test
                command_and_package, options = record["command"].split.partition { |arg| !arg.start_with?("-") }

                # Cleanup bad data before https://github.com/Homebrew/homebrew-test-bot/pull/1043
                # Can delete this code after 27th April 2025.
                next if %w[audit install linkage style test].exclude?(command_and_package.first)
                next if command_and_package.last.include?("/")
                next if options.include?("--tap=")
                next if options.include?("--only-dependencies")
                next if options.include?("--cached")

                command_and_options = (command_and_package + options.sort).join(" ")
                passed = (record["passed"] == "true") ? "PASSED" : "FAILED"

                "#{command_and_options} (#{record["os"]} #{record["arch"]}) (#{passed})"
              else
                record[groups.first.to_s]
              end
              next if dimension.blank?

              if (tap_name = record["tap_name"].presence) &&
                 ((tap_name != "homebrew/cask" && dimension_key == :cask) ||
                  (tap_name != "homebrew/core" && dimension_key == :formula))
                dimension = "#{tap_name}/#{dimension}"
              end

              if (all_core_formulae_json || category == :build_error) &&
                 (options = record["options"].presence)
                # homebrew/core formulae don't have non-HEAD options but they ended up in our analytics anyway.
                if all_core_formulae_json
                  options = options.split.include?("--HEAD") ? "--HEAD" : ""
                end
                dimension = "#{dimension} #{options}"
              end

              dimension = dimension.strip
              next if dimension.match?(/[<>]/)

              count = record["count"]

              json[:total_items] += 1
              json[:total_count] += count

              json[:items] << {
                number: nil,
                dimension_key => dimension,
                count:,
              }
            end
          end

          odie "No data returned" if json[:total_count].zero?

          # Combine identical values
          deduped_items = {}

          json[:items].each do |item|
            key = item[dimension_key]
            if deduped_items.key?(key)
              deduped_items[key][:count] += item[:count]
            else
              deduped_items[key] = item
            end
          end

          json[:items] = deduped_items.values

          if all_core_formulae_json
            core_formula_items = {}

            json[:items].each do |item|
              item.delete(:number)
              formula_name, = item[dimension_key].split.first
              next if formula_name.include?("/")

              core_formula_items[formula_name] ||= []
              core_formula_items[formula_name] << item
            end
            json.delete(:items)

            core_formula_items.each_value do |items|
              items.sort_by! { |item| -item[:count] }
              items.each do |item|
                item[:count] = format_count(item[:count])
              end
            end

            json[:formulae] = core_formula_items.sort_by { |name, _| name }.to_h
          else
            json[:items].sort_by! do |item|
              -item[:count]
            end

            json[:items].each_with_index do |item, index|
              item[:number] = index + 1

              percent = (item[:count].to_f / json[:total_count]) * 100
              item[:percent] = format_percent(percent)
              item[:count] = format_count(item[:count])
            end
          end

          puts JSON.pretty_generate json
        end
      end

      sig { params(count: Integer).returns(String) }
      def format_count(count)
        count.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
      end

      sig { params(percent: Float).returns(String) }
      def format_percent(percent)
        format("%<percent>.2f", percent:).gsub(/\.00$/, "")
      end

      sig { params(dimension: T.nilable(String)).returns(T.nilable(String)) }
      def format_os_version_dimension(dimension)
        return if dimension.blank?

        dimension = dimension.gsub(/^Intel ?/, "")
                             .gsub(/^macOS ?/, "")
                             .gsub(/ \(.+\)$/, "")
        case dimension
        when "10.11", /^10\.11\.?/ then "OS X El Capitan (10.11)"
        when "10.12", /^10\.12\.?/ then "macOS Sierra (10.12)"
        when "10.13", /^10\.13\.?/ then "macOS High Sierra (10.13)"
        when "10.14", /^10\.14\.?/ then "macOS Mojave (10.14)"
        when "10.15", /^10\.15\.?/ then "macOS Catalina (10.15)"
        when "10.16", /^11\.?/ then "macOS Big Sur (11)"
        when /^12\.?/ then "macOS Monterey (12)"
        when /^13\.?/ then "macOS Ventura (13)"
        when /^14\.?/ then "macOS Sonoma (14)"
        when /^15\.?/ then "macOS Sequoia (15)"
        when /Ubuntu(-Server)? (14|16|18|20|22)\.04/ then "Ubuntu #{Regexp.last_match(2)}.04 LTS"
        when /Ubuntu(-Server)? (\d+\.\d+).\d ?(LTS)?/
          "Ubuntu #{Regexp.last_match(2)} #{Regexp.last_match(3)}".strip
        when %r{Debian GNU/Linux (\d+)\.\d+} then "Debian #{Regexp.last_match(1)} #{Regexp.last_match(2)}"
        when /CentOS (\w+) (\d+)/ then "CentOS #{Regexp.last_match(1)} #{Regexp.last_match(2)}"
        when /Fedora Linux (\d+)[.\d]*/ then "Fedora Linux #{Regexp.last_match(1)}"
        when /KDE neon .*?([\d.]+)/ then "KDE neon #{Regexp.last_match(1)}"
        when /Amazon Linux (\d+)\.[.\d]*/ then "Amazon Linux #{Regexp.last_match(1)}"
        else dimension
        end
      end
    end
  end
end
