# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "formula"
require "tab"

module Homebrew
  module Cmd
    class TabCmd < AbstractCommand
      cmd_args do
        description <<~EOS
          Edit tab information for installed formulae or casks.

          This can be useful when you want to control whether an installed
          formula should be removed by `brew autoremove`.
          To prevent removal, mark the formula as installed on request;
          to allow removal, mark the formula as not installed on request.
        EOS

        switch "--installed-on-request",
               description: "Mark <installed_formula> or <installed_cask> as installed on request."
        switch "--no-installed-on-request",
               description: "Mark <installed_formula> or <installed_cask> as not installed on request."
        switch "--formula", "--formulae",
               description: "Only mark formulae."
        switch "--cask", "--casks",
               description: "Only mark casks."

        conflicts "--formula", "--cask"
        conflicts "--installed-on-request", "--no-installed-on-request"

        named_args [:installed_formula, :installed_cask], min: 1
      end

      sig { override.void }
      def run
        installed_on_request = if args.installed_on_request?
          true
        elsif args.no_installed_on_request?
          false
        end
        raise UsageError, "No marking option specified." if installed_on_request.nil?

        formulae, casks = T.cast(args.named.to_formulae_to_casks, [T::Array[Formula], T::Array[Cask::Cask]])
        formulae_not_installed = formulae.reject(&:any_version_installed?)
        casks_not_installed = casks.reject(&:installed?)
        if formulae_not_installed.any? || casks_not_installed.any?
          names = formulae_not_installed.map(&:name) + casks_not_installed.map(&:token)
          is_or_are = (names.length == 1) ? "is" : "are"
          odie "#{names.to_sentence} #{is_or_are} not installed."
        end

        [*formulae, *casks].each do |formula_or_cask|
          update_tab formula_or_cask, installed_on_request:
        end
      end

      private

      sig { params(formula_or_cask: T.any(Formula, Cask::Cask), installed_on_request: T::Boolean).void }
      def update_tab(formula_or_cask, installed_on_request:)
        name, tab = if formula_or_cask.is_a?(Formula)
          [formula_or_cask.name, Tab.for_formula(formula_or_cask)]
        else
          [formula_or_cask.token, formula_or_cask.tab]
        end

        if tab.tabfile.blank? || !tab.tabfile.exist?
          raise ArgumentError,
                "Tab file for #{name} does not exist."
        end

        installed_on_request_str = "#{"not " unless installed_on_request}installed on request"
        if (tab.installed_on_request && installed_on_request) ||
           (!tab.installed_on_request && !installed_on_request)
          ohai "#{name} is already marked as #{installed_on_request_str}."
          return
        end

        tab.installed_on_request = installed_on_request
        tab.write
        ohai "#{name} is now marked as #{installed_on_request_str}."
      end
    end
  end
end
