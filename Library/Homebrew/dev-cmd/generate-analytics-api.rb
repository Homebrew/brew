# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "fileutils"

module Homebrew
  module DevCmd
    class GenerateAnalyticsApi < AbstractCommand
      CATEGORIES = %w[
        build-error install install-on-request
        core-build-error core-install core-install-on-request
        cask-install core-cask-install os-version
        homebrew-devcmdrun-developer homebrew-os-arch-ci
        homebrew-prefixes homebrew-versions
        brew-command-run brew-command-run-options brew-test-bot-test
      ].freeze

      # TODO: add brew-command-run-options brew-test-bot-test to above when working.
      DAYS = %w[30 90 365].freeze
      MAX_RETRIES = 3

      cmd_args do
        description <<~EOS
          Generates analytics API data files for formulae.brew.sh.

          The generated files are written to the current directory.
        EOS

        named_args :none
      end

      sig { params(category_name: String, data_source: T.nilable(String)).returns(String) }
      def analytics_json_template(category_name, data_source: nil)
        data_source = "#{data_source}: true" if data_source

        <<~EOS
          ---
          layout: analytics_json
          category: #{category_name}
          #{data_source}
          ---
          {{ content }}
        EOS
      end

      sig { params(args: String).returns(String) }
      def run_formula_analytics(*args)
        puts "brew formula-analytics #{args.join(" ")}"

        retries = 0
        result = Utils.popen_read(HOMEBREW_BREW_FILE, "formula-analytics", *args, err: :err)

        while !$CHILD_STATUS.success? && retries < MAX_RETRIES
          # Give InfluxDB some more breathing room.
          sleep 4**(retries+2)

          retries += 1
          puts "Retrying #{args.join(" ")} (#{retries}/#{MAX_RETRIES})..."
          result = Utils.popen_read(HOMEBREW_BREW_FILE, "formula-analytics", *args, err: :err)
        end

        odie "`brew formula-analytics #{args.join(" ")}` failed: #{result}" unless $CHILD_STATUS.success?

        result
      end

      sig { override.void }
      def run
        safe_system HOMEBREW_BREW_FILE, "formula-analytics", "--setup"

        directories = ["_data/analytics", "api/analytics"]
        FileUtils.rm_rf directories
        FileUtils.mkdir_p directories

        root_dir = Pathname.pwd
        analytics_data_dir = root_dir/"_data/analytics"
        analytics_api_dir = root_dir/"api/analytics"

        analytics_output_queue = Queue.new

        CATEGORIES.each do |category|
          formula_analytics_args = []

          case category
          when "core-build-error"
            formula_analytics_args << "--all-core-formulae-json"
            formula_analytics_args << "--build-error"
            category_name = "build-error"
            data_source = "homebrew-core"
          when "core-install"
            formula_analytics_args << "--all-core-formulae-json"
            formula_analytics_args << "--install"
            category_name = "install"
            data_source = "homebrew-core"
          when "core-install-on-request"
            formula_analytics_args << "--all-core-formulae-json"
            formula_analytics_args << "--install-on-request"
            category_name = "install-on-request"
            data_source = "homebrew-core"
          when "core-cask-install"
            formula_analytics_args << "--all-core-formulae-json"
            formula_analytics_args << "--cask-install"
            category_name = "cask-install"
            data_source = "homebrew-cask"
          else
            formula_analytics_args << "--#{category}"
            category_name = category
          end

          path_suffix = File.join(category_name, data_source || "")
          analytics_data_path = analytics_data_dir/path_suffix
          analytics_api_path = analytics_api_dir/path_suffix

          FileUtils.mkdir_p analytics_data_path
          FileUtils.mkdir_p analytics_api_path

          # The `--json` and `--all-core-formulae-json` flags are mutually
          # exclusive, but we need to explicitly set `--json` sometimes,
          # so only set it if we've not already set
          # `--all-core-formulae-json`.
          formula_analytics_args << "--json" unless formula_analytics_args.include? "--all-core-formulae-json"

          DAYS.each do |days|
            next if days != "30" && category_name == "build-error" && !data_source.nil?

            analytics_output_queue << {
              formula_analytics_args: formula_analytics_args.dup,
              days:                   days,
              analytics_data_path:    analytics_data_path,
              analytics_api_path:     analytics_api_path,
              category_name:          category_name,
              data_source:            data_source,
            }
          end
        end

        workers = []
        4.times do
          workers << Thread.new do
            until analytics_output_queue.empty?
              analytics_output_type = begin
                analytics_output_queue.pop(true)
              rescue ThreadError
                break
              end

              days = analytics_output_type[:days]
              args = ["--days-ago=#{days}"]

              (analytics_output_type[:analytics_data_path]/"#{days}d.json").write \
                run_formula_analytics(*analytics_output_type[:formula_analytics_args], *args)

              data_source = analytics_output_type[:data_source]
              (analytics_output_type[:analytics_api_path]/"#{days}d.json").write \
                analytics_json_template(analytics_output_type[:category_name], data_source:)
            end
          end
        end
        workers.each(&:join)
      end
    end
  end
end
