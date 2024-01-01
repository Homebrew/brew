# typed: true
# frozen_string_literal: true

require "delegate"
require "api"
require "cli/args"

module Homebrew
  module CLI
    # Helper class for loading formulae/casks from named arguments.
    #
    # @api private
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
        require "cask/cask"
        require "cask/cask_loader"
        require "formulary"
        require "keg"
        require "missing_formula"

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
          options = { warn: warn }.compact
          load_formula_or_cask(name, only: only, method: method, **options)
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
        @to_formulae_to_casks[[method, only]] = to_formulae_and_casks(only: only, method: method)
                                                .partition { |o| o.is_a?(Formula) || o.is_a?(Keg) }
                                                .map(&:freeze).freeze
      end

      def to_formulae_and_casks_and_unavailable(only: parent&.only_formula_or_cask, method: nil)
        @to_formulae_casks_unknowns ||= {}
        @to_formulae_casks_unknowns[method] = downcased_unique_named.map do |name|
          load_formula_or_cask(name, only: only, method: method)
        rescue FormulaOrCaskUnavailableError => e
          e
        end.uniq.freeze
      end

      def load_formula_or_cask(name, only: nil, method: nil, warn: nil)
        Homebrew.with_no_api_env_if_needed(@without_api) do
          unreadable_error = nil

          if only != :cask
            begin
              formula = case method
              when nil, :factory
                options = { warn: warn, force_bottle: @force_bottle, flags: @flags }.compact
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

              warn_if_cask_conflicts(name, "formula") if only != :formula
              return formula
            rescue FormulaUnreadableError, FormulaClassUnavailableError,
                   TapFormulaUnreadableError, TapFormulaClassUnavailableError,
                   FormulaSpecificationError => e
              # Need to rescue before `FormulaUnavailableError` (superclass of this)
              # The formula was found, but there's a problem with its implementation
              unreadable_error ||= e
            rescue NoSuchKegError, FormulaUnavailableError => e
              raise e if only == :formula
            end
          end

          if only != :formula
            want_keg_like_cask = [:latest_kegs, :default_kegs, :kegs].include?(method)

            begin
              config = Cask::Config.from_args(@parent) if @cask_options
              options = { warn: warn }.compact
              cask = Cask::CaskLoader.load(name, config: config, **options)

              if unreadable_error.present?
                onoe <<~EOS
                  Failed to load formula: #{name}
                  #{unreadable_error}
                EOS
                opoo "Treating #{name} as a cask."
              end

              # If we're trying to get a keg-like Cask, do our best to use the same cask
              # file that was used for installation, if possible.
              if want_keg_like_cask && (installed_caskfile = cask.installed_caskfile) && installed_caskfile.exist?
                cask = Cask::CaskLoader.load(installed_caskfile)
              end

              return cask
            rescue Cask::CaskUnreadableError, Cask::CaskInvalidError => e
              # If we're trying to get a keg-like Cask, do our best to handle it
              # not being readable and return something that can be used.
              if want_keg_like_cask
                cask_version = Cask::Cask.new(name, config: config).installed_version
                cask = Cask::Cask.new(name, config: config) do
                  version cask_version if cask_version
                end
                return cask
              end

              # Need to rescue before `CaskUnavailableError` (superclass of this)
              # The cask was found, but there's a problem with its implementation
              unreadable_error ||= e
            rescue Cask::CaskUnavailableError => e
              raise e if only == :cask
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
        @to_resolved_formulae ||= to_formulae_and_casks(only: :formula, method: :resolve, uniq: uniq)
                                  .freeze
      end

      def to_resolved_formulae_to_casks(only: parent&.only_formula_or_cask)
        to_formulae_to_casks(only: only, method: :resolve)
      end

      LOCAL_PATH_REGEX = %r{^/|[.]|/$}.freeze
      TAP_NAME_REGEX = %r{^[^./]+/[^./]+$}.freeze
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
                 (!CoreTap.instance.installed? && Homebrew::API::Formula.all_formulae.key?(path.basename))
                paths << formula_path
              end
              if cask_path.exist? ||
                 (!CoreCaskTap.instance.installed? && Homebrew::API::Cask.all_casks.key?(path.basename))
                paths << cask_path
              end

              paths.empty? ? path : paths
            end
          end.uniq.freeze
        end
      end

      sig { returns(T::Array[Keg]) }
      def to_default_kegs
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
          to_formulae_and_casks(only: only, ignore_unavailable: ignore_unavailable, method: method)
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

        stable_kegs = kegs.reject { |k| k.version.head? }

        if stable_kegs.blank?
          return kegs.max_by do |keg|
            [Tab.for_keg(keg).source_modified_time, keg.version.revision]
          end
        end

        stable_kegs.max_by(&:version)
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

      def warn_if_cask_conflicts(ref, loaded_type)
        message = "Treating #{ref} as a #{loaded_type}."
        begin
          cask = Cask::CaskLoader.load ref
          message += " For the cask, use #{cask.tap.name}/#{cask.token}" if cask.tap.present?
        rescue Cask::CaskUnreadableError => e
          # Need to rescue before `CaskUnavailableError` (superclass of this)
          # The cask was found, but there's a problem with its implementation
          onoe <<~EOS
            Failed to load cask: #{ref}
            #{e}
          EOS
        rescue Cask::CaskUnavailableError
          # No ref conflict with a cask, do nothing
          return
        end
        opoo message.freeze
      end
    end
  end
end
