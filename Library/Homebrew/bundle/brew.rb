# typed: strict
# frozen_string_literal: true

require "json"
require "tsort"
require "utils"
require "utils/output"
require "bundle/package_type"

module Homebrew
  module Bundle
    class Brew < Homebrew::Bundle::PackageType
      extend Utils::Output::Mixin

      PACKAGE_TYPE = :brew
      PACKAGE_TYPE_NAME = "Formula"

      class << self
        sig { override.params(subclass: T.class_of(Homebrew::Bundle::PackageType)).void }
        def inherited(subclass)
          return if subclass.name == "Homebrew::Bundle::Brew::Services"

          super
        end

        sig { override.void }
        def reset!
          require "bundle/brew_services"

          Homebrew::Bundle::Brew::Services.reset!
          @installed_formulae = T.let(nil, T.nilable(T::Array[String]))
          @outdated_formulae = T.let(nil, T.nilable(T::Array[String]))
          @pinned_formulae = T.let(nil, T.nilable(T::Array[String]))
          @formulae = T.let(nil, T.nilable(T::Array[T::Hash[Symbol, T.untyped]]))
          @formulae_by_full_name = T.let(nil, T.nilable(T::Hash[String, T::Hash[Symbol, T.untyped]]))
          @formulae_by_name = T.let(nil, T.nilable(T::Hash[String, T::Hash[Symbol, T.untyped]]))
          @formula_aliases = T.let(nil, T.nilable(T::Hash[String, String]))
          @formula_oldnames = T.let(nil, T.nilable(T::Hash[String, String]))
        end

        sig { override.params(name: String, no_upgrade: T::Boolean, verbose: T::Boolean, options: T.untyped).returns(T::Boolean) }
        def preinstall!(name, no_upgrade: false, verbose: false, **options)
          new(name, options).preinstall!(no_upgrade:, verbose:)
        end

        sig {
          override.params(name: String, preinstall: T::Boolean, no_upgrade: T::Boolean, verbose: T::Boolean,
                          force: T::Boolean, options: T.untyped).returns(T::Boolean)
        }
        def install!(name, preinstall: true, no_upgrade: false, verbose: false, force: false, **options)
          new(name, options).install!(preinstall:, no_upgrade:, verbose:, force:)
        end

        # Override makes `name` a required argument unlike the parent's default-argument signature.
        # rubocop:disable Sorbet/AllowIncompatibleOverride
        sig {
          override(allow_incompatible: true).params(name: String, options: Homebrew::Bundle::EntryOptions).returns(String)
        }
        # rubocop:enable Sorbet/AllowIncompatibleOverride
        def install_verb(name, options = {})
          _ = options

          return "Installing" unless formula_upgradable?(name)

          "Upgrading"
        end

        sig { params(formula: String, no_upgrade: T::Boolean).returns(T::Boolean) }
        def formula_installed_and_up_to_date?(formula, no_upgrade: false)
          return false unless formula_installed?(formula)
          return true if no_upgrade_with_args?(no_upgrade, formula)

          !formula_upgradable?(formula)
        end

        sig { params(no_upgrade: T::Boolean, formula_name: String).returns(T::Boolean) }
        def no_upgrade_with_args?(no_upgrade, formula_name)
          no_upgrade && Bundle.upgrade_formulae.exclude?(formula_name)
        end

        sig { params(formula: String, array: T::Array[String]).returns(T::Boolean) }
        def formula_in_array?(formula, array)
          return true if array.include?(formula)
          return true if array.include?(Utils.name_from_full_name(formula))

          old_name = formula_oldnames[formula]
          old_name ||= formula_oldnames[Utils.name_from_full_name(formula)]
          return true if old_name && array.include?(old_name)

          resolved_full_name = formula_aliases[formula]
          return false unless resolved_full_name
          return true if array.include?(resolved_full_name)
          return true if array.include?(Utils.name_from_full_name(resolved_full_name))

          false
        end

        sig { params(formula: String).returns(T::Boolean) }
        def formula_installed?(formula)
          formula_in_array?(formula, installed_formulae)
        end

        sig { params(formula: String).returns(T::Boolean) }
        def formula_upgradable?(formula)
          # Check local cache first and then authoritative Homebrew source.
          (formula_in_array?(formula, upgradable_formulae) && Formula[formula].outdated?) || false
        end

        sig { returns(T::Array[String]) }
        def installed_formulae
          @installed_formulae ||= formulae.map { |f| f[:name] }
        end

        sig { returns(T::Array[String]) }
        def upgradable_formulae
          outdated_formulae - pinned_formulae
        end

        sig { returns(T::Array[String]) }
        def outdated_formulae
          @outdated_formulae ||= formulae.filter_map { |f| f[:name] if f[:outdated?] }
        end

        sig { returns(T::Array[String]) }
        def pinned_formulae
          @pinned_formulae ||= formulae.filter_map { |f| f[:name] if f[:pinned?] }
        end

        sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
        def formulae
          return @formulae if @formulae

          formulae_by_full_name
          # formulae_by_full_name sets @formulae as a side effect of calling sort!
          T.cast(@formulae, T::Array[T::Hash[Symbol, T.untyped]])
        end

        # Returns the full `@formulae_by_full_name` map when called without a name,
        # or a single formula's attribute hash when called with a name.
        sig {
          params(name: T.nilable(String)).returns(
            T.nilable(T.any(T::Hash[Symbol, T.untyped], T::Hash[String, T::Hash[Symbol, T.untyped]])),
          )
        }
        def formulae_by_full_name(name = nil)
          return @formulae_by_full_name[name] if name.present? && @formulae_by_full_name&.key?(name)

          require "formula"
          require "formulary"
          Formulary.enable_factory_cache!

          @formulae_by_name ||= {}
          @formulae_by_full_name ||= {}

          if name.nil?
            formulae = Formula.installed.map { add_formula(it) }
            sort!(formulae)
            return @formulae_by_full_name
          end

          formula = Formula[name]
          add_formula(formula)
        rescue FormulaUnavailableError => e
          opoo "'#{name}' formula is unreadable: #{e}"
          {}
        end

        sig { params(name: String).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
        def formulae_by_name(name)
          T.cast(formulae_by_full_name(name), T.nilable(T::Hash[Symbol, T.untyped])) || @formulae_by_name&.[](name)
        end

        sig { override.params(describe: T::Boolean, no_restart: T::Boolean).returns(String) }
        def dump(describe: false, no_restart: false)
          require "bundle/brew_services"

          requested_formula = formulae.select do |f|
            f[:installed_on_request?] || !f[:installed_as_dependency?]
          end
          requested_formula.map do |f|
            brewline = if describe && f[:desc].present?
              f[:desc].split("\n").map { |s| "# #{s}\n" }.join
            else
              ""
            end
            brewline += "brew \"#{f[:full_name]}\""

            args = f[:args].map { |arg| "\"#{arg}\"" }.sort.join(", ")
            brewline += ", args: [#{args}]" unless f[:args].empty?
            brewline += ", restart_service: :changed" if !no_restart && Services.started?(f[:full_name])
            brewline += ", link: #{f[:link?]}" unless f[:link?].nil?
            brewline
          end.join("\n")
        end

        sig { override.params(describe: T::Boolean, no_restart: T::Boolean).returns(String) }
        def dump_output(describe: false, no_restart: false)
          dump(describe:, no_restart:)
        end

        sig { override.params(name: String, options: T::Hash[Symbol, T.untyped], no_upgrade: T::Boolean).returns(T.nilable(String)) }
        def fetchable_name(name, options = {}, no_upgrade: false)
          _ = options

          return if (tap_name = Utils.tap_from_full_name(name)) &&
                    Homebrew::Bundle::Tap.installed_taps.exclude?(tap_name)
          return if formula_installed_and_up_to_date?(name, no_upgrade:)

          name
        end

        sig { returns(T::Hash[String, String]) }
        def formula_aliases
          return @formula_aliases if @formula_aliases

          @formula_aliases = {}
          formulae.each do |f|
            aliases = f[:aliases]
            next if aliases.blank?

            aliases.each do |a|
              @formula_aliases[a] = f[:full_name]
              if (tap_name = Utils.tap_from_full_name(f[:full_name]))
                @formula_aliases["#{tap_name}/#{a}"] = f[:full_name]
              end
            end
          end
          @formula_aliases
        end

        sig { returns(T::Hash[String, String]) }
        def formula_oldnames
          return @formula_oldnames if @formula_oldnames

          @formula_oldnames = {}
          formulae.each do |f|
            oldnames = f[:oldnames]
            next if oldnames.blank?

            oldnames.each do |oldname|
              @formula_oldnames[oldname] = f[:full_name]
              if (tap_name = Utils.tap_from_full_name(f[:full_name]))
                @formula_oldnames["#{tap_name}/#{oldname}"] = f[:full_name]
              end
            end
          end
          @formula_oldnames
        end

        private

        sig { params(formula: Formula).returns(T::Hash[Symbol, T.untyped]) }
        def add_formula(formula)
          hash = formula_to_hash formula

          raise "formulae_by_name is nil" if @formulae_by_name.nil?
          raise "formulae_by_full_name is nil" if @formulae_by_full_name.nil?

          @formulae_by_name[hash[:name]] = hash
          @formulae_by_full_name[hash[:full_name]] = hash

          hash
        end

        sig { params(formula: Formula).returns(T::Hash[Symbol, T.untyped]) }
        def formula_to_hash(formula)
          keg = if formula.linked?
            link = true if formula.keg_only?
            formula.linked_keg
          else
            link = false unless formula.keg_only?
            formula.any_installed_prefix
          end

          if keg
            require "tab"

            tab = Tab.for_keg(keg)
            args = tab.used_options.map(&:name)
            version = begin
              keg.realpath.basename
            rescue
              # silently handle broken symlinks
              nil
            end.to_s
            args << "HEAD" if version.start_with?("HEAD")
            installed_as_dependency = tab.installed_as_dependency
            installed_on_request = tab.installed_on_request
            runtime_dependencies = if (runtime_deps = tab.runtime_dependencies)
              runtime_deps.filter_map { |d| d["full_name"] }

            end
            poured_from_bottle = tab.poured_from_bottle
          end

          runtime_dependencies ||= formula.runtime_dependencies.map(&:name)

          bottled = if (stable = formula.stable) && stable.bottle_defined?
            bottle_hash = formula.bottle_hash.deep_symbolize_keys
            stable.bottled?
          end

          {
            name:                     formula.name,
            desc:                     formula.desc,
            oldnames:                 formula.oldnames,
            full_name:                formula.full_name,
            aliases:                  formula.aliases,
            any_version_installed?:   formula.any_version_installed?,
            args:                     Array(args).uniq,
            version:,
            installed_as_dependency?: installed_as_dependency || false,
            installed_on_request?:    installed_on_request || false,
            dependencies:             runtime_dependencies,
            build_dependencies:       formula.deps.select(&:build?).map(&:name).uniq,
            conflicts_with:           formula.conflicts.map(&:name),
            pinned?:                  formula.pinned? || false,
            outdated?:                formula.outdated? || false,
            link?:                    link,
            poured_from_bottle?:      poured_from_bottle || false,
            bottle:                   bottle_hash || false,
            bottled:                  bottled || false,
            official_tap:             formula.tap&.official? || false,
          }
        end

        sig { params(formulae: T::Array[T::Hash[Symbol, T.untyped]]).void }
        def sort!(formulae)
          # Step 1: Sort by formula full name while putting tap formulae behind core formulae.
          #         So we can have a nicer output.
          formulae = formulae.sort do |a, b|
            if a[:full_name].exclude?("/") && b[:full_name].include?("/")
              -1
            elsif a[:full_name].include?("/") && b[:full_name].exclude?("/")
              1
            else
              a[:full_name] <=> b[:full_name]
            end
          end

          # Step 2: Sort by formula dependency topology.
          topo = Topo.new
          formulae.each do |f|
            topo[f[:name]] = topo[f[:full_name]] = f[:dependencies].filter_map do |dep|
              ff = formulae_by_name(dep)
              next if ff.blank?
              next unless ff[:any_version_installed?]

              ff[:full_name]
            end
          end

          raise "formulae_by_full_name is nil" if @formulae_by_full_name.nil?
          raise "formulae_by_name is nil" if @formulae_by_name.nil?

          @formulae = topo.tsort
                          .map { |name| @formulae_by_full_name[name] || @formulae_by_name[name] }
                          .uniq { |f| f[:full_name] }
        rescue TSort::Cyclic => e
          e.message =~ /\["([^"]*)".*"([^"]*)"\]/
          cycle_first = Regexp.last_match(1)
          cycle_last = Regexp.last_match(2)
          odie e.message if !cycle_first || !cycle_last

          odie <<~EOS
            Formulae dependency graph sorting failed (likely due to a circular dependency):
            #{cycle_first}: #{topo[cycle_first] if topo}
            #{cycle_last}: #{topo[cycle_last] if topo}
            Please run the following commands and try again:
              brew update
              brew uninstall --ignore-dependencies --force #{cycle_first} #{cycle_last}
              brew install #{cycle_first} #{cycle_last}
          EOS
        end
      end

      sig { params(name: String, options: T::Hash[Symbol, T.untyped]).void }
      def initialize(name = "", options = {})
        super()
        @full_name = name
        @name = T.let(Utils.name_from_full_name(name), String)
        @args = T.let(options.fetch(:args, []).map { |arg| "--#{arg}" }, T::Array[String])
        @conflicts_with_arg = T.let(options.fetch(:conflicts_with, []), T::Array[String])
        @restart_service = T.let(options[:restart_service], T.nilable(T.any(Symbol, T::Boolean)))
        @start_service = T.let(options.fetch(:start_service, @restart_service), T.nilable(T.any(Symbol, T::Boolean)))
        @link = T.let(options.fetch(:link, nil), T.nilable(T.any(Symbol, T::Boolean)))
        @postinstall = T.let(options.fetch(:postinstall, nil), T.nilable(String))
        @version_file = T.let(options.fetch(:version_file, nil), T.nilable(String))
        @changed = T.let(nil, T.nilable(T::Boolean))
      end

      sig { override.params(formula: Object, no_upgrade: T::Boolean).returns(T::Boolean) }
      def installed_and_up_to_date?(formula, no_upgrade: false)
        raise "formula must be a String, got #{formula.class}: #{formula}" unless formula.is_a?(String)

        self.class.formula_installed_and_up_to_date?(formula, no_upgrade:)
      end

      sig { params(no_upgrade: T::Boolean, verbose: T::Boolean).returns(T::Boolean) }
      def preinstall!(no_upgrade: false, verbose: false)
        if installed? && (self.class.no_upgrade_with_args?(no_upgrade, @name) || !upgradable?)
          puts "Skipping install of #{@name} formula. It is already installed." if verbose
          @changed = nil
          return false
        end

        true
      end

      sig { params(preinstall: T::Boolean, no_upgrade: T::Boolean, verbose: T::Boolean, force: T::Boolean).returns(T::Boolean) }
      def install!(preinstall: true, no_upgrade: false, verbose: false, force: false)
        install_result = if preinstall
          install_change_state!(no_upgrade:, verbose:, force:)
        else
          true
        end
        result = install_result

        if installed?
          service_result = service_change_state!(verbose:)
          result &&= service_result

          link_result = link_change_state!(verbose:)
          result &&= link_result

          postinstall_result = postinstall_change_state!(verbose:)
          result &&= postinstall_result

          if result && @version_file.present?
            # Use the version from the environment if it hasn't changed.
            # Strip the revision number because it's not part of the non-Homebrew version.
            version = if !changed? && (env_version = Bundle.formula_versions_from_env(@name))
              PkgVersion.parse(env_version).version
            else
              Formula[@full_name].version
            end.to_s
            File.write(@version_file, "#{version}\n")

            puts "Wrote #{@name} version #{version} to #{@version_file}" if verbose
          end
        end

        result
      end

      sig { params(no_upgrade: T::Boolean, verbose: T::Boolean, force: T::Boolean).returns(T::Boolean) }
      def install_change_state!(no_upgrade:, verbose:, force:)
        require "tap"
        if (tap_with_name = ::Tap.with_formula_name(@full_name))
          tap, = tap_with_name
          tap.ensure_installed!
        end

        return false unless resolve_conflicts!(verbose:)

        if installed?
          upgrade_formula!(verbose:, force:)
        else
          install_formula!(verbose:, force:)
        end
      end

      sig { returns(T::Boolean) }
      def start_service?
        @start_service.present?
      end

      sig { returns(T::Boolean) }
      def start_service_needed?
        require "bundle/brew_services"
        start_service? && !Services.started?(@full_name)
      end

      sig { returns(T::Boolean) }
      def restart_service?
        @restart_service.present?
      end

      sig { returns(T::Boolean) }
      def restart_service_needed?
        return false unless restart_service?

        # Restart if `restart_service: :always`, or if the formula was installed or upgraded
        @restart_service.to_s == "always" || changed?
      end

      sig { returns(T::Boolean) }
      def changed?
        @changed.present?
      end

      sig { params(verbose: T::Boolean).returns(T::Boolean) }
      def service_change_state!(verbose:)
        require "bundle/brew_services"

        file = Services.versioned_service_file(@name)&.to_s

        if restart_service_needed?
          puts "Restarting #{@name} service." if verbose
          Services.restart(@full_name, file:, verbose:)
        elsif start_service_needed?
          puts "Starting #{@name} service." if verbose
          Services.start(@full_name, file:, verbose:)
        else
          true
        end
      end

      sig { params(verbose: T::Boolean).returns(T::Boolean) }
      def link_change_state!(verbose: false)
        link_args = []
        link_args << "--force" if unlinked_and_keg_only?

        cmd = case @link
        when :overwrite
          link_args << "--overwrite"
          "link" unless linked?
        when true
          "link" unless linked?
        when false
          "unlink" if linked?
        when nil
          if keg_only?
            "unlink" if linked?
          else
            "link" unless linked?
          end
        end

        if cmd.present?
          verb = "#{cmd}ing".capitalize
          with_args = " with #{link_args.join(" ")}" if link_args.present?
          puts "#{verb} #{@name} formula#{with_args}." if verbose
          return Bundle.brew(cmd, *link_args, @name, verbose:)
        end

        true
      end

      sig { params(verbose: T::Boolean).returns(T::Boolean) }
      def postinstall_change_state!(verbose:)
        return true if @postinstall.blank?
        return true unless changed?

        puts "Running postinstall for #{@name}: #{@postinstall}" if verbose
        Kernel.system(@postinstall) || false
      end

      private

      sig { returns(T::Boolean) }
      def installed?
        self.class.formula_installed?(@name)
      end

      sig { returns(T::Boolean) }
      def linked?
        Formula[@full_name].linked?
      end

      sig { returns(T::Boolean) }
      def keg_only?
        Formula[@full_name].keg_only?
      end

      sig { returns(T::Boolean) }
      def unlinked_and_keg_only?
        !linked? && keg_only?
      end

      sig { returns(T::Boolean) }
      def upgradable?
        self.class.formula_upgradable?(@full_name)
      end

      sig { returns(T::Array[String]) }
      def conflicts_with
        @conflicts_with ||= T.let(
          begin
            conflicts_with = Set.new
            conflicts_with += @conflicts_with_arg

            if (formula = T.cast(self.class.formulae_by_full_name(@full_name),
                                 T.nilable(T::Hash[Symbol, T.untyped]))) &&
              (formula_conflicts_with = formula[:conflicts_with])
              conflicts_with += formula_conflicts_with
            end

            conflicts_with.to_a
          end,
          T.nilable(T::Array[String]),
        )
      end

      sig { params(verbose: T::Boolean).returns(T::Boolean) }
      def resolve_conflicts!(verbose:)
        conflicts_with.each do |conflict|
          next unless self.class.formula_installed?(conflict)

          if verbose
            puts <<~EOS
              Unlinking #{conflict} formula.
              It is currently installed and conflicts with #{@name}.
            EOS
          end
          return false unless Bundle.brew("unlink", conflict, verbose:)

          next unless restart_service?

          require "bundle/brew_services"
          puts "Stopping #{conflict} service (if it is running)." if verbose
          Services.stop(conflict, verbose:)
        end

        true
      end

      sig { params(verbose: T::Boolean, force: T::Boolean).returns(T::Boolean) }
      def install_formula!(verbose:, force:)
        install_args = @args.dup
        install_args << "--force" << "--overwrite" if force
        install_args << "--skip-link" if @link == false
        with_args = " with #{install_args.join(" ")}" if install_args.present?
        puts "Installing #{@name} formula#{with_args}. It is not currently installed." if verbose
        unless Bundle.brew("install", "--formula", @full_name, *install_args, verbose:)
          @changed = nil
          return false
        end

        self.class.installed_formulae << @name
        @changed = true
        true
      end

      sig { params(verbose: T::Boolean, force: T::Boolean).returns(T::Boolean) }
      def upgrade_formula!(verbose:, force:)
        upgrade_args = []
        upgrade_args << "--force" if force
        with_args = " with #{upgrade_args.join(" ")}" if upgrade_args.present?
        puts "Upgrading #{@name} formula#{with_args}. It is installed but not up-to-date." if verbose
        unless Bundle.brew("upgrade", "--formula", @name, *upgrade_args, verbose:)
          @changed = nil
          return false
        end

        @changed = true
        true
      end

      class Topo < Hash
        extend T::Generic
        include TSort

        K = type_member { { fixed: String } }
        V = type_member { { fixed: T::Array[String] } }
        Elem = type_member(:out) { { fixed: [String, T::Array[String]] } }

        # TSort interface requires a broader block return type than our implementation.
        # rubocop:disable Sorbet/AllowIncompatibleOverride
        sig {
          override(allow_incompatible: true).params(block: T.proc.params(arg0: String).returns(BasicObject)).void
        }
        # rubocop:enable Sorbet/AllowIncompatibleOverride
        def each_key(&block)
          keys.each(&block)
        end
        alias tsort_each_node each_key

        sig { override.params(node: String, block: T.proc.params(arg0: String).void).void }
        def tsort_each_child(node, &block)
          fetch(node.downcase).sort.each(&block)
        end
      end
    end
  end
end
