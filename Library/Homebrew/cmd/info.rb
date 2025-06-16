# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

require "abstract_command"
require "missing_formula"
require "caveats"
require "options"
require "formula"
require "keg"
require "tab"
require "json"
require "utils/spdx"
require "deprecate_disable"
require "api"

module Homebrew
  module Cmd
    class Info < AbstractCommand
      VALID_DAYS = %w[30 90 365].freeze
      VALID_FORMULA_CATEGORIES = %w[install install-on-request build-error].freeze
      VALID_CATEGORIES = (VALID_FORMULA_CATEGORIES + %w[cask-install os-version]).freeze

      cmd_args do
        description <<~EOS
          Display brief statistics for your Homebrew installation.
          If a <formula> or <cask> is provided, show summary of information about it.
        EOS
        switch "--analytics",
               description: "List global Homebrew analytics data or, if specified, installation and " \
                            "build error data for <formula> (provided neither `$HOMEBREW_NO_ANALYTICS` " \
                            "nor `$HOMEBREW_NO_GITHUB_API` are set)."
        flag   "--days=",
               depends_on:  "--analytics",
               description: "How many days of analytics data to retrieve. " \
                            "The value for <days> must be `30`, `90` or `365`. The default is `30`."
        flag   "--category=",
               depends_on:  "--analytics",
               description: "Which type of analytics data to retrieve. " \
                            "The value for <category> must be `install`, `install-on-request` or `build-error`; " \
                            "`cask-install` or `os-version` may be specified if <formula> is not. " \
                            "The default is `install`."
        switch "--github-packages-downloads",
               description: "Scrape GitHub Packages download counts from HTML for a core formula.",
               hidden:      true
        switch "--github",
               description: "Open the GitHub source page for <formula> and <cask> in a browser. " \
                            "To view the history locally: `brew log -p` <formula> or <cask>"
        switch "--fetch-manifest",
               description: "Fetch GitHub Packages manifest for extra information when <formula> is not installed."
        flag   "--json",
               description: "Print a JSON representation. Currently the default value for <version> is `v1` for " \
                            "<formula>. For <formula> and <cask> use `v2`. See the docs for examples of using the " \
                            "JSON output: <https://docs.brew.sh/Querying-Brew>"
        switch "--installed",
               depends_on:  "--json",
               description: "Print JSON of formulae that are currently installed."
        switch "--eval-all",
               depends_on:  "--json",
               description: "Evaluate all available formulae and casks, whether installed or not, to print their " \
                            "JSON. Implied if `$HOMEBREW_EVAL_ALL` is set."
        switch "--variations",
               depends_on:  "--json",
               description: "Include the variations hash in each formula's JSON output."
        switch "-v", "--verbose",
               description: "Show more verbose analytics data for <formula>."
        switch "--formula", "--formulae",
               description: "Treat all named arguments as formulae."
        switch "--cask", "--casks",
               description: "Treat all named arguments as casks."

        conflicts "--installed", "--eval-all"
        conflicts "--installed", "--all"
        conflicts "--formula", "--cask"
        conflicts "--fetch-manifest", "--cask"
        conflicts "--fetch-manifest", "--json"

        named_args [:formula, :cask]
      end

      sig { override.void }
      def run
        if args.analytics?
          if args.days.present? && VALID_DAYS.exclude?(args.days)
            raise UsageError, "`--days` must be one of #{VALID_DAYS.join(", ")}."
          end

          if args.category.present?
            if args.named.present? && VALID_FORMULA_CATEGORIES.exclude?(args.category)
              raise UsageError,
                    "`--category` must be one of #{VALID_FORMULA_CATEGORIES.join(", ")} when querying formulae."
            end

            unless VALID_CATEGORIES.include?(args.category)
              raise UsageError, "`--category` must be one of #{VALID_CATEGORIES.join(", ")}."
            end
          end

          print_analytics
        elsif args.json
          all = args.eval_all?

          print_json(all)
        elsif args.github?
          raise FormulaOrCaskUnspecifiedError if args.no_named?

          exec_browser(*args.named.to_formulae_and_casks.map { |f| github_info(f) })
        elsif args.no_named?
          print_statistics
        else
          print_info
        end
      end

      def github_remote_path(remote, path)
        if remote =~ %r{^(?:https?://|git(?:@|://))github\.com[:/](.+)/(.+?)(?:\.git)?$}
          "https://github.com/#{Regexp.last_match(1)}/#{Regexp.last_match(2)}/blob/HEAD/#{path}"
        else
          "#{remote}/#{path}"
        end
      end

      private

      sig { void }
      def print_statistics
        return unless HOMEBREW_CELLAR.exist?

        count = Formula.racks.length
        puts "#{Utils.pluralize("keg", count, include_count: true)}, #{HOMEBREW_CELLAR.dup.abv}"
      end

      sig { void }
      def print_analytics
        if args.no_named?
          Utils::Analytics.output(args:)
          return
        end

        args.named.to_formulae_and_casks_and_unavailable.each_with_index do |obj, i|
          puts unless i.zero?

          case obj
          when Formula
            Utils::Analytics.formula_output(obj, args:)
          when Cask::Cask
            Utils::Analytics.cask_output(obj, args:)
          when FormulaOrCaskUnavailableError
            Utils::Analytics.output(filter: obj.name, args:)
          else
            raise
          end
        end
      end

      sig { void }
      def print_info
        args.named.to_formulae_and_casks_and_unavailable.each_with_index do |obj, i|
          puts unless i.zero?

          case obj
          when Formula
            info_formula(obj)
          when Cask::Cask
            info_cask(obj)
          when FormulaOrCaskUnavailableError
            # The formula/cask could not be found
            ofail obj.message
            # No formula with this name, try a missing formula lookup
            if (reason = MissingFormula.reason(obj.name, show_info: true))
              $stderr.puts reason
            end
          else
            raise
          end
        end
      end

      def json_version(version)
        version_hash = {
          true => :default,
          "v1" => :v1,
          "v2" => :v2,
        }

        raise UsageError, "invalid JSON version: #{version}" unless version_hash.include?(version)

        version_hash[version]
      end

      sig { params(all: T::Boolean).void }
      def print_json(all)
        raise FormulaOrCaskUnspecifiedError if !(all || args.installed?) && args.no_named?

        json = case json_version(args.json)
        when :v1, :default
          raise UsageError, "Cannot specify `--cask` when using `--json=v1`!" if args.cask?

          formulae = if all
            Formula.all(eval_all: args.eval_all?).sort
          elsif args.installed?
            Formula.installed.sort
          else
            args.named.to_formulae
          end

          if args.variations?
            formulae.map(&:to_hash_with_variations)
          else
            formulae.map(&:to_hash)
          end
        when :v2
          formulae, casks = T.let(
            if all
              [
                Formula.all(eval_all: args.eval_all?).sort,
                Cask::Cask.all(eval_all: args.eval_all?).sort_by(&:full_name),
              ]
            elsif args.installed?
              [Formula.installed.sort, Cask::Caskroom.casks.sort_by(&:full_name)]
            else
              T.cast(args.named.to_formulae_to_casks, [T::Array[Formula], T::Array[Cask::Cask]])
            end, [T::Array[Formula], T::Array[Cask::Cask]]
          )

          if args.variations?
            {
              "formulae" => formulae.map(&:to_hash_with_variations),
              "casks"    => casks.map(&:to_hash_with_variations),
            }
          else
            {
              "formulae" => formulae.map(&:to_hash),
              "casks"    => casks.map(&:to_h),
            }
          end
        else
          raise
        end

        puts JSON.pretty_generate(json)
      end

      def github_info(formula_or_cask)
        return formula_or_cask.path if formula_or_cask.tap.blank? || formula_or_cask.tap.remote.blank?

        path = case formula_or_cask
        when Formula
          formula = formula_or_cask
          formula.path.relative_path_from(T.must(formula.tap).path)
        when Cask::Cask
          cask = formula_or_cask
          if cask.sourcefile_path.blank? || cask.sourcefile_path.extname != ".rb"
            return "#{cask.tap.default_remote}/blob/HEAD/#{cask.tap.relative_cask_path(cask.token)}"
          end

          cask.sourcefile_path.relative_path_from(cask.tap.path)
        end

        github_remote_path(formula_or_cask.tap.remote, path)
      end

      def info_formula(formula)
        specs = []

        if (stable = formula.stable)
          string = "stable #{stable.version}"
          string += " (bottled)" if stable.bottled? && formula.pour_bottle?
          specs << string
        end

        specs << "HEAD" if formula.head

        attrs = []
        attrs << "pinned at #{formula.pinned_version}" if formula.pinned?
        attrs << "keg-only" if formula.keg_only?

        puts "#{oh1_title(formula.full_name)}: #{specs * ", "}#{" [#{attrs * ", "}]" unless attrs.empty?}"
        puts formula.desc if formula.desc
        puts Formatter.url(formula.homepage) if formula.homepage

        deprecate_disable_info_string = DeprecateDisable.message(formula)
        if deprecate_disable_info_string.present?
          deprecate_disable_info_string.tap { |info_string| info_string[0] = info_string[0].upcase }
          puts deprecate_disable_info_string
        end

        conflicts = formula.conflicts.map do |conflict|
          reason = " (because #{conflict.reason})" if conflict.reason
          "#{conflict.name}#{reason}"
        end.sort!
        unless conflicts.empty?
          puts <<~EOS
            Conflicts with:
              #{conflicts.join("\n  ")}
          EOS
        end

        kegs = formula.installed_kegs
        heads, versioned = kegs.partition { |keg| keg.version.head? }
        kegs = [
          *heads.sort_by { |keg| -keg.tab.time.to_i },
          *versioned.sort_by(&:scheme_and_version),
        ]
        if kegs.empty?
          puts "Not installed"
          if (bottle = formula.bottle)
            begin
              bottle.fetch_tab(quiet: !args.debug?) if args.fetch_manifest?
              bottle_size = bottle.bottle_size
              installed_size = bottle.installed_size
              puts "Bottle Size: #{disk_usage_readable(bottle_size)}" if bottle_size
              puts "Installed Size: #{disk_usage_readable(installed_size)}" if installed_size
            rescue RuntimeError => e
              odebug e
            end
          end
        else
          puts "Installed"
          kegs.each do |keg|
            puts "#{keg} (#{keg.abv})#{" *" if keg.linked?}"
            tab = keg.tab.to_s
            puts "  #{tab}" unless tab.empty?
          end
        end

        puts "From: #{Formatter.url(github_info(formula))}"

        puts "License: #{SPDX.license_expression_to_string formula.license}" if formula.license.present?

        unless formula.deps.empty?
          ohai "Dependencies"
          %w[build required recommended optional].map do |type|
            deps = formula.deps.send(type).uniq
            puts "#{type.capitalize}: #{decorate_dependencies deps}" unless deps.empty?
          end
        end

        unless formula.requirements.to_a.empty?
          ohai "Requirements"
          %w[build required recommended optional].map do |type|
            reqs = formula.requirements.select(&:"#{type}?")
            next if reqs.to_a.empty?

            puts "#{type.capitalize}: #{decorate_requirements(reqs)}"
          end
        end

        if !formula.options.empty? || formula.head
          ohai "Options"
          Options.dump_for_formula formula
        end

        caveats = Caveats.new(formula)
        ohai "Caveats", caveats.to_s unless caveats.empty?

        Utils::Analytics.formula_output(formula, args:)
      end

      def decorate_dependencies(dependencies)
        deps_status = dependencies.map do |dep|
          if dep.satisfied?([])
            pretty_installed(dep_display_s(dep))
          else
            pretty_uninstalled(dep_display_s(dep))
          end
        end
        deps_status.join(", ")
      end

      def decorate_requirements(requirements)
        req_status = requirements.map do |req|
          req_s = req.display_s
          req.satisfied? ? pretty_installed(req_s) : pretty_uninstalled(req_s)
        end
        req_status.join(", ")
      end

      def dep_display_s(dep)
        return dep.name if dep.option_tags.empty?

        "#{dep.name} #{dep.option_tags.map { |o| "--#{o}" }.join(" ")}"
      end

      def info_cask(cask)
        require "cask/info"

        Cask::Info.info(cask, args:)
      end
    end
  end
end
