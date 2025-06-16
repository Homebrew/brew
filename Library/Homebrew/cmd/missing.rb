# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "formula"
require "tab"
require "diagnostic"

module Homebrew
  module Cmd
    class Missing < AbstractCommand
      cmd_args do
        description <<~EOS
          Check the given <formula> kegs for missing dependencies. If no <formula> are
          provided, check all kegs. Will exit with a non-zero status if any kegs are found
          to be missing dependencies.
        EOS
        comma_array "--hide",
                    description: "Act as if none of the specified <hidden> are installed. <hidden> should be " \
                                 "a comma-separated list of formulae."

        named_args :formula
      end

      sig { override.void }
      def run
        return unless HOMEBREW_CELLAR.exist?

        ff = if args.no_named?
          Formula.installed.sort
        else
          args.named.to_resolved_formulae.sort
        end

        ff.each do |f|
          missing = f.missing_dependencies(hide: args.hide || [])
          next if missing.empty?

          Homebrew.failed = true
          print "#{f}: " if ff.size > 1
          puts missing.join(" ")
        end
      end
    end
  end
end
