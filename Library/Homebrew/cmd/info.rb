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
                            "JSON."
        switch "--variations",
               depends_on:  "--json",
               description: "Include the variations hash in each formula's JSON output."
        switch "-v", "--verbose",
               description: "Show more verbose analytics data for <formula>."
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
          print_json(json, args.eval_all?)
        elsif args.github?
          raise FormulaOrCaskUnspecifiedError if args.no_named?

          exec_browser(*args.named.to_formulae_and_casks.map do |formula_keg_or_cask|
            formula_or_cask = T.cast(formula_keg_or_cask, T.any(Formula, Cask::Cask))
            github_info(formula_or_cask)
          end)
        elsif args.no_named?
          print_statistics
        else
          print_info
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

      sig { params(formula_or_cask: T.untyped).returns(T::Array[String]) }
      def self.metadata_lines(formula_or_cask)
        return [] unless $stdout.tty?

        if formula_or_cask.is_a?(Formula) || formula_or_cask.respond_to?(:pinned?)
          formula_metadata_lines(formula_or_cask)
        elsif formula_or_cask.is_a?(Cask::Cask) || formula_or_cask.respond_to?(:supports_macos?)
          []
        else
          raise TypeError, "Unsupported formula_or_cask type: #{formula_or_cask.class}"
        end
      end

      sig { params(formula_or_cask: T.untyped).returns(T::Array[String]) }
      def self.requirements_lines(formula_or_cask)
        return [] unless $stdout.tty?
        return [] if formula_or_cask.is_a?(Formula) || formula_or_cask.respond_to?(:pinned?)
        if formula_or_cask.is_a?(Cask::Cask) || formula_or_cask.respond_to?(:supports_macos?)
          return cask_requirements_lines(formula_or_cask)
        end

        raise TypeError,
              "Unsupported formula_or_cask type: #{formula_or_cask.class}"
      end

      sig { params(tab: T.any(Tab, Cask::Tab)).returns(String) }
      def self.installation_status(tab)
        # TODO: Deprecate reading `installed_as_dependency`; `installed_on_request`
        # is the only state we need to render install intent.
        tab.installed_on_request ? "Installed (on request)" : "Installed (as dependency)"
      end

      sig { params(requirement: Requirement).returns(T::Boolean) }
      def self.requirement_for_other_os?(requirement)
        requirement.instance_of?(MacOSRequirement) || requirement.instance_of?(LinuxRequirement)
      end

      sig { params(installed_count: Integer, total_count: Integer).returns(String) }
      def self.dependency_status_counts(installed_count, total_count)
        "#{installed_count} #{Formatter.success("✔")}, " \
          "#{total_count - installed_count} #{Formatter.error("✘")}"
      end

      sig { params(full_name: String, name: String).returns(Integer) }
      def self.count_installed_dependents(full_name, name)
        Formula.racks.count do |rack|
          keg = Keg.from_rack(rack)
          next false unless keg

          tab_path = keg/AbstractTab::FILENAME
          next false unless tab_path.file?

          # Fast path: skip JSON parsing when the formula name
          # does not appear anywhere in the raw receipt.
          content = File.read(tab_path)
          next false unless content.include?(name)

          tab_deps = Tab.from_file_content(content, tab_path).runtime_dependencies
          next false unless tab_deps

          tab_deps.any? do |dep|
            dep_full_name = T.cast(dep, T::Hash[String, T.untyped])["full_name"]
            dep_full_name == full_name || dep_full_name&.split("/")&.last == name
          end
        end
      end

      sig { params(formula: T.untyped).returns(T::Array[String]) }
      def self.formula_metadata_lines(formula)
        metadata = T.let([], T::Array[String])
        if formula.pinned?
          pinned = "Pinned: #{formula.pinned_version}"
          if (pinned_time = formula_pinned_time(formula))
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

      sig { params(cask: T.untyped).returns(T::Array[String]) }
      def self.cask_requirements_lines(cask)
        requirement = if (macos = cask.depends_on.macos)
          requirement = macos.display_s
          if cask.supports_linux?
            requirement.sub(" (or Linux)",
                            " or Linux")
          else
            requirement.delete_suffix(" (or Linux)")
          end
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

      sig { params(formula: T.untyped).returns(T.nilable(Time)) }
      def self.formula_pinned_time(formula)
        pin_path = FormulaPin.new(formula).path
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
          rack = HOMEBREW_CELLAR/dep_name.split("/").last
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

      private_class_method :formula_metadata_lines, :formatted_time, :formula_pinned_time,
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

        json = case json_version(json)
        when :v1, :default
          raise UsageError, "Cannot specify `--cask` when using `--json=v1`!" if args.cask?

          formulae = if eval_all
            Formula.all(eval_all:).sort
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
            if eval_all
              [
                Formula.all(eval_all:).sort,
                Cask::Cask.all(eval_all:).sort_by(&:full_name),
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

      sig { params(formula_or_cask: T.any(Formula, Cask::Cask)).returns(String) }
      def github_info(formula_or_cask)
        tap = T.let(nil, T.nilable(Tap))
        path = case formula_or_cask
        when Formula
          formula = formula_or_cask
          tap = formula.tap
          return formula.path.to_s if tap.blank? || tap.remote.blank?

          formula.path.relative_path_from(tap.path)
        when Cask::Cask
          cask = formula_or_cask
          tap = cask.tap
          return cask.sourcefile_path.to_s if tap.blank? || tap.remote.blank?

          sourcefile_path = cask.sourcefile_path
          if sourcefile_path.blank? || sourcefile_path.extname != ".rb"
            return "#{tap.default_remote}/blob/HEAD/#{tap.relative_cask_path(cask.token)}"
          end

          sourcefile_path.relative_path_from(tap.path)
        end

        remote = tap.remote
        raise "unexpected nil tap.remote" unless remote

        github_remote_path(remote, path.to_s)
      end

      sig { params(formula: Formula).void }
      def info_formula(formula)
        specs = []

        if (stable = formula.stable)
          string = "stable #{stable.version}"
          string += " (bottled)" if stable.bottled? && formula.pour_bottle?
          specs << string
        end

        specs << "HEAD" if formula.head

        attrs = []
        attrs << "keg-only" if formula.keg_only?

        kegs = formula.installed_kegs
        name_with_status = if kegs.empty?
          pretty_uninstalled(formula.full_name)
        else
          pretty_installed(formula.full_name)
        end

        puts "#{oh1_title(name_with_status)}: #{specs * ", "}#{" [#{attrs * ", "}]" unless attrs.empty?}"
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
              puts "Bottle Size: #{Formatter.disk_usage_readable(bottle_size)}" if bottle_size
              puts "Installed Size: #{Formatter.disk_usage_readable(installed_size)}" if installed_size
            rescue RuntimeError => e
              odebug e
            end
          end
        else
          puts self.class.installation_status(Tab.for_formula(formula))
          kegs.each do |keg|
            puts "#{keg} (#{keg.abv})#{" *" if keg.linked?}"
            tab = keg.tab.to_s
            puts "  #{tab}" unless tab.empty?
          end
        end

        puts "From: #{Formatter.url(github_info(formula))}"

        puts "License: #{SPDX.license_expression_to_string formula.license}" if formula.license.present?
        metadata = self.class.metadata_lines(formula)
        puts metadata if metadata.present?

        tab_runtime_deps = kegs.last&.runtime_dependencies
        installed_dependents = if $stdout.tty? && kegs.any?
          self.class.count_installed_dependents(formula.full_name, formula.name)
        else
          0
        end
        dependency_lines = %w[build required recommended optional].filter_map do |type|
          next if type == "build" &&
                  (kegs.all? { |keg| keg.tab.poured_from_bottle } ||
                   (kegs.empty? &&
                    (formula.requirements.any? { |requirement| self.class.requirement_for_other_os?(requirement) } ||
                     (stable.present? ? stable.bottled? && formula.pour_bottle? : formula.head.blank?))))

          deps = formula.deps.send(type).uniq
          "#{type.capitalize} (#{deps.count}): #{decorate_dependencies deps}" unless deps.empty?
        end
        if dependency_lines.present? || tab_runtime_deps.present? || installed_dependents.positive?
          ohai "Dependencies"
          puts dependency_lines
          if tab_runtime_deps.present?
            installed_count = tab_runtime_deps.count do |dep|
              dep_name = dep["full_name"]&.split("/")&.last
              next false unless dep_name

              rack = HOMEBREW_CELLAR/dep_name
              rack.directory? && !rack.subdirs.empty?
            end
            puts "Recursive Runtime (#{tab_runtime_deps.count}): " \
                 "#{self.class.dependency_status_counts(installed_count, tab_runtime_deps.count)}"
          end
          puts "Dependents: #{installed_dependents}" if installed_dependents.positive?
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
        if (caveats_string = caveats.to_s.presence)
          ohai "Caveats", caveats_string
        end

        return unless formula.core_formula?

        Utils::Analytics.formula_output(formula, args:)
      end

      sig { params(dependencies: T::Array[Dependency]).returns(String) }
      def decorate_dependencies(dependencies)
        deps_status = dependencies.map do |dep|
          if dep.satisfied?
            pretty_installed(dep_display_s(dep))
          else
            pretty_uninstalled(dep_display_s(dep))
          end
        end
        deps_status.join(", ")
      end

      sig { params(requirements: T::Array[Requirement]).returns(String) }
      def decorate_requirements(requirements)
        req_status = requirements.map do |req|
          req_s = req.display_s
          req.satisfied? ? pretty_installed(req_s) : pretty_uninstalled(req_s)
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
