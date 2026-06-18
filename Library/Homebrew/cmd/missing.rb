# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "formula"
require "cask/caskroom"
require "missing"

module Homebrew
  module Cmd
    class Missing < AbstractCommand
      cmd_args do
        description <<~EOS
          Check the given <formula> kegs and <cask> installations for missing dependencies.
          If no <formula> or <cask> are provided, check all kegs and casks. Will exit with
          a non-zero status if any kegs or casks are found to be missing dependencies.
        EOS
        comma_array "--hide",
                    description: "Act as if none of the specified <hidden> are installed. <hidden> should be " \
                                 "a comma-separated list of formulae or casks."

        named_args [:formula, :cask]
      end

      sig { override.void }
      def run
        return if !HOMEBREW_CELLAR.exist? && !Cask::Caskroom.path.exist?

        formulae, casks = if args.no_named?
          [Formula.installed, Cask::Caskroom.casks]
        else
          args.named.to_resolved_formulae_to_casks
        end
        formulae = formulae.sort
        casks = casks.sort_by(&:full_name)
        hide = args.hide || []
        package_count = formulae.size + casks.size
        missing_deps = Homebrew::Missing.deps(formulae, casks, hide)

        (formulae + casks).each do |formula_or_cask|
          missing = missing_deps[formula_or_cask.full_name]
          next if missing.blank?

          Homebrew.failed = true
          print "#{formula_or_cask}: " if package_count > 1
          puts missing.join(" ")
        end
      end
    end
  end
end
