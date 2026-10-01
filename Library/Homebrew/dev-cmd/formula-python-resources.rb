# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "formula"
require "json"

module Homebrew
  module DevCmd
    class FormulaPythonResources < AbstractCommand
      cmd_args do
        description <<~EOS
          Print JSON describing the PyPI resources used by <formula>.
        EOS
        switch "--all",
               description: "Include all available formulae."
        flag   "--tap=",
               description: "Only include formulae from the named tap. Requires `--all`."

        named_args :formula, without_api: true

        hide_from_man_page!
      end

      sig { override.void }
      def run
        if args.all?
          raise UsageError, "`--all` cannot be combined with named formulae." if args.named.present?

          formulae = Formula.all
        else
          raise FormulaUnspecifiedError if args.named.blank?
          raise UsageError, "`--tap` requires `--all`." if args.tap

          formulae = args.named.to_formulae
        end

        output = formulae.filter_map do |formula|
          tap_name = formula.tap&.name
          next if args.tap && tap_name != args.tap

          resources = formula.resources.filter_map do |resource|
            url = resource.url
            next unless url&.match?(%r{\Ahttps?://files\.pythonhosted\.org/})

            {
              name: resource.name,
              url:,
            }
          end
          next if resources.empty?

          {
            name:       formula.name,
            tap:        tap_name,
            deprecated: formula.deprecated?,
            disabled:   formula.disabled?,
            resources:  resources.sort_by { |resource| resource.fetch(:name) },
          }
        end

        puts JSON.pretty_generate(output.sort_by { |formula| formula.fetch(:name) })
      end
    end
  end
end
