# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "formula"
require "livecheck/livecheck"
require "livecheck/strategy"

module Homebrew
  module DevCmd
    class LivecheckCmd < AbstractCommand
      cmd_args do
        description <<~EOS
          Check for newer versions of formulae and/or casks from upstream.
          If no formula or cask argument is passed, the list of formulae and
          casks to check is taken from `$HOMEBREW_LIVECHECK_WATCHLIST` or
          `~/.homebrew/livecheck_watchlist.txt`.
        EOS
        switch "--full-name",
               description: "Print formulae and casks with fully-qualified names."
        flag   "--tap=",
               description: "Check formulae and casks within the given tap, specified as <user>`/`<repo>."
        switch "--eval-all",
               description: "Evaluate all available formulae and casks, whether installed or not, to check them."
        switch "--installed",
               description: "Check formulae and casks that are currently installed."
        switch "--newer-only",
               description: "Show the latest version only if it's newer than the current formula or cask version."
        switch "--json",
               description: "Output information in JSON format."
        switch "-r", "--resources",
               description: "Also check resources for formulae."
        switch "-q", "--quiet",
               description: "Suppress warnings, don't print a progress bar for JSON output."
        switch "--formula", "--formulae",
               description: "Only check formulae."
        switch "--cask", "--casks",
               description: "Only check casks."
        switch "--extract-plist",
               description: "Enable checking multiple casks with ExtractPlist strategy."
        switch "--autobump",
               description: "Include packages that are autobumped by BrewTestBot. By default these are skipped."

        conflicts "--tap", "--installed", "--eval-all"
        conflicts "--json", "--debug"
        conflicts "--formula", "--cask"
        conflicts "--formula", "--extract-plist"

        named_args [:formula, :cask], without_api: true
      end

      sig { override.void }
      def run
        Homebrew.install_bundler_gems!(groups: ["livecheck"])

        eval_all = args.eval_all?

        if args.debug? && args.verbose?
          puts args
          puts Homebrew::EnvConfig.livecheck_watchlist if Homebrew::EnvConfig.livecheck_watchlist.present?
        end

        formulae_and_casks_to_check = Homebrew.with_no_api_env do
          if args.tap
            tap = Tap.fetch(args.tap)
            formulae = args.cask? ? [] : tap.formula_files.map { |path| Formulary.factory(path) }
            casks = args.formula? ? [] : tap.cask_files.map { |path| Cask::CaskLoader.load(path) }
            formulae + casks
          elsif args.installed?
            formulae = args.cask? ? [] : Formula.installed
            casks = args.formula? ? [] : Cask::Caskroom.casks
            formulae + casks
          elsif args.named.present?
            args.named.to_formulae_and_casks_with_taps
          elsif eval_all
            formulae = args.cask? ? [] : Formula.all(eval_all:)
            casks = args.formula? ? [] : Cask::Cask.all(eval_all:)
            formulae + casks
          elsif File.exist?(watchlist_path)
            begin
              # This removes blank lines, comment lines, and trailing comments
              names = Pathname.new(watchlist_path).read.lines
                              .filter_map do |line|
                                comment_index = line.index("#")
                                next if comment_index&.zero?

                                line = line[0...comment_index] if comment_index
                                line&.strip.presence
                              end

              named_args = CLI::NamedArgs.new(*names, parent: args)
              named_args.to_formulae_and_casks(ignore_unavailable: true)
            rescue Errno::ENOENT => e
              onoe e
            end
          else
            raise UsageError,
                  "`brew livecheck` with no arguments needs a watchlist file to be present or `--eval-all` passed!"
          end
        end

        skipped_autobump = T.let(false, T::Boolean)
        if skip_autobump?
          autobump_lists = {}

          formulae_and_casks_to_check = formulae_and_casks_to_check.reject do |formula_or_cask|
            tap = formula_or_cask.tap
            next false if tap.nil?

            autobump_lists[tap] ||= tap.autobump

            name = formula_or_cask.respond_to?(:token) ? formula_or_cask.token : formula_or_cask.name
            next unless autobump_lists[tap].include?(name)

            odebug "Skipping #{name} as it is autobumped in #{tap}."
            skipped_autobump = true
            true
          end
        end

        formulae_and_casks_to_check = formulae_and_casks_to_check.sort_by do |formula_or_cask|
          formula_or_cask.respond_to?(:token) ? formula_or_cask.token : formula_or_cask.name
        end

        raise UsageError, "No formulae or casks to check." if formulae_and_casks_to_check.blank? && !skipped_autobump
        return if formulae_and_casks_to_check.blank?

        options = {
          json:                 args.json?,
          full_name:            args.full_name?,
          handle_name_conflict: !args.formula? && !args.cask?,
          check_resources:      args.resources?,
          newer_only:           args.newer_only?,
          extract_plist:        args.extract_plist?,
          quiet:                args.quiet?,
          debug:                args.debug?,
          verbose:              args.verbose?,
        }.compact

        Livecheck.run_checks(formulae_and_casks_to_check, **options)
      end

      private

      sig { returns(String) }
      def watchlist_path
        @watchlist_path ||= T.let(File.expand_path(Homebrew::EnvConfig.livecheck_watchlist), T.nilable(String))
      end

      sig { returns(T::Boolean) }
      def skip_autobump?
        !(args.autobump? || Homebrew::EnvConfig.livecheck_autobump?)
      end
    end
  end
end
