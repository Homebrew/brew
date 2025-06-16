# typed: strict
# frozen_string_literal: true

require "bundle/checker"

module Homebrew
  module Bundle
    module Commands
      module Check
        sig {
          params(global: T::Boolean, file: T.nilable(String), no_upgrade: T::Boolean, verbose: T::Boolean,
                 quiet: T::Boolean).void
        }
        def self.run(global: false, file: nil, no_upgrade: false, verbose: false, quiet: false)
          output_errors = verbose
          exit_on_first_error = !verbose
          check_result = Homebrew::Bundle::Checker.check(
            global:, file:,
            exit_on_first_error:, no_upgrade:, verbose:
          )

          # Allow callers of `brew bundle check` to specify when they've already
          # output some formulae errors.
          check_missing_formulae = ENV.fetch("HOMEBREW_BUNDLE_CHECK_ALREADY_OUTPUT_FORMULAE_ERRORS", "")
                                      .strip
                                      .split

          if check_result.work_to_be_done
            puts "brew bundle can't satisfy your Brewfile's dependencies." if check_missing_formulae.blank?

            if output_errors
              check_result.errors.each do |error|
                if (match = error.match(/^Formula (.+) needs to be installed/)) &&
                   check_missing_formulae.include?(match[1])
                  next
                end

                puts "→ #{error}"
              end
            end

            puts "Satisfy missing dependencies with `brew bundle install`."
            exit 1
          end

          puts "The Brewfile's dependencies are satisfied." unless quiet
        end
      end
    end
  end
end
