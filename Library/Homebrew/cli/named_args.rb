# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

require "delegate"
require "cli/args"

module Homebrew
  module CLI
    # Helper class for loading formulae/casks from named arguments.
    class NamedArgs < Array
      sig {
        params(
          args:          String,
          parent:        Args,
          override_spec: Symbol,
          force_bottle:  T::Boolean,
          flags:         T::Array[String],
          cask_options:  T::Boolean,
          without_api:   T::Boolean,
        ).void
      }
      def initialize(
        *args,
        parent: Args.new,
        override_spec: T.unsafe(nil),
        force_bottle: T.unsafe(nil),
        flags: T.unsafe(nil),
        cask_options: false,
        without_api: false
      )
        @args = args
        @override_spec = override_spec
        @force_bottle = force_bottle
        @flags = flags
        @cask_options = cask_options
        @without_api = without_api
        @parent = parent

        super(@args)
      end

      attr_reader :parent

      def to_casks
        @to_casks ||= to_formulae_and_casks(only: :cask).freeze
      end

      def to_formulae
        @to_formulae ||= to_formulae_and_casks(only: :formula).freeze
      end

      # Convert named arguments to {Formula} or {Cask} objects.
      # If both a formula and cask with the same name exist, returns
      # the formula and prints a warning unless `only` is specified.
      sig {
        params(
          only:               T.nilable(Symbol),
          ignore_unavailable: T.nilable(T::Boolean),
          method:             T.nilable(Symbol),
          uniq:               T::Boolean,
          warn:               T::Boolean,
        ).returns(T::Array[T.any(Formula, Keg, Cask::Cask)])
      }
      def to_formulae_and_casks(
        only: parent&.only_formula_or_cask,
        ignore_unavailable: nil,
        method: T.unsafe(nil),
        uniq: true,
        warn: T.unsafe(nil)
      )
        @to_formulae_and_casks ||= {}
        @to_formulae_and_casks[only] ||= downcased_unique_named.flat_map do |name|
          options = { warn: }.compact
          load_formula_or_cask(name, only:, method:, **options)
        rescue FormulaUnreadableError, FormulaClassUnavailableError,
               TapFormulaUnreadableError, TapFormulaClassUnavailableError,
               Cask::CaskUnreadableError
          # Need to rescue before `*UnavailableError` (superclass of this)
          # The formula/cask was found, but there's a problem with its implementation
          raise
        rescue NoSuchKegError, FormulaUnavailableError, Cask::CaskUnavailableError, FormulaOrCaskUnavailableError
          ignore_unavailable ? [] : raise
        end.freeze

        if uniq
          @to_formulae_and_casks[only].uniq.freeze
        else
          @to_formulae_and_casks[only]
        end
      end

      def to_formulae_to_casks(only: parent&.only_formula_or_cask, method: nil)
        @to_formulae_to_casks ||= {}
        @to_formulae_to_casks[[method, only]] = to_formulae_and_casks(only:, method:)
                                                .partition { |o| o.is_a?(Formula) || o.is_a?(Keg) }
                                                .map(&:freeze).freeze
      end

      # Returns formulae and casks after validating that a tap is present for each of them.
      def to_formulae_and_casks_with_taps
        formulae_and_casks_with_taps, formulae_and_casks_without_taps =
          to_formulae_and_casks.partition do |formula_or_cask|
            T.cast(formula_or_cask, T.any(Formula, Cask::Cask)).tap&.installed?
          end

        return formulae_and_casks_with_taps if formulae_and_casks_without_taps.blank?

        types = []
        types << "formulae" if formulae_and_casks_without_taps.any?(Formula)
        types << "casks" if formulae_and_casks_without_taps.any?(Cask::Cask)

        odie <<~ERROR
          These #{types.join(" and ")} are not in any locally installed taps!

            #{formulae_and_casks_without_taps.sort_by(&:to_s).join("\n  ")}

          You may need to run `brew tap` to install additional taps.
        ERROR
      end

      def to_formulae_and_casks_and_unavailable(only: parent&.only_formula_or_cask, method: nil)
        @to_formulae_casks_unknowns ||= {}
        @to_formulae_casks_unknowns[method] = downcased_unique_named.map do |name|
          load_formula_or_cask(name, only:, method:)
        rescue FormulaOrCaskUnavailableError => e
          e
        end.uniq.freeze
      end

      def load_formula_or_cask(name, only: nil, method: nil, warn: nil)
        Homebrew.with_no_api_env_if_needed(@without_api) do
          unreadable_error = nil

          formula_or_kegs = if only != :cask
            begin
              case method
              when nil, :factory
                options = { warn:, force_bottle: @force_bottle, flags: @flags }.compact
                Formulary.factory(name, *@override_spec, **options)
              when :resolve
                resolve_formula(name)
              when :latest_kegs
                resolve_latest_keg(name)
              when :default_kegs
                resolve_default_keg(name)
              when :kegs
                _, kegs = resolve_kegs(name)
                kegs
              else
                raise
              end
            rescue FormulaUnreadableError, FormulaClassUnavailableError,
                   TapFormulaUnreadableError, TapFormulaClassUnavailableError,
                   FormulaSpecificationError => e
              # Need to rescue before `FormulaUnavailableError` (superclass of this)
              # The formula was found, but there's a problem with its implementation
              unreadable_error ||= e
              nil
            rescue NoSuchKegError, FormulaUnavailableError => e
              raise e if only == :formula

              nil
            end
          end

          if only == :formula
            return formula_or_kegs if formula_or_kegs
          elsif formula_or_kegs && (!formula_or_kegs.is_a?(Formula) || formula_or_kegs.tap&.core_tap?)
            warn_if_cask_conflicts(name, "formula")
            return formula_or_kegs
          else
            want_keg_like_cask = [:latest_kegs, :default_kegs, :kegs].include?(method)

            cask = begin
              config = Cask::Config.from_args(@parent) if @cask_options
              options = { warn: }.compact
              candidate_cask = Cask::CaskLoader.load(name, config:, **options)

              if unreadable_error.present?
                onoe <<~EOS
                  Failed to load formula: #{name}
                  #{unreadable_error}
                EOS
                opoo "Treating #{name} as a cask."
              end

              # If we're trying to get a keg-like Cask, do our best to use the same cask
              # file that was used for installation, if possible.
              if want_keg_like_cask &&
                 (installed_caskfile = candidate_cask.installed_caskfile) &&
                 installed_caskfile.exist?
                Cask::CaskLoader.load(installed_caskfile)
              else
                candidate_cask
              end
            rescue Cask::CaskUnreadableError, Cask::CaskInvalidError => e
              # If we're trying to get a keg-like Cask, do our best to handle it
              # not being readable and return something that can be used.
              if want_keg_like_cask
                cask_version = Cask::Cask.new(name, config:).installed_version
                Cask::Cask.new(name, config:) do
                  version cask_version if cask_version
                end
              else
                # Need to rescue before `CaskUnavailableError` (superclass of this)
                # The cask was found, but there's a problem with its implementation
                unreadable_error ||= e
                nil
              end
            rescue Cask::CaskUnavailableError => e
              raise e if only == :cask

              nil
            end

            # Prioritise formulae unless it's a core tap cask (we already prioritised core tap formulae above)
            if formula_or_kegs && !cask&.tap&.core_cask_tap?
              if cask || unreadable_error
                onoe <<~EOS if unreadable_error
                  Failed to load cask: #{name}
                  #{unreadable_error}
                EOS
                opoo package_conflicts_message(name, "formula", cask)
              end
              return formula_or_kegs
            elsif cask
              opoo package_conflicts_message(name, "cask", formula_or_kegs) if formula_or_kegs
              return cask
            end
          end

          raise unreadable_error if unreadable_error.present?

          user, repo, short_name = name.downcase.split("/", 3)
          if repo.present? && short_name.present?
            tap = Tap.fetch(user, repo)
            raise TapFormulaOrCaskUnavailableError.new(tap, short_name)
          end

          raise NoSuchKegError, name if resolve_formula(name)

          raise FormulaOrCaskUnavailableError, name
        end
      end
      private :load_formula_or_cask

      def resolve_formula(name)
        Formulary.resolve(name, **{ spec: @override_spec, force_bottle: @force_bottle, flags: @flags }.compact)
      end
      private :resolve_formula

      sig { params(uniq: T::Boolean).returns(T::Array[Formula]) }
      def to_resolved_formulae(uniq: true)
        @to_resolved_formulae ||= to_formulae_and_casks(only: :formula, method: :resolve, uniq:)
                                  .freeze
      end

      def to_resolved_formulae_to_casks(only: parent&.only_formula_or_cask)
        to_formulae_to_casks(only:, method: :resolve)
      end

      LOCAL_PATH_REGEX = %r{^/|[.]|/$}
      TAP_NAME_REGEX = %r{^[^./]+/[^./]+$}
      private_constant :LOCAL_PATH_REGEX, :TAP_NAME_REGEX

      # Keep existing paths and try to convert others to tap, formula or cask paths.
      # If a cask and formula with the same name exist, includes both their paths
      # unless `only` is specified.
      sig { params(only: T.nilable(Symbol), recurse_tap: T::Boolean).returns(T::Array[Pathname]) }
      def to_paths(only: parent&.only_formula_or_cask, recurse_tap: false)
        @to_paths ||= {}
        @to_paths[only] ||= Homebrew.with_no_api_env_if_needed(@without_api) do
          downcased_unique_named.flat_map do |name|
            path = Pathname(name).expand_path
            if only.nil? && name.match?(LOCAL_PATH_REGEX) && path.exist?
              path
            elsif name.match?(TAP_NAME_REGEX)
              tap = Tap.fetch(name)

              if recurse_tap
                next tap.formula_files if only == :formula
                next tap.cask_files if only == :cask
              end

              tap.path
            else
              next Formulary.path(name) if only == :formula
              next Cask::CaskLoader.path(name) if only == :cask

              formula_path = Formulary.path(name)
              cask_path = Cask::CaskLoader.path(name)

              paths = []

              if formula_path.exist? ||
                 (!Homebrew::EnvConfig.no_install_from_api? &&
                 !CoreTap.instance.installed? &&
                 Homebrew::API::Formula.all_formulae.key?(path.basename.to_s))
                paths << formula_path
              end
              if cask_path.exist? ||
                 (!Homebrew::EnvConfig.no_install_from_api? &&
                 !CoreCaskTap.instance.installed? &&
                 Homebrew::API::Cask.all_casks.key?(path.basename.to_s))
                paths << cask_path
              end

              paths.empty? ? path : paths
            end
          end.uniq.freeze
        end
      end

      sig { returns(T::Array[Keg]) }
      def to_default_kegs
        require "missing_formula"

        @to_default_kegs ||= begin
          to_formulae_and_casks(only: :formula, method: :default_kegs).freeze
        rescue NoSuchKegError => e
          if (reason = MissingFormula.suggest_command(e.name, "uninstall"))
            $stderr.puts reason
          end
          raise e
        end
      end

      sig { returns(T::Array[Keg]) }
      def to_latest_kegs
        require "missing_formula"

        @to_latest_kegs ||= begin
          to_formulae_and_casks(only: :formula, method: :latest_kegs).freeze
        rescue NoSuchKegError => e
          if (reason = MissingFormula.suggest_command(e.name, "uninstall"))
            $stderr.puts reason
          end
          raise e
        end
      end

      sig { returns(T::Array[Keg]) }
      def to_kegs
        require "missing_formula"

        @to_kegs ||= begin
          to_formulae_and_casks(only: :formula, method: :kegs).freeze
        rescue NoSuchKegError => e
          if (reason = MissingFormula.suggest_command(e.name, "uninstall"))
            $stderr.puts reason
          end
          raise e
        end
      end

      sig {
        params(only: T.nilable(Symbol), ignore_unavailable: T.nilable(T::Boolean), all_kegs: T.nilable(T::Boolean))
          .returns([T::Array[Keg], T::Array[Cask::Cask]])
      }
      def to_kegs_to_casks(only: parent&.only_formula_or_cask, ignore_unavailable: nil, all_kegs: nil)
        method = all_kegs ? :kegs : :default_kegs
        @to_kegs_to_casks ||= {}
        @to_kegs_to_casks[method] ||=
          to_formulae_and_casks(only:, ignore_unavailable:, method:)
          .partition { |o| o.is_a?(Keg) }
          .map(&:freeze).freeze
      end

      sig { returns(T::Array[Tap]) }
      def to_taps
        @to_taps ||= downcased_unique_named.map { |name| Tap.fetch name }.uniq.freeze
      end

      sig { returns(T::Array[Tap]) }
      def to_installed_taps
        @to_installed_taps ||= to_taps.each do |tap|
          raise TapUnavailableError, tap.name unless tap.installed?
        end.uniq.freeze
      end

      sig { returns(T::Array[String]) }
      def homebrew_tap_cask_names
        downcased_unique_named.grep(HOMEBREW_CASK_TAP_CASK_REGEX)
      end

      private

      sig { returns(T::Array[String]) }
      def downcased_unique_named
        # Only lowercase names, not paths, bottle filenames or URLs
        map do |arg|
          if arg.include?("/") || arg.end_with?(".tar.gz") || File.exist?(arg)
            arg
          else
            arg.downcase
          end
        end.uniq
      end

      def resolve_kegs(name)
        raise UsageError if name.blank?

        require "keg"

        rack = Formulary.to_rack(name.downcase)

        kegs = rack.directory? ? rack.subdirs.map { |d| Keg.new(d) } : []
        raise NoSuchKegError, name if kegs.none?

        [rack, kegs]
      end

      def resolve_latest_keg(name)
        _, kegs = resolve_kegs(name)

        # Return keg if it is the only installed keg
        return kegs if kegs.length == 1

        stable_kegs = kegs.reject { |keg| keg.version.head? }

        if stable_kegs.blank?
          return kegs.max_by do |keg|
            [keg.tab.source_modified_time, keg.version.revision]
          end
        end

        stable_kegs.max_by(&:scheme_and_version)
      end

      def resolve_default_keg(name)
        rack, kegs = resolve_kegs(name)

        linked_keg_ref = HOMEBREW_LINKED_KEGS/rack.basename
        opt_prefix = HOMEBREW_PREFIX/"opt/#{rack.basename}"

        begin
          return Keg.new(opt_prefix.resolved_path) if opt_prefix.symlink? && opt_prefix.directory?
          return Keg.new(linked_keg_ref.resolved_path) if linked_keg_ref.symlink? && linked_keg_ref.directory?
          return kegs.first if kegs.length == 1

          f = if name.include?("/") || File.exist?(name)
            Formulary.factory(name)
          else
            Formulary.from_rack(rack)
          end

          unless (prefix = f.latest_installed_prefix).directory?
            raise MultipleVersionsInstalledError, <<~EOS
              #{rack.basename} has multiple installed versions
              Run `brew uninstall --force #{rack.basename}` to remove all versions.
            EOS
          end

          Keg.new(prefix)
        rescue FormulaUnavailableError
          raise MultipleVersionsInstalledError, <<~EOS
            Multiple kegs installed to #{rack}
            However we don't know which one you refer to.
            Please delete (with `rm -rf`!) all but one and then try again.
          EOS
        end
      end

      def package_conflicts_message(ref, loaded_type, package)
        message = "Treating #{ref} as a #{loaded_type}."
        case package
        when Formula, Keg, Array
          message += " For the formula, "
          if package.is_a?(Formula) && (tap = package.tap)
            message += "use #{tap.name}/#{package.name} or "
          end
          message += "specify the `--formula` flag."
        when Cask::Cask
          message += " For the cask, "
          if (tap = package.tap)
            message += "use #{tap.name}/#{package.token} or "
          end
          message += "specify the `--cask` flag."
        end
        message.freeze
      end

      def warn_if_cask_conflicts(ref, loaded_type)
        available = true
        cask = begin
          Cask::CaskLoader.load(ref, warn: false)
        rescue Cask::CaskUnreadableError => e
          # Need to rescue before `CaskUnavailableError` (superclass of this)
          # The cask was found, but there's a problem with its implementation
          onoe <<~EOS
            Failed to load cask: #{ref}
            #{e}
          EOS
          nil
        rescue Cask::CaskUnavailableError
          # No ref conflict with a cask, do nothing
          available = false
          nil
        end
        return unless available

        opoo package_conflicts_message(ref, loaded_type, cask)
      end
    end
  end
end
