# typed: strict
# frozen_string_literal: true

require "formula"
require "tap"

module Homebrew
  module DevCmd
    class Lgtm < AbstractCommand
      include SystemCommand::Mixin

      cmd_args do
        description <<~EOS
          Run `brew typecheck`, `brew style --changed` and the relevant `brew tests`,
          `brew audit` and `brew test` checks in one go.
        EOS
        switch "--online",
               description: "Run additional, slower checks that require a network connection."
        named_args :none
      end

      sig { override.void }
      def run
        Homebrew.install_bundler_gems!(groups: Homebrew.valid_gem_groups - ["sorbet"])

        tap = Tap.from_path(Dir.pwd)

        typecheck_args = ["typecheck", tap&.name].compact
        ohai "brew #{typecheck_args.join(" ")}"
        safe_system HOMEBREW_BREW_FILE, *typecheck_args
        puts

        ohai "brew style --changed --fix"
        safe_system HOMEBREW_BREW_FILE, "style", "--changed", "--fix"
        puts

        if tap
          added_files = Utils.popen_read("git", "diff", "--name-only", "--no-relative", "--diff-filter=A", "main")
                             .split("\n")
          changed_formulae = []
          new_formulae = []
          changed_casks = []
          new_casks = []
          changed_audit_args = ["--strict"]
          changed_audit_args << "--online" if args.online?
          new_audit_args = args.online? ? ["--new"] : ["--strict"]

          Utils.popen_read("git", "diff", "--name-only", "--no-relative", "--diff-filter=AMR", "main")
               .split("\n").each do |file|
            next if file.blank?

            tapped_name = "#{tap.name}/#{Pathname(file).basename(".rb")}"

            if tap.formula_file?(file)
              (added_files.include?(file) ? new_formulae : changed_formulae) << tapped_name
            elsif tap.cask_file?(file)
              (added_files.include?(file) ? new_casks : changed_casks) << tapped_name
            end
          end

          if Utils.popen_read("git", "ls-files", "--others", "--exclude-standard", "--full-name")
                  .split("\n")
                  .any? { |file| tap.formula_file?(file) || tap.cask_file?(file) }
            opoo "Untracked formula or cask files are not checked by `brew lgtm`; stage or commit them first."
          end

          if !args.online? && [*new_formulae, *new_casks].present?
            opoo "New formulae or casks were detected. Run `brew lgtm --online` to include `brew audit --new` checks."
          end

          unless changed_formulae.empty?
            ohai "brew audit #{changed_audit_args.join(" ")} --skip-style --formula #{changed_formulae.join(" ")}"
            safe_system HOMEBREW_BREW_FILE, "audit", *changed_audit_args, "--skip-style", "--formula",
                        *changed_formulae
            puts
          end

          unless new_formulae.empty?
            ohai "brew audit #{new_audit_args.join(" ")} --skip-style --formula #{new_formulae.join(" ")}"
            safe_system HOMEBREW_BREW_FILE, "audit", *new_audit_args, "--skip-style", "--formula", *new_formulae
            puts
          end

          unless changed_casks.empty?
            ohai "brew audit #{changed_audit_args.join(" ")} --skip-style --cask #{changed_casks.join(" ")}"
            safe_system HOMEBREW_BREW_FILE, "audit", *changed_audit_args, "--skip-style", "--cask", *changed_casks
            puts
          end

          unless new_casks.empty?
            ohai "brew audit #{new_audit_args.join(" ")} --skip-style --cask #{new_casks.join(" ")}"
            safe_system HOMEBREW_BREW_FILE, "audit", *new_audit_args, "--skip-style", "--cask", *new_casks
            puts
          end

          formulae_to_test = [*changed_formulae, *new_formulae].select do |formula_name|
            next true if Formulary.factory(formula_name).latest_version_installed?

            opoo "Skipping `brew test #{formula_name}`; the latest version is not installed."
            false
          end
          return if formulae_to_test.empty?

          ohai "brew test #{formulae_to_test.join(" ")}"
          safe_system HOMEBREW_BREW_FILE, "test", *formulae_to_test
        else
          audit_or_tests_args = ["--changed"]
          audit_or_tests_args << "--online" if args.online?
          ohai "brew tests #{audit_or_tests_args.join(" ")}"
          safe_system HOMEBREW_BREW_FILE, "tests", *audit_or_tests_args
        end
      end
    end
  end
end
