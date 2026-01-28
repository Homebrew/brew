# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "json"
require "open3"
require "style"

module Homebrew
  module DevCmd
    class StyleCmd < AbstractCommand
      cmd_args do
        description <<~EOS
          Check formulae or files for conformance to Homebrew style guidelines.

          Lists of <file>, <tap> and <formula> may not be combined. If none are
          provided, `style` will run style checks on the whole Homebrew library,
          including core code and all formulae.
        EOS
        switch "--fix",
               description: "Fix style violations automatically using RuboCop's auto-correct feature."
        switch "--display-cop-names",
               description: "Include the RuboCop cop name for each violation in the output.",
               hidden:      true
        switch "--reset-cache",
               description: "Reset the RuboCop cache."
        switch "--changed",
               description: "Check files that were changed from the `main` branch."
        switch "--formula", "--formulae",
               description: "Treat all named arguments as formulae."
        switch "--cask", "--casks",
               description: "Treat all named arguments as casks."
        comma_array "--only-cops",
                    description: "Specify a comma-separated <cops> list to check for violations of only the " \
                                 "listed RuboCop cops."
        comma_array "--except-cops",
                    description: "Specify a comma-separated <cops> list to skip checking for violations of the " \
                                 "listed RuboCop cops."

        conflicts "--formula", "--cask"
        conflicts "--only-cops", "--except-cops"

        named_args [:file, :tap, :formula, :cask], without_api: true
      end

      sig { override.void }
      def run
        Homebrew.install_bundler_gems!(groups: ["style"])

        if args.changed? && !args.no_named?
          raise UsageError, "`--changed` and named arguments are mutually exclusive!"
        end

        target = if args.changed?
          changed_ruby_or_shell_files
        elsif args.no_named?
          nil
        else
          args.named.to_paths
        end

        if target.blank? && args.changed?
          opoo "No style checks are available for the changed files!"
          return
        end

        only_cops = args.only_cops
        except_cops = args.except_cops

        options = {
          fix:         args.fix?,
          reset_cache: args.reset_cache?,
          debug:       args.debug?,
          verbose:     args.verbose?,
        }
        if only_cops
          options[:only_cops] = only_cops
        elsif except_cops
          options[:except_cops] = except_cops
        else
          options[:except_cops] = %w[FormulaAuditStrict]
        end

        Homebrew.failed = !Style.check_style_and_print(target, **options)
      end

      sig { returns(T::Array[Pathname]) }
      def changed_ruby_or_shell_files
        repo = Utils.popen_read("git", "rev-parse", "--show-toplevel").chomp
        odie "`brew style --changed` must be run inside a git repository!" unless $CHILD_STATUS.success?

        changed_files = Utils.popen_read("git", "diff", "--name-only", "--no-relative", "main")
        changed_files.split("\n").filter_map do |file|
          next if !file.end_with?(".rb", ".sh", ".yml", ".rbi") && file != "bin/brew"

          Pathname(file).expand_path(repo)
        end.select(&:exist?)
      end
    end
  end
end
