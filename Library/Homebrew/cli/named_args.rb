# typed: strict
# frozen_string_literal: true

require "cli/args"

module Homebrew
  module CLI
    # Helper class for loading formulae/casks from named arguments.
    class NamedArgs < Array
      extend T::Generic

      Elem = type_member(:out) { { fixed: String } }

      sig { returns(Args) }
      attr_reader :parent

      sig {
        params(
          args:          String,
          parent:        Args,
          override_spec: T.nilable(Symbol),
          force_bottle:  T::Boolean,
          flags:         T::Array[String],
          cask_options:  T::Boolean,
          without_api:   T::Boolean,
        ).void
      }
      def initialize(
        *args,
        parent: Args.new,
        override_spec: nil,
        force_bottle: false,
        flags: [],
        cask_options: false,
        without_api: false
      )
        super(args)

        @override_spec = override_spec
        @force_bottle = force_bottle
        @flags = flags
        @cask_options = cask_options
        @without_api = without_api
        @parent = parent
      end

      sig { returns(T::Array[Cask::Cask]) }
      def to_casks
        @to_casks ||= T.let(
          to_formulae_and_casks(only: :cask).freeze, T.nilable(T::Array[T.any(Formula, Keg, Cask::Cask)])
        )
        T.cast(@to_casks, T::Array[Cask::Cask])
      end

      sig { returns(T::Array[Formula]) }
      def to_formulae
        @to_formulae ||= T.let(
          to_formulae_and_casks(only: :formula).freeze, T.nilable(T::Array[T.any(Formula, Keg, Cask::Cask)])
        )
        T.cast(@to_formulae, T::Array[Formula])
      end

      # Convert named arguments to {Formula} or {Cask} objects.
      # If both a formula and cask with the same name exist, returns
      # the formula and prints a warning unless `only` is specified.
      sig {
        params(
          only:               T.nilable(Symbol),
          ignore_unavailable: T::Boolean,
          method:             T.nilable(Symbol),
          uniq:               T::Boolean,
          warn:               T::Boolean,
        ).returns(T::Array[T.any(Formula, Keg, Cask::Cask)])
      }
      def to_formulae_and_casks(
        only: parent.only_formula_or_cask, ignore_unavailable: false, method: nil, uniq: true, warn: false
      )
        @to_formulae_and_casks ||= T.let(
          {}, T.nilable(T::Hash[T.nilable(Symbol), T::Array[T.any(Formula, Keg, Cask::Cask)]])
        )
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
          @to_formulae_and_casks.fetch(only).uniq.freeze
        else
          @to_formulae_and_casks.fetch(only)
        end
      end

      sig {
        params(only: T.nilable(Symbol), method: T.nilable(Symbol))
          .returns([T::Array[T.any(Formula, Keg)], T::Array[Cask::Cask]])
      }
      def to_formulae_to_casks(only: parent.only_formula_or_cask, method: nil)
        @to_formulae_to_casks ||= T.let(
          {}, T.nilable(T::Hash[[T.nilable(Symbol), T.nilable(Symbol)],
                                [T::Array[T.any(Formula, Keg)], T::Array[Cask::Cask]]])
        )
        @to_formulae_to_casks[[method, only]] =
          T.cast(
            to_formulae_and_casks(only:, method:).partition { |o| o.is_a?(Formula) || o.is_a?(Keg) }
                    .map(&:freeze).freeze,
            [T::Array[T.any(Formula, Keg)], T::Array[Cask::Cask]],
          )
      end

      # Returns formulae and casks after validating that a tap is present for each of them.
      sig { returns(T::Array[T.any(Formula, Keg, Cask::Cask)]) }
      def to_formulae_and_casks_with_taps
        formulae_and_casks_with_taps, formulae_and_casks_without_taps =
          to_formulae_and_casks.partition do |formula_or_cask|
            T.cast(formula_or_cask, T.any(Formula, Cask::Cask)).tap&.installed?
          end

        return formulae_and_casks_with_taps if formulae_and_casks_without_taps.empty?

        types = []
        types << "formulae" if formulae_and_casks_without_taps.any?(Formula)
        types << "casks" if formulae_and_casks_without_taps.any?(Cask::Cask)

        odie <<~ERROR
          These #{types.join(" and ")} are not in any locally installed taps!

            #{formulae_and_casks_without_taps.sort_by(&:to_s).join("\n  ")}

          You may need to run `brew tap` to install additional taps.
        ERROR
      end

      sig {
        params(only: T.nilable(Symbol), method: T.nilable(Symbol))
          .returns(T::Array[T.any(Formula, Keg, Cask::Cask, T::Array[Keg], FormulaOrCaskUnavailableError)])
      }
      def to_formulae_and_casks_and_unavailable(only: parent.only_formula_or_cask, method: nil)
        @to_formulae_casks_unknowns ||= T.let(
          {},
          T.nilable(T::Hash[
            T.nilable(Symbol),
            T::Array[T.any(Formula, Keg, Cask::Cask, T::Array[Keg], FormulaOrCaskUnavailableError)]
          ]),
        )
        @to_formulae_casks_unknowns[method] = downcased_unique_named.map do |name|
          load_formula_or_cask(name, only:, method:)
        rescue FormulaOrCaskUnavailableError => e
          e
        end.uniq.freeze
      end

      sig { params(uniq: T::Boolean).returns(T::Array[Formula]) }
      def to_resolved_formulae(uniq: true)
        @to_resolved_formulae ||= T.let(
          to_formulae_and_casks(only: :formula, method: :resolve, uniq:).freeze,
          T.nilable(T::Array[T.any(Formula, Keg, Cask::Cask)]),
        )
        T.cast(@to_resolved_formulae, T::Array[Formula])
      end

      sig { params(only: T.nilable(Symbol)).returns([T::Array[Formula], T::Array[Cask::Cask]]) }
      def to_resolved_formulae_to_casks(only: parent.only_formula_or_cask)
        T.cast(to_formulae_to_casks(only:, method: :resolve), [T::Array[Formula], T::Array[Cask::Cask]])
      end

      LOCAL_PATH_REGEX = %r{^/|[.]|/$}
      TAP_NAME_REGEX = %r{^[^./]+/[^./]+$}
      private_constant :LOCAL_PATH_REGEX, :TAP_NAME_REGEX

      # Keep existing paths and try to convert others to tap, formula or cask paths.
      # If a cask and formula with the same name exist, includes both their paths
      # unless `only` is specified.
      sig { params(only: T.nilable(Symbol), recurse_tap: T::Boolean).returns(T::Array[Pathname]) }
      def to_paths(only: parent.only_formula_or_cask, recurse_tap: false)
        @to_paths ||= T.let({}, T.nilable(T::Hash[T.nilable(Symbol), T::Array[Pathname]]))
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

        @to_default_kegs ||= T.let(begin
          to_formulae_and_casks(only: :formula, method: :default_kegs).freeze
        rescue NoSuchKegError => e
          if (reason = MissingFormula.suggest_command(e.name, "uninstall"))
            $stderr.puts reason
          end
          raise e
        end, T.nilable(T::Array[T.any(Formula, Keg, Cask::Cask)]))
        T.cast(@to_default_kegs, T::Array[Keg])
      end

      sig { returns(T::Array[Keg]) }
      def to_latest_kegs
        require "missing_formula"

        @to_latest_kegs ||= T.let(begin
          to_formulae_and_casks(only: :formula, method: :latest_kegs).freeze
        rescue NoSuchKegError => e
          if (reason = MissingFormula.suggest_command(e.name, "uninstall"))
            $stderr.puts reason
          end
          raise e
        end, T.nilable(T::Array[T.any(Formula, Keg, Cask::Cask)]))
        T.cast(@to_latest_kegs, T::Array[Keg])
      end

      sig { returns(T::Array[Keg]) }
      def to_kegs
        require "missing_formula"

        @to_kegs ||= T.let(begin
          to_formulae_and_casks(only: :formula, method: :kegs).freeze
        rescue NoSuchKegError => e
          if (reason = MissingFormula.suggest_command(e.name, "uninstall"))
            $stderr.puts reason
          end
          raise e
        end, T.nilable(T::Array[T.any(Formula, Keg, Cask::Cask)]))
        T.cast(@to_kegs, T::Array[Keg])
      end

      sig {
        params(only: T.nilable(Symbol), ignore_unavailable: T::Boolean, all_kegs: T.nilable(T::Boolean))
          .returns([T::Array[Keg], T::Array[Cask::Cask]])
      }
      def to_kegs_to_casks(only: parent.only_formula_or_cask, ignore_unavailable: false, all_kegs: nil)
        method = all_kegs ? :kegs : :default_kegs
        @to_kegs_to_casks ||= T.let({}, T.nilable(T::Hash[T.nilable(Symbol), [T::Array[Keg], T::Array[Cask::Cask]]]))
        @to_kegs_to_casks[method] ||=
          T.cast(to_formulae_and_casks(only:, ignore_unavailable:, method:)
          .partition { |o| o.is_a?(Keg) }
          .map(&:freeze).freeze, [T::Array[Keg], T::Array[Cask::Cask]])
      end

      sig { returns(T::Array[Tap]) }
      def to_taps
        @to_taps ||= T.let(downcased_unique_named.map { |name| Tap.fetch name }.uniq.freeze, T.nilable(T::Array[Tap]))
      end

      sig { returns(T::Array[Tap]) }
      def to_installed_taps
        @to_installed_taps ||= T.let(to_taps.each do |tap|
          raise TapUnavailableError, tap.name unless tap.installed?
        end.uniq.freeze, T.nilable(T::Array[Tap]))
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

      sig {
        params(name: String, only: T.nilable(Symbol), method: T.nilable(Symbol), warn: T.nilable(T::Boolean))
          .returns(T.any(Formula, Keg, Cask::Cask, T::Array[Keg]))
      }
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

              if unreadable_error
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
                cask = Cask::CaskLoader.load_from_installed_caskfile(installed_caskfile)

                requested_tap, requested_token = Tap.with_cask_token(name)
                if requested_tap && requested_token
                  installed_cask_tap = cask.tab.tap

                  if installed_cask_tap && installed_cask_tap != requested_tap
                    raise Cask::TapCaskUnavailableError.new(requested_tap, requested_token)
                  end
                end

                cask
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
                opoo package_conflicts_message(name, "formula", cask) unless Context.current.quiet?
              end
              return formula_or_kegs
            elsif cask
              if formula_or_kegs && !Context.current.quiet?
                opoo package_conflicts_message(name, "cask", formula_or_kegs)
              end
              return cask
            end
          end

          raise unreadable_error if unreadable_error

          user, repo, short_name = name.downcase.split("/", 3)
          if repo.present? && short_name.present?
            tap = Tap.fetch(T.must(user), repo)
            raise TapFormulaOrCaskUnavailableError.new(tap, short_name)
          end

          raise NoSuchKegError, name if resolve_formula(name)
        end
      end

      sig { params(name: String).returns(Formula) }
      def resolve_formula(name)
        Formulary.resolve(name, **{ spec: @override_spec, force_bottle: @force_bottle, flags: @flags }.compact)
      end

      sig { params(name: String).returns([Pathname, T::Array[Keg]]) }
      def resolve_kegs(name)
        raise UsageError if name.blank?

        require "keg"

        rack = Formulary.to_rack(name.downcase)

        kegs = rack.directory? ? rack.subdirs.map { |d| Keg.new(d) } : []

        requested_tap, requested_formula = Tap.with_formula_name(name)
        if requested_tap && requested_formula
          kegs = kegs.select do |keg|
            keg.tab.tap == requested_tap
          end

          raise NoSuchKegError.new(requested_formula, tap: requested_tap) if kegs.none?
        end

        raise NoSuchKegError, name if kegs.none?

        [rack, kegs]
      end

      sig { params(name: String).returns(Keg) }
      def resolve_latest_keg(name)
        _, kegs = resolve_kegs(name)

        # Return keg if it is the only installed keg
        return kegs.fetch(0) if kegs.length == 1

        stable_kegs = kegs.reject { |keg| keg.version.head? }

        latest_keg = if stable_kegs.empty?
          kegs.max_by do |keg|
            [keg.tab.source_modified_time, keg.version.revision]
          end
        else
          stable_kegs.max_by(&:scheme_and_version)
        end
        T.must(latest_keg)
      end

      sig { params(name: String).returns(Keg) }
      def resolve_default_keg(name)
        rack, kegs = resolve_kegs(name)

        linked_keg_ref = HOMEBREW_LINKED_KEGS/rack.basename
        opt_prefix = HOMEBREW_PREFIX/"opt/#{rack.basename}"

        begin
          return Keg.new(opt_prefix.resolved_path) if opt_prefix.symlink? && opt_prefix.directory?
          return Keg.new(linked_keg_ref.resolved_path) if linked_keg_ref.symlink? && linked_keg_ref.directory?
          return kegs.fetch(0) if kegs.length == 1

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

      sig {
        params(
          ref: String, loaded_type: String,
          package: T.any(T::Array[T.any(Formula, Keg)], Cask::Cask, Formula, Keg, NilClass)
        ).returns(String)
      }
      def package_conflicts_message(ref, loaded_type, package)
        message = "Treating #{ref} as a #{loaded_type}."
        case package
        when Formula, Keg, Array
          message += " For the formula, "
          if package.is_a?(Formula) && (tap = package.tap)
            message += "use #{tap.name}/#{package.name} or "
          end
          message += "specify the `--formula` flag. To silence this message, use the `--cask` flag."
        when Cask::Cask
          message += " For the cask, "
          if (tap = package.tap)
            message += "use #{tap.name}/#{package.token} or "
          end
          message += "specify the `--cask` flag. To silence this message, use the `--formula` flag."
        end
        message.freeze
      end

      sig { params(ref: String, loaded_type: String).void }
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
        return if Context.current.quiet?

        opoo package_conflicts_message(ref, loaded_type, cask)
      end
    end
  end
end
