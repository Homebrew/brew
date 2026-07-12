# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "missing_formula"
require "caveats"
require "options"
require "formula"
require "formula_pin"
require "keg"
require "tab"
require "json"
require "cask/cask_loader"
require "utils/spdx"
require "deprecate_disable"
require "api"

module Homebrew
  module Cmd
    class Info < AbstractCommand
      class NameSize < T::Struct
        const :name, String
        const :size, Integer
      end
      private_constant :NameSize

      VALID_DAYS = %w[30 90 365].freeze
      VALID_FORMULA_CATEGORIES = %w[install install-on-request build-error].freeze
      VALID_CATEGORIES = T.let((VALID_FORMULA_CATEGORIES + %w[cask-install os-version]).freeze, T::Array[String])

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
               description: "Fetch GitHub Packages manifest for extra information when <formula> is not installed.",
               odeprecated: true
        flag   "--json",
               description: "Print a JSON representation. Currently the default value for <version> is `v1`." \
                            "`v1` is valid for <formula> only. `v2` is valid for both <formula> and <cask>." \
                            "See the docs for examples of using the JSON output: <https://docs.brew.sh/Querying-Brew>"
        switch "--installed",
               description: "Output a human-readable inventory of installed formulae and casks. If `--json` is " \
                            "passed, print JSON for installed formulae and, with `--json=v2`, installed casks."
        switch "--eval-all",
               depends_on:  "--json",
               description: "Evaluate all available formulae and casks, whether installed or not, to print their " \
                            "JSON.",
               env:         :eval_all,
               odeprecated: true
        switch "--variations",
               depends_on:  "--json",
               description: "Include the variations hash in each formula's JSON output."
        switch "-v", "--verbose",
               description: "Show more verbose data for <formula>, or full information with `--installed`."
        switch "--formula", "--formulae",
               description: "Treat all named arguments as formulae."
        switch "--cask", "--casks",
               description: "Treat all named arguments as casks."
        switch "--sizes",
               description: "Show the size of installed formulae and casks."

        conflicts "--installed", "--eval-all"
        conflicts "--formula", "--cask"
        conflicts "--fetch-manifest", "--cask"
        conflicts "--fetch-manifest", "--json"

        named_args [:formula, :cask]
      end

      sig { override.void }
      def run
        if args.sizes?
          if args.no_named?
            print_sizes
          else
            formulae, casks = args.named.to_formulae_to_casks
            formulae = T.cast(formulae, T::Array[Formula])
            print_sizes(formulae:, casks:)
          end
        elsif args.analytics?
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
        elsif (json = args.json)
          eval_all = args.eval_all?
          eval_all ||= args.no_named? && !args.installed? && Homebrew::EnvConfig.tap_trust_configured?
          print_json(json, eval_all)
        elsif args.installed?
          T.let([
            *(args.cask? ? [] : Formula.installed.sort),
            *(args.formula? ? [] : Cask::Caskroom.casks.sort_by(&:full_name)),
          ], T::Array[T.any(Formula, Cask::Cask)]).each_with_index do |formula_or_cask, i|
            puts unless i.zero?

            info_formula_or_cask(formula_or_cask, quiet: !args.verbose?)
          end
        elsif args.github?
          raise FormulaOrCaskUnspecifiedError if args.no_named?

          exec_browser(*args.named.to_formulae_and_casks.map do |formula_keg_or_cask|
            formula_or_cask = T.cast(formula_keg_or_cask, T.any(Formula, Cask::Cask))
            github_info(formula_or_cask)
          end)
        elsif args.no_named?
          print_statistics
        else
          print_info(quiet: args.quiet?)
        end
      end

      sig { params(remote: String, path: String).returns(String) }
      def github_remote_path(remote, path)
        if remote =~ %r{^(?:https?://|git(?:@|://))github\.com[:/](.+)/(.+?)(?:\.git)?$}
          "https://github.com/#{Regexp.last_match(1)}/#{Regexp.last_match(2)}/blob/HEAD/#{path}"
        else
          "#{remote}/#{path}"
        end
      end

      sig { params(formula_or_cask: T.any(Formula, Cask::Cask)).returns(T::Array[String]) }
      def self.metadata_lines(formula_or_cask)
        return [] unless $stdout.tty?

        case formula_or_cask
        when Formula
          formula_metadata_lines(formula_or_cask)
        when Cask::Cask
          if formula_or_cask.pinned?
            pinned = "Pinned: #{formula_or_cask.pinned_version}"
            if (pinned_time = pin_path_mtime(formula_or_cask.pin_path))
              pinned << " on #{formatted_time(pinned_time)}"
            end
            [pinned]
          else
            []
          end
        else
          T.absurd(formula_or_cask)
        end
      end

      sig { params(formula_or_cask: T.any(Formula, Cask::Cask)).returns(T::Array[String]) }
      def self.requirements_lines(formula_or_cask)
        return [] unless $stdout.tty?

        case formula_or_cask
        when Formula
          []
        when Cask::Cask
          cask_requirements_lines(formula_or_cask)
        else
          T.absurd(formula_or_cask)
        end
      end

      sig { params(tab: T.any(Tab, Cask::Tab)).returns(String) }
      def self.installation_status(tab)
        # TODO: Deprecate reading `installed_as_dependency`; `installed_on_request`
        # is the only state we need to render install intent.
        tab.installed_on_request ? "Installed (on request)" : "Installed (as dependency)"
      end

      sig { params(tab: T.any(Tab, Cask::Tab)).returns(String) }
      def self.installation_reason(tab)
        return "-" unless tab.installed_on_request_present?

        tab.installed_on_request ? "on request" : "dependency"
      end

      sig { params(version: String, tab: T.any(Tab, Cask::Tab)).returns(String) }
      def self.installation_summary(version, tab)
        reason = installation_reason(tab)

        "Installed: #{version}#{" (#{reason})" if reason != "-"}"
      end

      sig { params(requirement: Requirement).returns(T::Boolean) }
      def self.requirement_for_other_os?(requirement)
        requirement.instance_of?(MacOSRequirement) || requirement.instance_of?(LinuxRequirement)
      end

      sig { params(installed_count: Integer, total_count: Integer).returns(String) }
      def self.dependency_status_counts(installed_count, total_count)
        missing_count = total_count - installed_count
        return "all installed #{Formatter.success("✔")}" if missing_count.zero?

        "#{installed_count} installed #{Formatter.success("✔")}, " \
          "#{missing_count} missing #{Formatter.error("✘")}"
      end

      sig { params(full_name: String, name: String).returns(T::Array[String]) }
      def self.installed_dependent_names(full_name, name)
        Formula.racks.filter_map do |rack|
          keg = Keg.from_rack(rack)
          next unless keg

          tab_path = keg/AbstractTab::FILENAME
          next unless tab_path.file?

          # Fast path: skip JSON parsing when the formula name
          # does not appear anywhere in the raw receipt.
          content = File.read(tab_path)
          next unless content.include?(name)

          tab_deps = Tab.from_file_content(content, tab_path).runtime_dependencies
          next unless tab_deps

          dependent = tab_deps.any? do |dep|
            dep_full_name = T.cast(dep, T::Hash[String, T.untyped])["full_name"]
            dep_full_name == full_name || dep_full_name&.then { Utils.name_from_full_name(it) } == name
          end
          keg.name if dependent
        end.sort.uniq
      end

      sig { params(formula: Formula).returns(T::Array[String]) }
      def self.formula_metadata_lines(formula)
        metadata = T.let([], T::Array[String])
        if formula.pinned?
          pinned = "Pinned: #{formula.pinned_version}"
          if (pinned_time = pin_path_mtime(FormulaPin.new(formula).path))
            pinned << " on #{formatted_time(pinned_time)}"
          end
          metadata << pinned
        end

        if !formula.any_version_installed? &&
           formula_installs_from_source?(formula) &&
           formula.requirements.none? { |requirement| requirement_for_other_os?(requirement) }
          metadata << "Installs from source: yes"
        end
        metadata
      end

      sig { params(cask: Cask::Cask).returns(T::Array[String]) }
      def self.cask_requirements_lines(cask)
        macos_requirements = [cask.depends_on.macos, cask.depends_on.maximum_macos].compact
        requirement = if macos_requirements.present?
          requirement = macos_requirements.filter_map do |macos_requirement|
            macos_requirement.display_s.delete_suffix(" (or Linux)").delete_prefix("macOS").strip.presence
          end
          requirement = requirement.present? ? "macOS #{requirement.join(", ")}" : "macOS"
          requirement += " or Linux" if cask.supports_linux?
          requirement
        elsif cask.supports_macos? && cask.supports_linux?
          "macOS or Linux"
        elsif cask.supports_macos?
          "macOS"
        elsif cask.supports_linux?
          "Linux"
        end

        requirement ? [requirement] : []
      end

      sig { params(time: T.any(Integer, Time)).returns(String) }
      def self.formatted_time(time)
        time = Time.at(time) if time.is_a?(Integer)

        time.strftime("%Y-%m-%d at %H:%M:%S")
      end

      sig { params(pin_path: Pathname).returns(T.nilable(Time)) }
      def self.pin_path_mtime(pin_path)
        pin_path.lstat.mtime if pin_path.symlink? || pin_path.exist?
      rescue Errno::ENOENT
        nil
      end

      sig { params(formula: T.untyped).returns(T::Boolean) }
      def self.formula_installs_from_source?(formula)
        return true if formula.stable.blank? && formula.head.present?
        return false if formula.stable.blank?

        !formula.stable.bottled? || !formula.pour_bottle?
      end

      sig {
        params(cask: T.untyped, formula_dependencies: T::Set[String], cask_dependencies: T::Set[String],
               visited_casks: T::Set[String]).void
      }
      def self.collect_cask_dependency_names(cask, formula_dependencies, cask_dependencies, visited_casks)
        cask.depends_on.formula.each do |name|
          dep_name = name.to_s
          formula_dependencies << dep_name
          rack = HOMEBREW_CELLAR/Utils.name_from_full_name(dep_name)
          next unless rack.directory?

          keg = Keg.from_rack(rack)
          next unless keg

          tab_deps = Tab.for_keg(keg).runtime_dependencies
          tab_deps&.each do |runtime_dep|
            dep_full_name = T.cast(runtime_dep, T::Hash[String, T.untyped])["full_name"]
            formula_dependencies << dep_full_name if dep_full_name
          end
        end

        cask.depends_on.cask.each do |name|
          token = name.to_s
          next if visited_casks.include?(token)

          cask_dependencies << token
          visited_casks << token
          begin
            dependency = Cask::CaskLoader.load(token)
            collect_cask_dependency_names(dependency, formula_dependencies, cask_dependencies, visited_casks)
          rescue Cask::CaskUnavailableError
            next
          end
        end
      end

      private_class_method :formula_metadata_lines, :formatted_time, :pin_path_mtime,
                           :formula_installs_from_source?, :cask_requirements_lines

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
            Utils::Analytics.formula_output(obj, args:) if obj.core_formula?
          when Cask::Cask
            Utils::Analytics.cask_output(obj, args:) if obj.tap&.core_cask_tap?
          when FormulaOrCaskUnavailableError
            Utils::Analytics.output(filter: obj.name, args:)
          else
            raise
          end
        end
      end

      sig { params(quiet: T::Boolean).void }
      def print_info(quiet: false)
        objects = args.named.to_formulae_and_casks_and_unavailable(uniq: false)
        user_qualified = args.named.downcased_unique_named.map { |name| name.include?("/") }

        resolved = user_qualified.zip(objects).map do |qualified, obj|
          if obj.is_a?(Formula)
            display_resolution(obj, user_qualified: qualified)
          else
            [obj, nil]
          end
        end

        unique_by_display_name(resolved).each_with_index do |(obj, shadowed_by), i|
          puts unless i.zero?

          if obj.is_a?(FormulaOrCaskUnavailableError)
            # The formula/cask could not be found
            ofail obj.message
            # No formula with this name, try a missing formula lookup
            if (reason = MissingFormula.reason(obj.name, show_info: true))
              $stderr.puts reason
            end
          else
            info_formula_or_cask(obj, quiet:, shadowed_by:)
          end
        end
      end

      sig {
        params(resolved: T::Array[[T.untyped, T.nilable(Tap)]]).returns(T::Array[[T.untyped, T.nilable(Tap)]])
      }
      def unique_by_display_name(resolved)
        resolved.uniq do |obj, _shadowed_by|
          case obj
          when Formula, Cask::Cask then obj.full_name
          else obj
          end
        end
      end

      sig { params(formula: Formula, user_qualified: T::Boolean).returns([Formula, T.nilable(Tap)]) }
      def display_resolution(formula, user_qualified:)
        return [formula, nil] if user_qualified

        installed_resolution(formula)
      end

      sig { params(formula_or_cask: T.any(Formula, Cask::Cask), qualified_inputs: T::Set[String]).returns(T::Boolean) }
      def formula_qualified_by_user?(formula_or_cask, qualified_inputs)
        return false if qualified_inputs.empty?

        names = T.let([formula_or_cask.full_name.downcase], T::Array[String])
        if (tap = formula_or_cask.tap)
          names << "#{tap.name.downcase}/#{Utils.name_or_token(formula_or_cask).downcase}"
        end
        names.any? { |n| qualified_inputs.include?(n) }
      end

      sig { params(formula_or_cask: T.any(Formula, Cask::Cask), quiet: T::Boolean, shadowed_by: T.nilable(Tap)).void }
      def info_formula_or_cask(formula_or_cask, quiet:, shadowed_by: nil)
        case formula_or_cask
        when Formula
          if quiet
            info_formula_summary(formula_or_cask)
          else
            info_formula(formula_or_cask, shadowed_by:)
          end
        when Cask::Cask
          if quiet
            info_cask_summary(formula_or_cask)
          else
            info_cask(formula_or_cask)
          end
        end
      end

      sig { params(formula: Formula).returns([Formula, T.nilable(Tap)]) }
      def installed_resolution(formula)
        keg = formula.installed_kegs.last
        return [formula, nil] if keg.nil?

        installed_tap = keg.tab.tap
        return [formula, nil] if installed_tap.nil? || installed_tap == formula.tap

        [Formulary.factory("#{installed_tap}/#{keg.name}"), formula.tap]
      rescue FormulaUnavailableError, TapFormulaAmbiguityError
        [formula, nil]
      end

      sig { params(formula: Formula).returns(T.nilable(Formula)) }
      def shadowing_installed_formula(formula)
        installed_formula, shadowed_by = installed_resolution(formula)
        installed_formula if shadowed_by
      end

      sig { params(formula: Formula, qualified_inputs: T::Set[String]).returns(Formula) }
      def swap_to_installed_formula(formula, qualified_inputs)
        return formula if formula_qualified_by_user?(formula, qualified_inputs)

        installed_resolution(formula).first
      end

      sig { params(version: T.any(T::Boolean, String)).returns(Symbol) }
      def json_version(version)
        version_hash = {
          true => :default,
          "v1" => :v1,
          "v2" => :v2,
        }

        raise UsageError, "invalid JSON version: #{version}" unless version_hash.include?(version)

        version_hash[version]
      end

      sig { params(json: T.any(T::Boolean, String), eval_all: T::Boolean).void }
      def print_json(json, eval_all)
        raise FormulaOrCaskUnspecifiedError if !(eval_all || args.installed?) && args.no_named?

        qualified_inputs = args.named.select { |name| name.include?("/") }.to_set

        json = case json_version(json)
        when :v1, :default
          raise UsageError, "Cannot specify `--cask` when using `--json=v1`!" if args.cask?

          formulae = if eval_all
            Formula.all(eval_all:).sort
          elsif args.installed?
            Formula.installed.sort
          else
            args.named.to_formulae.map { |f| swap_to_installed_formula(f, qualified_inputs) }
          end

          if args.variations?
            formulae.map(&:to_hash_with_variations)
          else
            formulae.map(&:to_hash)
          end
        when :v2
          formulae, casks = T.let(
            if eval_all
              formulae = [] if args.cask?
              formulae ||= Formula.all(eval_all:).sort
              casks = [] if args.formula?
              casks ||= Cask::Cask.all(eval_all:).sort_by(&:full_name)
              [formulae, casks]
            elsif args.installed?
              formulae = [] if args.cask?
              formulae ||= Formula.installed.sort
              casks = [] if args.formula?
              casks ||= Cask::Caskroom.casks.sort_by(&:full_name)
              [formulae, casks]
            else
              named_formulae, named_casks = T.cast(
                args.named.to_formulae_to_casks, [T::Array[Formula], T::Array[Cask::Cask]]
              )
              [named_formulae.map { |f| swap_to_installed_formula(f, qualified_inputs) }, named_casks]
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

      sig { params(formula_or_cask: T.any(Formula, Cask::Cask)).returns(String) }
      def github_info(formula_or_cask)
        tap = T.let(nil, T.nilable(Tap))
        path = case formula_or_cask
        when Formula
          formula = formula_or_cask
          tap = formula.tap
          return formula.path.to_s if tap.blank? || tap.remote.blank?
          # The formula file may live outside the tap (e.g. loaded from a keg's
          # `.brew/` directory after the formula was removed from its tap), in
          # which case there is no meaningful upstream URL to link to.
          return formula.path.to_s unless formula.path.to_s.start_with?("#{tap.path}/")

          formula.path.relative_path_from(tap.path)
        when Cask::Cask
          cask = formula_or_cask
          tap = cask.tap
          return cask.sourcefile_path.to_s if tap.blank? || tap.remote.blank?

          sourcefile_path = cask.sourcefile_path
          if !sourcefile_path || sourcefile_path.extname != ".rb"
            return "#{tap.default_remote}/blob/HEAD/#{tap.relative_cask_path(cask.token)}"
          end

          sourcefile_path.relative_path_from(tap.path)
        end

        remote = tap.remote
        raise "unexpected nil tap.remote" unless remote

        github_remote_path(remote, path.to_s)
      end

      sig { params(name: String, description: T.nilable(String), installed: T::Boolean).returns(String) }
      def info_summary_title(name, description, installed:)
        name = pretty_installed(name) if installed

        "#{name}#{": #{description}" if description.present?}"
      end

      sig { params(formula: Formula).void }
      def info_formula_summary(formula)
        kegs = formula.installed_kegs
        tab = Tab.for_formula(formula)
        version = kegs.sort_by(&:scheme_and_version)
                      .map { |keg| keg.version.to_s }
                      .join(", ")
        version = "-" if version.blank?

        puts oh1_title(info_summary_title(formula.full_name, formula.desc, installed: kegs.any?))
        if kegs.empty?
          puts "Formula from #{github_info(formula)}"
          puts "Not installed"
        else
          puts "Formula from #{formula.tap&.name ||
                                T.cast(tab.source["tap"], T.nilable(String)) ||
                                T.cast(tab.source["path"], T.nilable(String)) ||
                                github_info(formula)}"
          puts self.class.installation_summary(version, tab)
        end
      end

      sig { params(formula: Formula, shadowed_by: T.nilable(Tap)).void }
      def info_formula(formula, shadowed_by: nil)
        specs = T.let([], T::Array[String])

        if (stable = formula.stable)
          string = "stable #{stable.version}"
          string += " (bottled)" if stable.bottled? && formula.pour_bottle?
          specs << string
        end

        specs << "HEAD" if formula.head

        attrs = []
        attrs << "keg-only" if formula.keg_only?

        shadowing_formula = shadowing_installed_formula(formula)
        kegs = shadowing_formula ? [] : formula.installed_kegs
        installed = kegs.any?
        outdated = installed && formula.outdated?
        missing_libraries, missing_library_deps = formula.missing_library_linkage if installed
        missing_libraries ||= []
        missing_library_deps ||= Set.new
        if outdated && (upgrade_version = specs.first.presence)
          installed_version = formula.linked_version ||
                              kegs.max_by(&:scheme_and_version)&.version
          specs[0] = "#{installed_version} → #{upgrade_version}"
        end
        title_name = if shadowing_formula && (formula_tap = formula.tap)
          "#{formula_tap}/#{formula.name}"
        elsif shadowed_by
          formula.name
        else
          formula.full_name
        end
        name_with_status = pretty_install_status(
          title_name,
          warning:    missing_libraries.present?,
          installed:,
          outdated:,
          deprecated: formula.deprecated?,
          disabled:   formula.disabled?,
          bold:       true,
        )

        puts "#{oh1_title(name_with_status)}: #{specs * ", "}#{" [#{attrs * ", "}]" unless attrs.empty?}"
        if shadowed_by
          puts Formatter.warning(
            "`#{formula.name}` shadows `#{shadowed_by.name}/#{formula.name}`.",
            label: "Warning",
          )
        end
        puts formula.desc if formula.desc
        puts Formatter.url(formula.homepage) if formula.homepage
        puts "Aliases: #{formula.aliases.join(", ")}" if formula.aliases.any?
        puts "Old Names: #{formula.oldnames.join(", ")}" if formula.oldnames.any?

        deprecate_disable_info_string = DeprecateDisable.message(formula)
        if deprecate_disable_info_string.present?
          deprecate_disable_info_string.tap { |info_string| info_string[0] = info_string[0].upcase }
          puts deprecate_disable_info_string
        end

        conflicts = formula.conflicts.filter_map do |conflict|
          resolved = begin
            Formulary.factory(conflict.name)
          rescue FormulaUnavailableError
            nil
          end
          next if resolved && resolved.full_name == formula.full_name

          conflict_name = resolved&.full_name || conflict.name
          reason = " (because #{conflict.reason})" if conflict.reason
          "#{conflict_name}#{reason}"
        end.sort!
        unless conflicts.empty?
          puts <<~EOS
            Conflicts with:
              #{conflicts.join("\n  ")}
          EOS
        end

        heads, versioned = kegs.partition { |keg| keg.version.head? }
        kegs = [
          *heads.sort_by { |keg| -keg.tab.time.to_i },
          *versioned.sort_by(&:scheme_and_version),
        ]
        if kegs.empty?
          puts "Not installed"
          if (bottle = formula.bottle)
            begin
              bottle.fetch_tab(quiet: !args.debug?) if args.fetch_manifest? || args.verbose?
              bottle_size = bottle.bottle_size
              installed_size = bottle.installed_size
              puts "Bottle Size: #{Formatter.disk_usage_readable(bottle_size)}" if bottle_size
              puts "Installed Size: #{Formatter.disk_usage_readable(installed_size)}" if installed_size
            rescue RuntimeError => e
              odebug e
            end
          end
        else
          puts self.class.installation_status(Tab.for_formula(formula))
        end

        puts "From: #{Formatter.url(github_info(formula))}"
        formula_tap = formula.tap
        puts "Tap: #{formula_tap.name}" if formula_tap && !formula_tap.official?

        puts "License: #{SPDX.license_expression_to_string formula.license}" if formula.license.present?
        metadata = self.class.metadata_lines(formula)
        puts metadata if metadata.present?

        installed_lines = installed_section_lines(shadowing_formula || formula, verbose: args.verbose?)
        unless installed_lines.empty?
          ohai(args.verbose? ? "Installed Kegs and Versions" : "Installed Versions")
          installed_lines.each { |line| puts line }
        end

        tab_runtime_deps = kegs.last&.runtime_dependencies
        installed_dependents = if $stdout.tty? && kegs.any?
          self.class.installed_dependent_names(formula.full_name, formula.name)
        else
          [].freeze
        end
        dependency_lines = %w[build required recommended optional].filter_map do |type|
          next if type == "build" &&
                  (kegs.all? { |keg| keg.tab.poured_from_bottle } ||
                   (kegs.empty? &&
                    (formula.requirements.any? { |requirement| self.class.requirement_for_other_os?(requirement) } ||
                     (stable.present? ? stable.bottled? && formula.pour_bottle? : formula.head.blank?))))

          deps = formula.deps.send(type).uniq
          next if deps.empty?

          tab_deps = (kegs.any? && type != "build") ? tab_runtime_deps : nil
          "#{type.capitalize} (#{deps.count}): " \
            "#{decorate_dependencies(deps, tab_runtime_deps: tab_deps, mark_uninstalled: kegs.any?,
                                     missing_library_deps:)}"
        end
        if dependency_lines.present? || tab_runtime_deps.present? || installed_dependents.any?
          ohai "Dependencies"
          puts dependency_lines
          missing_library_names = missing_libraries.map { |lib| File.basename(lib) }.uniq
          if missing_library_names.present?
            decorated = missing_library_names.map { |lib| pretty_uninstalled(lib, bold: false) }.join(", ")
            puts "Missing libraries (#{missing_library_names.count}): #{decorated}"
          end
          if tab_runtime_deps.present?
            installed_count = tab_runtime_deps.count do |dep|
              dep_name = dep["full_name"]&.then { Utils.name_from_full_name(it) }
              next false unless dep_name

              rack = HOMEBREW_CELLAR/dep_name
              rack.directory? && !rack.subdirs.empty?
            end
            puts "Recursive Runtime (#{tab_runtime_deps.count}): " \
                 "#{self.class.dependency_status_counts(installed_count, tab_runtime_deps.count)}"
          end
          if installed_dependents.any?
            if args.verbose?
              puts "Dependents (#{installed_dependents.count}): #{installed_dependents.join(", ")}"
            else
              puts "Dependents: #{installed_dependents.count}"
            end
          end
        end

        unless formula.requirements.to_a.empty?
          ohai "Requirements"
          %w[build required recommended optional].map do |type|
            reqs = formula.requirements.select(&:"#{type}?")
            next if reqs.to_a.empty?

            puts "#{type.capitalize}: #{decorate_requirements(reqs, mark_uninstalled: kegs.any?)}"
          end
        end

        if !formula.options.empty? || formula.head
          ohai "Options"
          Options.dump_for_formula formula
        end

        if args.verbose?
          binaries_keg = kegs.find(&:linked?) || kegs.last
          binaries = if binaries_keg
            binary_files = [binaries_keg/"bin", binaries_keg/"sbin"].select(&:directory?).flat_map do |dir|
              dir.children.select { |child| child.file? && child.executable? }
            end
            binary_files.map { |path| path.basename.to_s }
          elsif (path_exec_files = formula.bottle&.path_exec_files)
            path_exec_files.map { |path| File.basename(path) }
          end
          if binaries.present?
            binaries = binaries.sort.uniq
            ohai "Binaries", Formatter.columns(binaries)
          end
        end

        caveats = Caveats.new(formula)
        if (caveats_string = caveats.to_s.presence)
          ohai "Caveats", caveats_string
        end

        return unless formula.core_formula?

        Utils::Analytics.formula_output(formula, args:)
      end

      sig { params(formula: Formula, verbose: T::Boolean).returns(T::Array[String]) }
      def installed_section_lines(formula, verbose: false)
        siblings = formula.versioned_formulae
        parent = if (parent_name = formula.unversioned_formula_name)
          begin
            Formulary.factory(parent_name)
          rescue FormulaUnavailableError
            nil
          end
        end
        related = [formula, parent, *siblings].compact.uniq(&:full_name)
        installed = related.select { |f| f.installed_kegs.any? }
        return [] if installed.empty?

        ordered = installed.sort_by do |other|
          newest_keg = other.installed_kegs.max_by(&:scheme_and_version)
          newest_keg ? newest_keg.scheme_and_version : other.pkg_version
        end.reverse
        with_kegs = ordered.flat_map do |other|
          heads, versioned = other.installed_kegs.partition { |keg| keg.version.head? }
          ordered_kegs = [
            *heads.sort_by { |keg| -keg.tab.time.to_i },
            *versioned.sort_by(&:scheme_and_version).reverse,
          ]
          ordered_kegs.each_with_index.map { |keg, index| [other, keg, index.zero?] }
        end
        with_kegs = with_kegs.select { |_other, keg, newest| newest || keg.linked? } unless verbose
        rows = with_kegs.map do |other, keg, newest|
          name_status = pretty_install_status(other.full_name, installed: true, outdated: other.outdated?)
          version = keg.version.to_s
          latest = other.pkg_version.to_s
          version = "#{version} → #{latest}" if newest && other.outdated? && latest != version
          linked_marker = keg.linked? ? "[Linked]" : ""
          [name_status, version, "(#{keg.abv})", linked_marker, keg]
        end
        name_width = rows.map { |r| Tty.strip_ansi(r[0]).length }.max || 0
        version_width = rows.map { |r| r[1].length }.max || 0
        size_width = rows.map { |r| r[2].length }.max || 0
        rows.flat_map do |name_status, version, size, linked_marker, keg|
          padded_name = name_status + (" " * (name_width - Tty.strip_ansi(name_status).length))
          padded_size = linked_marker.empty? ? size : size.ljust(size_width)
          line = "#{padded_name} #{version.ljust(version_width)} #{padded_size}" \
                 "#{" #{linked_marker}" unless linked_marker.empty?}"
          next [line] unless verbose

          tab_string = keg.tab.to_s
          tab_string.empty? ? [line] : [line, "  #{tab_string}"]
        end
      end

      sig {
        params(dependencies:         T::Array[Dependency],
               tab_runtime_deps:     T.nilable(T::Array[T::Hash[String, T.untyped]]),
               mark_uninstalled:     T::Boolean,
               missing_library_deps: T::Set[String]).returns(String)
      }
      def decorate_dependencies(dependencies, tab_runtime_deps: nil, mark_uninstalled: true,
                                missing_library_deps: Set.new)
        dependencies.map do |dep|
          display = dep_display_s(dep)
          full_name = tab_runtime_deps&.find do |d|
            name = d["full_name"]
            name == dep.name || name&.then { Utils.name_from_full_name(it) } == dep.name
          end&.fetch("full_name") || dep.name
          rack = HOMEBREW_CELLAR/Utils.name_from_full_name(full_name)
          installed = T.let(rack.directory? && !rack.subdirs.empty?, T::Boolean)
          formula = begin
            dep.to_formula
          rescue FormulaUnavailableError, TapFormulaAmbiguityError
            nil
          end
          installed ||= formula.any_version_installed? if !installed && formula
          outdated = T.let(installed && formula&.outdated? == true, T::Boolean)
          warning = missing_library_deps.include?(Utils.name_from_full_name(dep.name))
          pretty_install_status(display, warning:, installed:, outdated:, mark_uninstalled:, bold: true)
        end.join(", ")
      end

      sig { params(requirements: T::Array[Requirement], mark_uninstalled: T::Boolean).returns(String) }
      def decorate_requirements(requirements, mark_uninstalled: true)
        req_status = requirements.map do |req|
          req_s = req.display_s
          pretty_install_status(req_s, installed: req.satisfied?, mark_uninstalled:, bold: true)
        end
        req_status.join(", ")
      end

      sig { params(dep: Dependency).returns(String) }
      def dep_display_s(dep)
        return dep.name if dep.option_tags.empty?

        "#{dep.name} #{dep.option_tags.map { |o| "--#{o}" }.join(" ")}"
      end

      sig { params(cask: Cask::Cask).void }
      def info_cask(cask)
        require "cask/info"

        Cask::Info.info(cask, args:)
      end

      sig { params(cask: Cask::Cask).void }
      def info_cask_summary(cask)
        installed_version = cask.installed_version
        installed = installed_version.present?
        tab = Cask::Tab.for_cask(cask)

        puts oh1_title(info_summary_title(
                         cask.full_name,
                         cask.desc.presence&.then do |desc|
                           "#{if cask.name.present?
                                "(#{cask.name.join(", ")}) "
                           end}#{desc}"
                         end,
                         installed:,
                       ))
        if installed
          puts "Cask from #{T.cast(cask.tap, T.nilable(Tap))&.name ||
                             T.cast(tab.source["tap"], T.nilable(String)) ||
                             cask.sourcefile_path&.to_s ||
                             T.cast(tab.source["path"], T.nilable(String)) ||
                             github_info(cask)}"
          puts self.class.installation_summary(installed_version, tab)
        else
          puts "Cask from #{github_info(cask)}"
          puts "Not installed"
        end
      end

      sig { params(title: String, items: T::Array[NameSize]).void }
      def print_sizes_table(title, items)
        return if items.blank?

        ohai title

        total_size = items.sum(&:size)
        total_size_str = Formatter.disk_usage_readable(total_size)

        name_width = (items.map { |item| item.name.length } + [5]).max
        size_width = (items.map do |item|
          Formatter.disk_usage_readable(item.size).length
        end + [total_size_str.length]).max

        items.each do |item|
          puts format("%-#{name_width}s %#{size_width}s", item.name,
                      Formatter.disk_usage_readable(item.size))
        end

        puts format("%-#{name_width}s %#{size_width}s", "Total", total_size_str)
      end

      sig { params(formulae: T::Array[Formula], casks: T::Array[Cask::Cask]).void }
      def print_sizes(formulae: [], casks: [])
        if formulae.blank? &&
           (args.formulae? || (!args.casks? && args.no_named?))
          formulae = Formula.installed
        end

        if casks.blank? &&
           (args.casks? || (!args.formulae? && args.no_named?))
          casks = Cask::Caskroom.casks
        end

        unless args.casks?
          formula_sizes = formulae.map do |formula|
            kegs = formula.installed_kegs
            size = kegs.sum(&:disk_usage)
            NameSize.new(name: formula.full_name, size:)
          end
          formula_sizes.sort_by! { |f| -f.size }
          print_sizes_table("Formulae sizes:", formula_sizes)
        end

        return if casks.blank? || args.formulae?

        cask_sizes = casks.filter_map do |cask|
          installed_version = cask.installed_version
          next unless installed_version.present?

          versioned_staged_path = cask.caskroom_path.join(installed_version)
          next unless versioned_staged_path.exist?

          size = versioned_staged_path.children.sum(&:disk_usage)
          NameSize.new(name: cask.full_name, size:)
        end
        cask_sizes.sort_by! { |c| -c.size }
        print_sizes_table("Casks sizes:", cask_sizes)
      end
    end
  end
end

require "extend/os/cmd/info"
