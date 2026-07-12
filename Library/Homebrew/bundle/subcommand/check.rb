# typed: strict
# frozen_string_literal: true

require "abstract_subcommand"

require "bundle/checker"
module Homebrew
  module Cmd
    class Bundle < Homebrew::AbstractCommand
      class CheckSubcommand < Homebrew::AbstractSubcommand
        subcommand_args do
          usage_banner <<~EOS
            `brew bundle check`:
            Check if all dependencies present in the `Brewfile` are installed.

            This provides a successful exit code if everything is up-to-date, making it useful for scripting. Use `--verbose` to list unmet dependencies.
          EOS
          named_args :none
          switch "-v", "--verbose",
                 description: "List all missing dependencies."
          switch "--no-upgrade",
                 description: "Do not check for outdated dependencies. " \
                              "Note they may still be upgraded by `brew install` if needed.",
                 env:         :bundle_no_upgrade
          switch "--install",
                 description: "Run `install` before checking dependencies."
        end

        sig { override.void }
        def run
          output_errors = context.verbose
          exit_on_first_error = !context.verbose
          check_result = Homebrew::Bundle::Checker.check(
            global: context.global, file: context.file,
            exit_on_first_error:, no_upgrade: context.no_upgrade, verbose: context.verbose
          )

          # Allow callers of `brew bundle check` to specify when they've already
          # output some formulae errors.
          check_missing_formulae = ENV.fetch("HOMEBREW_BUNDLE_CHECK_ALREADY_OUTPUT_FORMULAE_ERRORS", "")
                                      .strip
                                      .split

          if check_result.work_to_be_done
            $stderr.puts "brew bundle can't satisfy your Brewfile's dependencies." if check_missing_formulae.blank?

            if output_errors
              check_result.errors.each do |error|
                if (match = error.match(/^Formula (.+) needs to be installed/)) &&
                   check_missing_formulae.include?(match[1])
                  next
                end

                $stderr.puts "→ #{error}"
              end
            else
              $stderr.puts "Run `brew bundle check --verbose` to list unmet dependencies."
            end

            $stderr.puts "Satisfy missing dependencies with `brew bundle install`."
            exit 1
          end

          puts "The Brewfile's dependencies are satisfied." unless quiet
        end
      end
    end
  end
end
