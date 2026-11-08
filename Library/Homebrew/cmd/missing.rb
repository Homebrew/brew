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
          Print installation instructions to standard error unless `--hide` is used.
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
        missing_deps = Homebrew::Missing.deps(formulae, casks, args.hide || [])

        (formulae + casks).each do |formula_or_cask|
          missing = missing_deps[formula_or_cask.full_name]
          next if missing.blank?

          Homebrew.failed = true
          puts Homebrew::Missing.format_deps(formula_or_cask.to_s, missing, show_name: formulae.size + casks.size > 1)
        end

        return if missing_deps.empty? || args.hide

        opoo <<~EOS
          You should `brew install` the missing dependencies:
            #{Homebrew::Missing.install_commands(missing_deps).join("\n  ")}
        EOS
      end
    end
  end
end
