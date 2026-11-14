# typed: strict
# frozen_string_literal: true

require "system_command"

module Utils
  module Analytics
    # Query and format the analytics stored in InfluxDB.
    class Influx
      include Utils::Output::Mixin

      FIRST_INFLUXDB_ANALYTICS_DATE = Date.new(2023, 03, 27).freeze
      STANDARD_PREFIXES = %w[/opt/homebrew /usr/local /home/linuxbrew/.linuxbrew].freeze

      class CategoryDimensions < T::Struct
        const :bucket, Symbol
        const :dimension_key, T.any(String, Symbol)
        const :groups, T::Array[Symbol]
      end

      DEFAULT_CATEGORY_DIMENSIONS = CategoryDimensions.new(
        bucket: :formula_install, dimension_key: :formula, groups: [:package, :tap_name, :options],
      ).freeze
      CATEGORY_DIMENSIONS = T.let({
        homebrew_devcmdrun_developer: CategoryDimensions.new(
          bucket: :formula_install, dimension_key: "devcmdrun_developer", groups: [:devcmdrun, :developer],
        ),
        homebrew_env_config:          CategoryDimensions.new(
          bucket: :command_run, dimension_key: "env_config", groups: [:env_config, :env_config_state],
        ),
        homebrew_os_arch_ci:          CategoryDimensions.new(
          bucket: :formula_install, dimension_key: "os_arch_ci", groups: [:os, :arch, :ci],
        ),
        homebrew_prefixes:            CategoryDimensions.new(
          bucket: :formula_install, dimension_key: "prefix", groups: [:prefix, :os, :arch],
        ),
        homebrew_versions:            CategoryDimensions.new(
          bucket: :formula_install, dimension_key: "version", groups: [:version],
        ),
        os_versions:                  CategoryDimensions.new(
          bucket: :formula_install, dimension_key: :os_version, groups: [:os_name_and_version],
        ),
        command_run:                  CategoryDimensions.new(
          bucket: :command_run, dimension_key: "command_run", groups: [:command],
        ),
        command_run_options:          CategoryDimensions.new(
          bucket:        :command_run,
          dimension_key: "command_run_options",
          groups:        [:command, :options, :devcmdrun, :developer],
        ),
        test_bot_test:                CategoryDimensions.new(
          bucket: :test_bot_test, dimension_key: "test_bot_test", groups: [:command, :passed, :arch, :os],
        ),
        cask_install:                 CategoryDimensions.new(
          bucket: :cask_install, dimension_key: :cask, groups: [:package, :tap_name],
        ),
        build_error:                  CategoryDimensions.new(
          bucket: :build_error, dimension_key: :formula, groups: [:package, :tap_name, :options],
        ),
      }.freeze, T::Hash[Symbol, CategoryDimensions])

      sig { void }
      def setup_python
        uv = which("uv", ORIGINAL_PATHS)
        odie <<~EOS if uv.nil?
          `uv` is required. Try:
            brew install uv
        EOS

        vendor_python = venv_root.dirname
        vendor_python.children.reject { |path| path == venv_root }.each(&:rmtree) if vendor_python.exist?

        with_env(UV_PROJECT_ENVIRONMENT: venv_root.to_s) do
          SystemCommand.safe_system uv, "sync", "--frozen", "--project", formula_analytics_root, out: :err
        end
      end

      sig { returns(Pathname) }
      def formula_analytics_root
        HOMEBREW_LIBRARY/"Homebrew/formula-analytics"
      end

      sig { returns(Pathname) }
      def influxdb_query_script
        formula_analytics_root/"influxdb-query.py"
      end

      sig { returns(Pathname) }
      def venv_root
        python_version = (formula_analytics_root/".python-version").read.chomp
        Pathname.new("~/.brew-formula-analytics/vendor/python").expand_path/python_version
      end

      sig { returns(Pathname) }
      def venv_python
        venv_root/"bin/python"
      end

      sig { params(query: String, _block: T.proc.params(record: T::Hash[String, T.untyped]).void).void }
      def each_influx_record(query, &_block)
        require "json"
        require "tempfile"
        require "utils/analytics"
        require "utils/popen"

        request = {
          host:     URI.parse(Utils::Analytics::INFLUX_HOST).host,
          org:      Utils::Analytics::INFLUX_ORG,
          database: Utils::Analytics::INFLUX_BUCKET,
          query:,
        }.to_json

        Tempfile.create("influxdb-query-stderr") do |stderr_file|
          Utils.popen([venv_python.to_s, influxdb_query_script.to_s], "r+b", { err: stderr_file.path }) do |pipe|
            pipe.write request
            pipe.close_write
            pipe.each_line { |line| yield JSON.parse(line) }
          end

          next if $CHILD_STATUS.success?

          stderr = stderr_file.read
          if stderr.include?("unauthenticated")
            odie "Could not authenticate with InfluxDB! Please check your `$HOMEBREW_INFLUXDB_TOKEN`!"
          end
          odie "InfluxDB query failed:\n#{stderr}"
        end
      end

      sig {
        params(categories: T::Array[Symbol], days_ago: Integer,
               all_core_formulae_json: T::Boolean).returns(T::Array[T::Hash[Symbol, T.untyped]])
      }
      def query(categories:, days_ago: 30, all_core_formulae_json: false)
        require "utils/analytics"
        require "json"

        odie "`$HOMEBREW_NO_ANALYTICS` is set!" if ENV["HOMEBREW_NO_ANALYTICS"]

        odie "No InfluxDB credentials found in `$HOMEBREW_INFLUXDB_TOKEN`!" unless ENV["HOMEBREW_INFLUXDB_TOKEN"]

        max_days_ago = (Date.today - FIRST_INFLUXDB_ANALYTICS_DATE).to_s.to_i
        if days_ago > max_days_ago
          opoo "Analytics started #{FIRST_INFLUXDB_ANALYTICS_DATE}. `--days-ago` set to maximum value."
          days_ago = max_days_ago
        end
        if days_ago > 365
          opoo "Analytics are only retained for 1 year, setting `--days-ago=365`."
          days_ago = 365
        end

        categories.map do |category|
          additional_where = all_core_formulae_json ? " AND tap_name ~ '^homebrew/'" : ""
          dimensions = CATEGORY_DIMENSIONS.fetch(category, DEFAULT_CATEGORY_DIMENSIONS)
          dimension_key = dimensions.dimension_key
          # Events predating the user-set-aware `env_config_state` tag
          # counted brew's own exports as configuration, so drop them.
          additional_where += " AND env_config_state IS NOT NULL" if category == :homebrew_env_config
          additional_where += " AND on_request = 'true'" if category == :formula_install_on_request

          package_renames = self.package_renames(dimension_key)

          sql_groups = dimensions.groups.map { |e| "\"#{e}\"" }.join(",")
          query = <<~EOS
            SELECT #{sql_groups}, COUNT(*) AS "count" FROM "#{dimensions.bucket}" WHERE time >= now() - INTERVAL '#{days_ago} day'#{additional_where} GROUP BY #{sql_groups}
          EOS

          json = T.let({
            category:,
            total_items: 0,
            start_date:  Date.today - days_ago.to_i,
            end_date:    Date.today,
            total_count: 0,
            items:       [],
          }, T::Hash[Symbol, T.untyped])

          each_influx_record(query) do |record|
            if category == :homebrew_env_config
              state = record["env_config_state"]
              env_config_name = record["env_config"].to_s
              # Drop malformed events from non-standard clients and events
              # for variables Homebrew no longer supports.
              next if %w[unset default non_default].exclude?(state)
              next unless Homebrew::EnvConfig::ENVS.key?(env_config_name.to_sym)

              count = record["count"]
              json[:total_count] += count
              json[:items] << {
                number: nil,
                dimension_key => env_config_name,
                count:,
                non_default_count: (state == "non_default") ? count : 0,
                set_default_count: (state == "default") ? count : 0,
                unset_count:       (state == "unset") ? count : 0,
              }
              next
            end

            dimension = case category
            when :homebrew_devcmdrun_developer
              "devcmdrun=#{record["devcmdrun"]} HOMEBREW_DEVELOPER=#{record["developer"]}"
            when :homebrew_os_arch_ci
              "#{record["os"]} #{record["arch"]}#{" (CI)" if record["ci"] == "true"}"
            when :homebrew_prefixes
              prefix = record["prefix"].to_s
              if STANDARD_PREFIXES.none? { |std| std.casecmp?(prefix) }
                "custom-prefix (#{record["os"]} #{record["arch"]})"
              else
                prefix
              end
            when :os_versions
              format_os_version_dimension(record["os_name_and_version"])
            when :command_run_options
              "#{record["command"]} #{record["options"].to_s.split.sort.join(" ")}"
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
              record[dimensions.groups.first.to_s]
            end
            next if dimension.blank?

            if [:formula, :cask].include?(dimension_key)
              tap_name = record["tap_name"].presence
              dimension = "#{tap_name}/#{dimension}" if tap_name
              seen = Set.new
              while (new_name = package_renames[dimension]) && seen.add?(dimension)
                dimension = new_name
              end

              core_tap_name = (dimension_key == :cask) ? "homebrew/cask" : "homebrew/core"
              next if all_core_formulae_json && !dimension.start_with?("#{core_tap_name}/")

              dimension = dimension.delete_prefix("#{core_tap_name}/")
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

            json[:total_count] += count

            json[:items] << {
              number: nil,
              dimension_key => dimension,
              count:,
            }
          end

          odie "No data returned" if json[:total_count].zero?

          # Combine identical values
          deduped_items = {}

          json[:items].each do |item|
            key = item[dimension_key]
            if deduped_items.key?(key)
              deduped_items[key][:count] += item[:count]
              if category == :homebrew_env_config
                deduped_items[key][:non_default_count] += item[:non_default_count]
                deduped_items[key][:set_default_count] += item[:set_default_count]
                deduped_items[key][:unset_count] += item[:unset_count]
              end
            else
              deduped_items[key] = item
            end
          end

          json[:items] = deduped_items.values
          json[:total_items] = json[:items].length

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
                item[:count] = Utils::Analytics.format_count(item[:count])
              end
            end

            json[:formulae] = core_formula_items.sort_by { |name, _| name }.to_h
          else
            json[:items].sort_by! do |item|
              if category == :homebrew_env_config
                -item[:non_default_count].to_f / item[:count]
              else
                -item[:count]
              end
            end

            json[:items].each_with_index do |item, index|
              item[:number] = index + 1

              percent = if category == :homebrew_env_config
                (item[:non_default_count].to_f / item[:count]) * 100
              else
                (item[:count].to_f / json[:total_count]) * 100
              end
              item[:percent] = Utils::Analytics.format_percent(percent).delete_suffix(".00")
              item[:count] = Utils::Analytics.format_count(item[:count])
              next if category != :homebrew_env_config

              item[:non_default_count] = Utils::Analytics.format_count(item[:non_default_count])
              item[:set_default_count] = Utils::Analytics.format_count(item[:set_default_count])
              item[:unset_count] = Utils::Analytics.format_count(item[:unset_count])
              item[:default_value] = Homebrew::EnvConfig.default_description(item[dimension_key].to_sym)
            end
          end

          json
        end
      end

      sig { params(dimension_key: T.any(String, Symbol)).returns(T::Hash[String, String]) }
      def package_renames(dimension_key)
        return {} unless [:formula, :cask].include?(dimension_key)

        require "tap"

        package_renames = {}
        Tap.all.select(&:official?).each do |tap|
          ((dimension_key == :cask) ? tap.cask_renames : tap.formula_renames).each do |old_name, new_name|
            package_renames["#{tap.name}/#{old_name}"] = "#{tap.name}/#{new_name}"
          end
          tap.tap_migrations.each do |old_name, new_name|
            package_renames["#{tap.name}/#{old_name}"] = if Utils.full_name?(new_name)
              new_name
            else
              "#{new_name}/#{old_name}"
            end
          end
        end
        package_renames
      end

      sig { params(dimension: T.nilable(String)).returns(T.nilable(String)) }
      def format_os_version_dimension(dimension)
        return if dimension.blank?

        require "macos_version"
        require "utils/analytics"

        wsl = dimension.end_with?(Utils::Analytics::WSL_SUFFIX)
        dimension = dimension.delete_suffix(Utils::Analytics::WSL_SUFFIX)
        dimension = dimension.gsub(/^Intel ?/, "")
                             .gsub(/^macOS ?/, "")
                             .gsub(/ \(.+\)$/, "")

        begin
          macos_version = ::MacOSVersion.new(dimension)
          release_version = macos_version.release_version
          os_name = (macos_version < "10.12") ? "OS X" : "macOS"
          if (release_name = macos_version.release_name)
            return "#{os_name} #{release_name} (#{release_version})"
          end

          return "#{os_name} #{release_version}"
        rescue MacOSVersion::Error
          nil
        end

        formatted_dimension = case dimension
        when /Ubuntu(-Server)? (14|16|18|20|22|24)\.04/ then "Ubuntu #{Regexp.last_match(2)}.04 LTS"
        when /Ubuntu(-Server)? (\d+\.\d+).\d ?(LTS)?/
          "Ubuntu #{Regexp.last_match(2)} #{Regexp.last_match(3)}".strip
        when %r{Debian GNU/Linux (\d+)} then "Debian #{Regexp.last_match(1)}"
        when /CentOS (\w+) (\d+)/ then "CentOS #{Regexp.last_match(1)} #{Regexp.last_match(2)}"
        when /Fedora Linux (\d+)[.\d]*/ then "Fedora Linux #{Regexp.last_match(1)}"
        when /KDE neon .*?([\d.]+)/ then "KDE neon #{Regexp.last_match(1)}"
        when /Amazon Linux (\d+)\.[.\d]*/ then "Amazon Linux #{Regexp.last_match(1)}"
        when /^Armbian\S*(?: OS)? (\d+)\.0?(\d+)\S*(?: (\w+))?/
          "Armbian #{Regexp.last_match(1)}.#{Regexp.last_match(2)} #{Regexp.last_match(3)&.downcase}".strip
        when /Fedora Linux Rawhide[.\dn]*/ then "Fedora Linux Rawhide"
        when /Red Hat Enterprise Linux CoreOS (\d+\.\d+)[-.\d]*/
          "Red Hat Enterprise Linux CoreOS #{Regexp.last_match(1)}"
        when /([A-Za-z ]+)\s+(\d+)\.\d{8}[.\d]*/ then "#{Regexp.last_match(1)} #{Regexp.last_match(2)}"
        else dimension
        end

        Utils::Analytics.with_wsl_suffix_if_needed(formatted_dimension, wsl:)
      end
    end
  end
end
