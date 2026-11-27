# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "api/env"
require "tap"
require "cask/ci/runner_matrix"

module Homebrew
  module DevCmd
    class GenerateCaskCiMatrix < AbstractCommand
      cmd_args do
        description <<~EOS
          Generate a GitHub Actions matrix for a given pull request URL or list of cask names.
          For internal use in Homebrew taps.
        EOS
        switch "--url",
               description: "Treat named argument as a pull request URL."
        switch "--cask", "--casks",
               description: "Treat all named arguments as cask tokens."
        flag   "--testing-casks=",
               description: "Use these detected casks instead of comparing Git revisions."
        comma_array "--added-casks=",
                    description: "Run new cask checks for these detected additions."
        switch "--skip-install",
               description: "Skip installing casks."
        switch "--new",
               description: "Run new cask checks."
        switch "--syntax-only",
               description: "Only run syntax checks."

        conflicts "--url", "--cask"
        conflicts "--testing-casks", "--cask", "--syntax-only"
        conflicts "--syntax-only", "--skip-install"
        conflicts "--syntax-only", "--new"

        named_args [:cask, :url], min: 0

        hide_from_man_page!
      end

      sig { override.void }
      def run
        pr_url = args.named if args.url?

        repository = ENV.fetch("GITHUB_REPOSITORY", nil)
        raise UsageError, "The `$GITHUB_REPOSITORY` environment variable must be set." if repository.blank?

        tap = Tap.fetch(repository)

        if !args.syntax_only? && !args.testing_casks && !args.casks? && !args.url?
          raise UsageError, "Specify `--testing-casks`, `--cask` or `--url`."
        end
        if (args.casks? || args.url?) && args.named.empty?
          raise UsageError, "Please provide a `--cask` or `--url` argument."
        end
        raise UsageError, "Only one `--url` can be specified." if pr_url&.count&.> 1

        labels = Cask::CI::RunnerMatrix.labels(pr_url&.first)
        cask_jobs = if args.syntax_only? || labels.include?("ci-syntax-only")
          []
        else
          Homebrew::API.with_no_api_env do
            if (testing_casks = args.testing_casks)
              cask_names = testing_casks.split(/[,\s]+/).reject(&:empty?)
              added_casks = args.added_casks.to_a
            else
              require "test_bot/packages_detect"

              added_casks, modified_casks, =
                TestBot::PackagesDetect.changed_packages(tap, "origin...HEAD", check_cask_paths: true).fetch(:cask)
              cask_names = if args.casks?
                args.named
              else
                added_casks | modified_casks
              end
            end
            Cask::CI::RunnerMatrix.generate(tap, cask_names, added_casks:, labels:,
                                            skip_install: args.skip_install?, new_cask: args.new?)
          end
        end

        # Older workflows get both syntax and cask jobs from the `matrix` output.
        runner = Cask::CI::RunnerMatrix.random_runner.fetch(:name)
        syntax_job = {
          name:   "tap_syntax (#{runner})",
          tap:    tap.name,
          runner:,
          stable: false,
        }
        syntax_job[:skip_audit] = true if cask_jobs.any?
        matrix = [
          syntax_job,
          syntax_job.merge(name: "tap_syntax (stable) (#{runner})", stable: true, skip_audit: true),
          *cask_jobs,
        ]

        Cask::CI::RunnerMatrix.check_size!(matrix.size)

        puts JSON.pretty_generate(matrix)
        github_output = ENV.fetch("GITHUB_OUTPUT", nil)
        return unless github_output

        File.open(github_output, "a") do |f|
          f.puts "runners=#{JSON.generate(cask_jobs)}"
          f.puts "matrix=#{JSON.generate(matrix)}"
        end
      end
    end
  end
end
