# typed: strict
# frozen_string_literal: true

require "context"
require "erb"
require "settings"
require "cacheable"
require "utils/output"

module Utils
  # Helper module for fetching and reporting analytics data.
  module Analytics
    INFLUX_BUCKET = "analytics"
    INFLUX_HOST = "https://analytics.brew.sh"
    INFLUX_ORG = "d81a3e6d582d485f"
    WSL_SUFFIX = " [WSL]"
    ENV_CONFIG_COMMANDS = %w[config fetch install reinstall update update-report upgrade].freeze

    extend Utils::Output::Mixin
    extend T::Generic
    extend Cacheable

    Cache = type_template { { fixed: T::Hash[Symbol, T.untyped] } }

    class << self
      include Context

      sig { params(category: String, name: String, data: T.anything, data_source: T.nilable(String)).void }
      def write_api(category, name, data, data_source: nil)
        suffix = File.join(category, data_source || "")
        Pathname("_data/analytics/#{suffix}").mkpath
        Pathname("api/analytics/#{suffix}").mkpath
        Pathname("_data/analytics/#{suffix}/#{name}.json").write(JSON.pretty_generate(data))
        Pathname("api/analytics/#{suffix}/#{name}.json").write(<<~EOS)
          ---
          layout: analytics_json
          category: #{category}
          #{"#{data_source}: true" if data_source}
          ---
          {{ content }}
        EOS
      end

      sig {
        params(measurement: Symbol,
               tags:        T::Hash[Symbol, T.any(T::Boolean, String)],
               fields:      T::Hash[Symbol, T.any(T::Boolean, String)]).void
      }
      def report_influx(measurement, tags, fields)
        return if not_this_run? || disabled?

        # Tags are always implicitly strings and must have low cardinality.
        tags_string = tags.map { |k, v| "#{k}=#{v.to_s.gsub(/[ ,=]/) { |char| "\\#{char}" }}" }
                          .join(",")

        # Fields need explicitly wrapped with quotes and can have high cardinality.
        fields_string = fields.compact
                              .map { |k, v| %Q(#{k}="#{v}") }
                              .join(",")

        args = [
          "--max-time", "3",
          "--header", "Content-Type: text/plain; charset=utf-8",
          "--header", "Accept: application/json",
          "--data-binary", "#{measurement},#{tags_string} #{fields_string} #{Time.now.to_i}"
        ]

        # Second precision is highest we can do and has the lowest performance cost.
        url = "#{INFLUX_HOST}/api/v2/write?bucket=#{INFLUX_BUCKET}&precision=s"
        deferred_curl(url, args)
      end

      sig { params(url: String, args: T::Array[String]).void }
      def deferred_curl(url, args)
        require "utils/curl"

        curl = Utils::Curl.curl_executable
        args = Utils::Curl.curl_args(*args, "--silent", "--output", File::NULL, show_error: false)
        if ENV["HOMEBREW_ANALYTICS_DEBUG"]
          puts "#{curl} #{args.join(" ")} \"#{url}\""
          puts Utils.safe_popen_read(curl, *args, url)
        else
          pid = spawn curl, *args, url, out: File::NULL, err: File::NULL
          Process.detach(pid)
        end
      end

      sig {
        params(measurement: Symbol, package_name: String, tap_name: String,
               on_request: T::Boolean, options: String).void
      }
      def report_package_event(measurement, package_name:, tap_name:, on_request: false, options: "")
        return if not_this_run? || disabled?

        # ensure options are removed (by `.compact` below) if empty
        options = nil if options.blank?

        # Tags must have low cardinality.
        tags = default_package_tags.merge(on_request:)

        # Fields can have high cardinality.
        fields = default_package_fields.merge(package: package_name, tap_name:, options:)
                                       .compact

        report_influx(measurement, tags, fields)
      end

      sig { params(exception: BuildError).void }
      def report_build_error(exception)
        return if not_this_run? || disabled?

        formula = exception.formula
        return unless formula

        tap = formula.tap
        return unless tap
        return unless tap.should_report_analytics?

        options = exception.options.to_a.compact.map(&:to_s).sort.uniq.join(" ")
        report_package_event(:build_error, package_name: formula.name, tap_name: tap.name, options:)
      end

      sig { params(command_instance: Homebrew::AbstractCommand).void }
      def report_command_run(command_instance)
        return if not_this_run? || disabled?

        command = command_instance.class.command_name

        options_array = command_instance.args.options_only.to_a.compact

        # Strip out any flag values to reduce cardinality and preserve privacy.
        options_array.map! { |option| option.sub(/=.*/m, "=") }

        # Strip out --with-* and --without-* options
        options_array.reject! { |option| option.match(/^--with(?:out)?-/) }

        options = options_array.sort.uniq.join(" ")

        # Tags must have low cardinality.
        tags = {
          command:,
          ci:        ENV["CI"].present?,
          devcmdrun: Homebrew::EnvConfig.devcmdrun?,
          developer: Homebrew::EnvConfig.developer?,
        }
        if ENV_CONFIG_COMMANDS.include?(command)
          variables = Homebrew::EnvConfig::ANALYTICS_VARIABLES
          env_config = variables.fetch(Random.rand(variables.length))
          tags[:env_config] = env_config.to_s
          tags[:env_config_state] = if Homebrew::EnvConfig.user_set_variable?(env_config)
            Homebrew::EnvConfig.non_default_variable?(env_config) ? "non_default" : "default"
          else
            "unset"
          end
        end

        # Fields can have high cardinality.
        fields = { options: }

        report_influx(:command_run, tags, fields)
      end

      sig { params(step_command_short: String, passed: T::Boolean).void }
      def report_test_bot_test(step_command_short, passed)
        return if not_this_run? || disabled?
        return if ENV["HOMEBREW_TEST_BOT_ANALYTICS"].blank?

        # Tags must have low cardinality.
        tags = {
          passed:,
          arch:   HOMEBREW_PHYSICAL_PROCESSOR,
          os:     HOMEBREW_SYSTEM,
        }

        # Strip out any flag values to reduce cardinality and preserve privacy.
        # Sort options to ensure consistent ordering and improve readability.
        command_and_package, options =
          step_command_short.split
                            .map { |arg| arg.sub(/=.*/, "=") }
                            .partition { |arg| !arg.start_with?("-") }
        command = (command_and_package + options.sort).join(" ")

        # Fields can have high cardinality.
        fields = { command: }

        report_influx(:test_bot_test, tags, fields)
      end

      sig { returns(T::Boolean) }
      def influx_message_displayed?
        config_true?(:influxanalyticsmessage)
      end

      sig { returns(T::Boolean) }
      def messages_displayed?
        return false unless config_true?(:analyticsmessage)
        return false unless config_true?(:caskanalyticsmessage)

        influx_message_displayed?
      end

      sig { returns(T::Boolean) }
      def disabled?
        return true if Homebrew::EnvConfig.no_analytics?

        config_true?(:analyticsdisabled)
      end

      sig { returns(T::Boolean) }
      def not_this_run?
        ENV["HOMEBREW_NO_ANALYTICS_THIS_RUN"].present?
      end

      sig { returns(T::Boolean) }
      def no_message_output?
        # Used by Homebrew/install
        ENV["HOMEBREW_NO_ANALYTICS_MESSAGE_OUTPUT"].present?
      end

      sig { void }
      def messages_displayed!
        Homebrew::Settings.write :analyticsmessage, true
        Homebrew::Settings.write :caskanalyticsmessage, true
        Homebrew::Settings.write :influxanalyticsmessage, true
      end

      sig { void }
      def enable!
        Homebrew::Settings.write :analyticsdisabled, false
        delete_uuid!
        messages_displayed!
      end

      sig { void }
      def disable!
        Homebrew::Settings.write :analyticsdisabled, true
        delete_uuid!
      end

      sig { void }
      def delete_uuid!
        Homebrew::Settings.delete :analyticsuuid
      end

      sig { params(args: Homebrew::Cmd::Info::Args, filter: T.nilable(String)).void }
      def output(args:, filter: nil)
        require "api"

        days = args.days || "30"
        category = args.category || "install"
        begin
          json = Homebrew::API::Analytics.fetch category, days
        rescue ArgumentError
          # Ignore failed API requests
          return
        end
        return if json.blank? || json["items"].blank?

        os_version = category == "os-version"
        cask_install = category == "cask-install"
        results = {}
        json["items"].each do |item|
          key = if os_version
            item["os_version"]
          elsif cask_install
            item["cask"]
          else
            item["formula"]
          end
          next if filter.present? && key != filter && !key.start_with?("#{filter} ")

          results[key] = item["count"].tr(",", "").to_i
        end

        if filter.present? && results.blank?
          onoe "No results matching `#{filter}` found!"
          return
        end

        table_output(category, days, results, os_version:, cask_install:)
      end

      sig { params(analytics: T::Hash[String, T.untyped], args: Homebrew::Cmd::Info::Args).void }
      def output_analytics(analytics, args:)
        full_analytics = args.analytics? || verbose?

        ohai "Analytics"
        analytics.each do |category, value|
          category = category.tr("_", "-")
          summaries = []

          value.each do |days, results|
            days = days.to_i
            if full_analytics
              next if args.days.present? && args.days&.to_i != days
              next if args.category.present? && args.category != category

              table_output(category, days.to_s, results)
            else
              total_count = results.values.sum
              summaries << "#{Formatter.number_readable(total_count)} (#{days} days)"
            end
          end

          puts "#{category}: #{summaries.join(", ")}" unless full_analytics
        end
      end

      # This flag is hidden because it is not intended for general use.
      # It relies on screen scraping some GitHub HTML that's not available as an API.
      # This seems very likely to break in the future.
      # That said, it's the only way to get the data we want right now.
      sig { params(formula: Formula, analytics: T::Hash[String, T.untyped], args: Homebrew::Cmd::Info::Args).void }
      def output_github_packages_downloads(formula, analytics, args:)
        return unless args.github_packages_downloads?
        return unless formula.core_formula?

        downloads = GitHubPackages.downloads(formula.name)
        unless downloads
          opoo "Failed to fetch GitHub Packages downloads for: #{formula.name}"
          return
        end

        puts "GitHub Packages downloads (since Bintray migration): #{format_count(downloads.all_time)}"
        puts "GitHub Packages downloads (30 days): #{format_count(downloads.last_30_days)}"
        puts "Download dates: #{downloads.start_date} to #{downloads.end_date}; fetched #{downloads.fetched_at}"

        install_count = analytics.dig("install", "30d")&.values&.sum
        return unless install_count&.positive?

        puts "Downloads / analytics install events (30 days): " \
             "#{format("%.2f", downloads.last_30_days.to_f / install_count)}x " \
             "(#{format_count(install_count)} events)"
      end

      sig { params(formula: Formula, args: Homebrew::Cmd::Info::Args).void }
      def formula_output(formula, args:)
        return if Homebrew::EnvConfig.no_analytics? || Homebrew::EnvConfig.no_github_api?

        require "api"

        return unless Homebrew::API.formula_name? formula.name

        analytics = Homebrew::API::Analytics.formula_analytics formula.name
        return if analytics.blank?

        output_analytics(analytics, args:)
        output_github_packages_downloads(formula, analytics, args:)
      rescue ArgumentError
        # Ignore failed API requests
        nil
      end

      sig { params(cask: Cask::Cask, args: Homebrew::Cmd::Info::Args).void }
      def cask_output(cask, args:)
        return if Homebrew::EnvConfig.no_analytics? || Homebrew::EnvConfig.no_github_api?

        require "api"

        return unless Homebrew::API.cask_token?(cask.token)

        analytics = Homebrew::API::Analytics.cask_analytics cask.token
        return if analytics.blank?

        output_analytics(analytics, args:)
      rescue ArgumentError
        # Ignore failed API requests
        nil
      end

      sig { params(value: String, wsl: T::Boolean).returns(String) }
      def with_wsl_suffix_if_needed(value, wsl: OS.wsl?)
        return value if !wsl || value.end_with?(WSL_SUFFIX)

        "#{value}#{WSL_SUFFIX}"
      end

      sig { returns(T::Hash[Symbol, T.any(T::Boolean, String)]) }
      def default_package_tags
        cache[:default_package_tags] ||= begin
          # Only display default prefixes to reduce cardinality and improve privacy
          prefix = Homebrew.default_prefix? ? HOMEBREW_PREFIX.to_s : "custom-prefix"

          # Tags are always strings and must have low cardinality.
          {
            ci:             ENV["CI"].present?,
            prefix:,
            default_prefix: Homebrew.default_prefix?,
            developer:      Homebrew::EnvConfig.developer?,
            devcmdrun:      Homebrew::EnvConfig.devcmdrun?,
            arch:           HOMEBREW_PHYSICAL_PROCESSOR,
            cpu_family:     Hardware::CPU.family.to_s,
            os:             with_wsl_suffix_if_needed(HOMEBREW_SYSTEM),
          }
        end
      end

      # remove os_version starting with " or number
      # remove macOS patch release
      sig { returns(T::Hash[Symbol, String]) }
      def default_package_fields
        cache[:default_package_fields] ||= begin
          version = if (numeric_version = HOMEBREW_VERSION[/^[\d.]+/])
            suffix = "-dev" if HOMEBREW_VERSION.include?("-")
            numeric_version + suffix.to_s
          else
            ">=4.1.22"
          end

          # Only include OS versions with an actual name.
          os_name_and_version = if (os_version = OS_VERSION.presence) && os_version.downcase.match?(/^[a-z]/)
            with_wsl_suffix_if_needed(os_version)
          end

          {
            version:,
            os_name_and_version:,
          }
        end
      end

      sig {
        params(
          category: String, days: String, results: T::Hash[String, Integer], os_version: T::Boolean,
          cask_install: T::Boolean, name_header: T.nilable(String)
        ).void
      }
      def table_output(category, days, results, os_version: false, cask_install: false, name_header: nil)
        oh1 "#{category} (#{days} days)"
        total_count = results.values.sum
        formatted_total_count = format_count(total_count)
        formatted_total_percent = format_percent(100)

        index_header = "Index"
        count_header = "Count"
        percent_header = "Percent"
        name_with_options_header = if name_header
          name_header
        elsif os_version
          "macOS Version"
        elsif cask_install
          "Token"
        else
          "Name (with options)"
        end

        total_index_footer = "Total"
        max_index_width = results.length.to_s.length
        index_width = [
          index_header.length,
          total_index_footer.length,
          max_index_width,
        ].max
        count_width = [
          count_header.length,
          formatted_total_count.length,
        ].max
        percent_width = [
          percent_header.length,
          formatted_total_percent.length,
        ].max
        name_with_options_width = Tty.width -
                                  index_width -
                                  count_width -
                                  percent_width -
                                  10 # spacing and lines

        formatted_index_header =
          format "%#{index_width}s", index_header
        formatted_name_with_options_header =
          format "%-#{name_with_options_width}s",
                 name_with_options_header[0..(name_with_options_width-1)]
        formatted_count_header =
          format "%#{count_width}s", count_header
        formatted_percent_header =
          format "%#{percent_width}s", percent_header
        puts "#{formatted_index_header} | #{formatted_name_with_options_header} | " \
             "#{formatted_count_header} |  #{formatted_percent_header}"

        columns_line = "#{"-"*index_width}:|-#{"-"*name_with_options_width}-|-" \
                       "#{"-"*count_width}:|-#{"-"*percent_width}:"
        puts columns_line

        index = 0
        results.each do |name_with_options, count|
          index += 1
          formatted_index = format "%0#{max_index_width}d", index
          formatted_index = format "%-#{index_width}s", formatted_index
          formatted_name_with_options =
            format "%-#{name_with_options_width}s",
                   name_with_options[0..(name_with_options_width-1)]
          formatted_count = format "%#{count_width}s", format_count(count)
          formatted_percent = if total_count.zero?
            format "%#{percent_width}s", format_percent(0)
          else
            format "%#{percent_width}s",
                   format_percent((count.to_i * 100) / total_count.to_f)
          end
          puts "#{formatted_index} | #{formatted_name_with_options} | " \
               "#{formatted_count} | #{formatted_percent}%"
          next if index > 10
        end
        return if results.length <= 1

        formatted_total_footer =
          format "%-#{index_width}s", total_index_footer
        formatted_blank_footer =
          format "%-#{name_with_options_width}s", ""
        formatted_total_count_footer =
          format "%#{count_width}s", formatted_total_count
        formatted_total_percent_footer =
          format "%#{percent_width}s", formatted_total_percent
        puts "#{formatted_total_footer} | #{formatted_blank_footer} | " \
             "#{formatted_total_count_footer} | #{formatted_total_percent_footer}%"
      end

      sig { params(key: Symbol).returns(T::Boolean) }
      def config_true?(key)
        Homebrew::Settings.read(key) == "true"
      end

      sig { params(count: Integer).returns(String) }
      def format_count(count)
        count.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
      end

      sig { params(percent: T.any(Integer, Float)).returns(String) }
      def format_percent(percent)
        format("%<percent>.2f", percent:)
      end
    end
  end
end
