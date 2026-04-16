# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "formula"
require "cask_dependent"

module Homebrew
  module Cmd
    class Leaves < AbstractCommand
      cmd_args do
        description <<~EOS
          List installed formulae that are not dependencies of another installed formula or cask.
        EOS
        switch "-r", "--installed-on-request",
               description: "Only list leaves that were manually installed."
        switch "-p", "--installed-as-dependency",
               description: "Only list leaves that were installed as dependencies."

        conflicts "--installed-on-request", "--installed-as-dependency"

        named_args :none
      end

      sig { override.void }
      def run
        installed = Formula.installed

        # Build a set of dependency names from tab data to avoid loading full Formula objects
        # via Formulary.resolve for each dependency (which is expensive I/O).
        formula_dep_names = installed.flat_map do |f|
          if (tab_deps = f.any_installed_keg&.runtime_dependencies)
            tab_deps.filter_map do |dep|
              full_name = dep["full_name"]
              next unless full_name

              Utils.name_from_full_name(full_name)
            end
          else
            # Fallback for installations without tab runtime_dependencies.
            f.installed_runtime_formula_dependencies.map(&:name)
          end
        end

        # Add direct cask formula dependency names; their transitive deps are already in dep_names.
        cask_dep_names = Cask::Caskroom.casks.flat_map do |cask|
          CaskDependent.new(cask).deps.map { |dep| Utils.name_from_full_name(dep.name) }
        end

        dep_names = T.let((formula_dep_names + cask_dep_names).to_set, T::Set[String])

        leaves_list = installed.reject { |f| dep_names.intersect?(f.possible_names) }
        leaves_list.select! { |leaf| installed_on_request?(leaf) } if args.installed_on_request?
        leaves_list.select! { |leaf| installed_as_dependency?(leaf) } if args.installed_as_dependency?

        leaves_list.map(&:full_name)
                   .sort
                   .each { |leaf| puts(leaf) }
      end

      private

      sig { params(formula: Formula).returns(T::Boolean) }
      def installed_on_request?(formula)
        formula.any_installed_keg&.tab&.installed_on_request == true
      end

      sig { params(formula: Formula).returns(T::Boolean) }
      def installed_as_dependency?(formula)
        formula.any_installed_keg&.tab&.installed_as_dependency == true
      end
    end
  end
end
