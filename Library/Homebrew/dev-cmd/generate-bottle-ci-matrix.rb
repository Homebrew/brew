# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "formula"
require "utils/bottles"

module Homebrew
  module DevCmd
    class GenerateBottleCiMatrix < AbstractCommand
      cmd_args do
        description <<~EOS
          Generate a GitHub Actions runner matrix for a dispatched bottle build.
          For internal use in Homebrew taps.
        EOS
        comma_array "--runners",
                    description: "Build runner names as a comma-separated list."

        named_args :formula, number: 1, without_api: true

        hide_from_man_page!
      end

      sig { override.void }
      def run
        runners = args.runners.to_a.map(&:strip).reject(&:empty?)
        raise UsageError, "`--runners` must specify at least one build runner." if runners.empty?

        github_run_id = ENV.fetch("GITHUB_RUN_ID") do
          raise UsageError, "The `$GITHUB_RUN_ID` environment variable must be set."
        end
        formula = args.named.to_formulae.fetch(0)
        matrix = runners.map do |runner|
          macos_runner_parts = runner.split("-", 2) if runner.match?(/\A\d+(?:\.\d+)?(?:-(?:arm64|x86_64))?\z/)
          bottle_tag = if (runner.start_with?("ubuntu-") && runner.end_with?("-arm")) ||
                          runner.match?(/\Alinux-arm64(?:\z|-)/)
            Utils::Bottles.tag(:arm64_linux)
          elsif runner.start_with?("ubuntu", "linux")
            Utils::Bottles.tag(:x86_64_linux)
          elsif macos_runner_parts
            Utils::Bottles::Tag.new(
              system: MacOSVersion.new(macos_runner_parts.fetch(0)).to_sym,
              arch:   macos_runner_parts.fetch(1, "x86_64").to_sym,
            )
          end
          if bottle_tag && formula.bottle_specification.tag?(bottle_tag, no_older_versions: true)
            ofail "#{formula.name} already has a bottle for #{bottle_tag}!"
          end

          if macos_runner_parts
            {
              runner:  "#{macos_runner_parts.fetch(0)}-#{macos_runner_parts.fetch(1, "x86_64")}-" \
                       "#{github_run_id}-dispatch",
              cleanup: false,
            }
          elsif runner.start_with?("ubuntu-")
            {
              runner:,
              container: {
                image:   "ghcr.io/homebrew/brew:main",
                options: "--user=linuxbrew",
              },
              workdir:   "/github/home",
              cleanup:   false,
            }
          elsif runner.match?(/\Alinux-(?:arm64|x86_64)\z/)
            { runner: "#{runner}-#{github_run_id}-dispatch", cleanup: false }
          else
            { runner:, cleanup: true }
          end
        end
        puts JSON.pretty_generate(matrix)

        return unless (github_output = ENV.fetch("GITHUB_OUTPUT", nil))

        File.open(github_output, "a") do |file|
          file.puts "runners=#{JSON.generate(matrix)}"
        end
      end
    end
  end
end
