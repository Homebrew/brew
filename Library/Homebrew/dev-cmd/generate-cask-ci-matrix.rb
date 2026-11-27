# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "api/env"
require "cask/ci/runner_matrix"
require "tap"
require "utils/github/api"
require "cli/parser"
require "system_command"

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
        switch "--skip-install",
               description: "Skip installing casks."
        switch "--new",
               description: "Run new cask checks."
        switch "--syntax-only",
               description: "Only run syntax checks."

        conflicts "--url", "--cask"
        conflicts "--syntax-only", "--skip-install"
        conflicts "--syntax-only", "--new"

        named_args [:cask, :url], min: 0

        hide_from_man_page!
      end

      sig { override.void }
      def run
        skip_install = args.skip_install?
        new_cask = args.new?
        casks = args.named if args.casks?
        pr_url = args.named if args.url?
        syntax_only = args.syntax_only?

        repository = ENV.fetch("GITHUB_REPOSITORY", nil)
        raise UsageError, "The `$GITHUB_REPOSITORY` environment variable must be set." if repository.blank?

        tap = T.let(Tap.fetch(repository), Tap)

        unless syntax_only
          raise UsageError, "Either `--cask` or `--url` must be specified." if !args.casks? && !args.url?
          raise UsageError, "Please provide a `--cask` or `--url` argument." if casks.blank? && pr_url.blank?
        end
        raise UsageError, "Only one `--url` can be specified." if pr_url&.count&.> 1

        labels = Cask::CI::RunnerMatrix.labels(pr_url&.first)

        runner = Cask::CI::RunnerMatrix.random_runner.fetch(:name)
        syntax_job = {
          name:   "tap_syntax",
          tap:    tap.name,
          runner:,
          stable: false,
        }
        stable_syntax_job = syntax_job.merge(name: "tap_syntax (stable)", stable: true, skip_audit: true)

        matrix = [syntax_job, stable_syntax_job]

        if !syntax_only && labels.exclude?("ci-syntax-only")
          cask_jobs = if casks&.any?
            generate_matrix(tap, labels:, cask_names: casks, skip_install:, new_cask:)
          else
            generate_matrix(tap, labels:, skip_install:, new_cask:)
          end

          if cask_jobs.any?
            # If casks were changed, skip `audit` for whole tap.
            syntax_job[:skip_audit] = true

            # The syntax job only runs `style` at this point, which should work on Linux.
            # Running on macOS is currently faster though, since `homebrew/cask` and
            # `homebrew/core` are already tapped on macOS CI machines.
            # syntax_job[:runner] = "ubuntu-latest"
          end

          matrix += cask_jobs
        end

        Cask::CI::RunnerMatrix.check_size!(matrix.size)

        [syntax_job, stable_syntax_job].each do |job|
          job[:name] += " (#{job[:runner]})"
        end

        puts JSON.pretty_generate(matrix)
        github_output = ENV.fetch("GITHUB_OUTPUT", nil)
        return unless github_output

        File.open(ENV.fetch("GITHUB_OUTPUT"), "a") do |f|
          f.puts "runners=#{JSON.generate(cask_jobs.to_a)}"
          f.puts "matrix=#{JSON.generate(matrix)}"
        end
      end

      private

      sig {
        params(tap: T.nilable(Tap), labels: T::Array[String], cask_names: T::Array[String], skip_install: T::Boolean,
               new_cask: T::Boolean).returns(T::Array[T::Hash[Symbol,
                                                              T.any(String, T::Boolean, T::Array[String],
                                                                    T::Hash[Symbol, String])]])
      }
      def generate_matrix(tap, labels: [], cask_names: [], skip_install: false, new_cask: false)
        odie "This command must be run from inside a tap directory." unless tap

        git_diff = ["git", "-C", tap.path.to_s, "diff", "--name-only"]
        files = Utils.safe_popen_read(*git_diff, "--diff-filter=AMR", "origin...HEAD", "--",
                                      "*.rb").lines(chomp: true)
        cask_files, other_files = files.partition { |file| tap.cask_file?(file) }
        misplaced = other_files.reject { |file| file.start_with?("cmd/", ".github/actions/") }
        if misplaced.any?
          misplaced.each { |file| puts "::error file=#{file}::File is in wrong directory." }
          odie "Found Ruby files in wrong directory:\n#{misplaced.join("\n")}"
        end

        cask_names = cask_files.map { |file| File.basename(file, ".rb") } if cask_names.empty?
        added_casks = Utils.safe_popen_read(*git_diff, "--diff-filter=A", "origin...HEAD", "--", "*.rb")
                           .lines(chomp: true)
                           .select { |file| tap.cask_file?(file) }
                           .map do |file|
          File.basename(
            file, ".rb"
          )
        end
        Homebrew::API.with_no_api_env do
          Cask::CI::RunnerMatrix.generate(tap, cask_names, added_casks:, labels:, skip_install:, new_cask:)
        end
      end
    end
  end
end
