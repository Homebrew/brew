# typed: strict
# frozen_string_literal: true

require "abstract_subcommand"
require "bundle/extensions/extension"
require "cleanup"

require "utils/formatter"
require "utils"
require "installed_dependents"
require "bundle/dsl"
require "bundle/extensions"
require "bundle/trust"
require "trust"
require "ask"
module Homebrew
  module Cmd
    class Bundle < Homebrew::AbstractCommand
      class CleanupSubcommand < Homebrew::AbstractSubcommand
        extend Utils::Output::Mixin

        subcommand_args do
          usage_banner <<~EOS
            `brew bundle cleanup`:
            Uninstall all dependencies not present in the `Brewfile`.

            This workflow is useful for maintainers or testers who regularly install lots of formulae.

            When cleanup is performed, Homebrew's global trust store is reset to the trust values declared by the `Brewfile`, removing trust entries not declared there.

            Unless `--force` is passed, this prompts before removing anything and returns a 1 exit code if the prompt is declined or cannot be shown.
          EOS
          named_args :none
          switch "--install",
                 description: "Run `install` before cleaning up dependencies."
          switch "-f", "--force",
                 description: "Actually perform cleanup operations and reset Homebrew's global trust store " \
                              "to the `Brewfile` values."
          switch "--all",
                 description: "Clean up all supported dependencies."
          switch "--formula", "--formulae", "--brews",
                 description: "Clean up Homebrew formula dependencies."
          switch "--no-formula", "--no-formulae", "--no-brews",
                 description: "Clean up without Homebrew formula dependencies. " \
                              "Enabled by default if `$HOMEBREW_BUNDLE_CLEANUP_NO_BREW` is set."
          switch "--no-cleanup-brew",
                 description: "Clean up without Homebrew formula dependencies.",
                 env:         :bundle_cleanup_no_brew
          switch "--cask", "--casks",
                 description: "Clean up Homebrew cask dependencies."
          switch "--no-cask", "--no-casks",
                 description: "Clean up without Homebrew cask dependencies. " \
                              "Enabled by default if `$HOMEBREW_BUNDLE_CLEANUP_NO_CASK` is set."
          switch "--no-cleanup-cask",
                 description: "Clean up without Homebrew cask dependencies.",
                 env:         :bundle_cleanup_no_cask
          switch "--tap", "--taps",
                 description: "Clean up Homebrew tap dependencies."
          switch "--no-tap", "--no-taps",
                 description: "Clean up without Homebrew tap dependencies. " \
                              "Enabled by default if `$HOMEBREW_BUNDLE_CLEANUP_NO_TAP` is set."
          switch "--no-cleanup-tap",
                 description: "Clean up without Homebrew tap dependencies.",
                 env:         :bundle_cleanup_no_tap
          Homebrew::Bundle.extensions.select(&:cleanup_supported?).each do |extension|
            env = "HOMEBREW_#{extension.cleanup_disable_env.to_s.upcase}"
            switch "--#{extension.flag}",
                   description: extension.switch_description("Clean up #{extension.banner_name}.")
            switch "--no-#{extension.flag}",
                   description: "#{extension.cleanup_disable_description} " \
                                "Enabled by default if `$#{env}` is set."
            switch "--no-cleanup-#{extension.flag}",
                   description: extension.cleanup_disable_description,
                   env:         extension.cleanup_disable_env
          end
          switch "--zap",
                 description: "Clean up casks using the `zap` command instead of `uninstall`."
        end

        sig { override.void }
        def run
          core_type_options = context.core_type_options(args, "cleanup", all: args.all?)
          self.class.cleanup(
            global:          context.global,
            file:            context.file,
            force:           context.force,
            zap:             context.zap,
            ask:             context.ask || !context.force,
            formulae:        core_type_options.fetch(:formulae),
            casks:           core_type_options.fetch(:casks),
            taps:            core_type_options.fetch(:taps),
            extension_types: context.extensions.select(&:cleanup_supported?).to_h do |extension|
              [
                extension.type,
                !context.extension_disabled?(args, extension) &&
                  (context.extension_selected?(args, extension) || args.all? || context.no_type_args),
              ]
            end,
          )
        end

        sig { void }
        def self.reset!
          require "bundle/cask"
          require "bundle/brew"
          require "bundle/tap"
          require "bundle/brew_services"

          @dsl = T.let(nil, T.nilable(Homebrew::Bundle::Dsl))
          @kept_casks = nil
          @kept_formulae = T.let(nil, T.nilable(T::Array[String]))
          Homebrew::Bundle::Cask.reset!
          Homebrew::Bundle::Brew.reset!
          Homebrew::Bundle::Tap.reset!
          Homebrew::Bundle::Brew::Services.reset!
          Homebrew::Bundle.extensions.each(&:reset!)
        end

        sig {
          params(global: T::Boolean, file: T.nilable(String), force: T::Boolean, zap: T::Boolean,
                 dsl: T.nilable(Homebrew::Bundle::Dsl), formulae: T::Boolean, casks: T::Boolean, taps: T::Boolean,
                 ask: T::Boolean, extension_types: Homebrew::Bundle::ExtensionTypes).void
        }
        def self.cleanup(global: false, file: nil, force: false, zap: false, dsl: nil,
                         formulae: true, casks: true, taps: true, ask: false, extension_types: {})
          read_dsl_from_brewfile!(global:, file:, dsl:)

          cleanup_formulae = formulae
          cleanup_casks = casks
          cleanup_taps = taps
          extension_types = Homebrew::Bundle.extensions.select(&:cleanup_supported?).to_h do |extension|
            [extension.type, true]
          end.merge(extension_types)
          casks = if casks
            casks_to_uninstall(global:, file:)
          else
            []
          end
          formulae = if formulae
            formulae_to_uninstall(global:, file:)
          else
            []
          end
          taps = if taps
            taps_to_untap(global:, file:)
          else
            []
          end
          cleanup_extensions = Homebrew::Bundle.extensions.select(&:cleanup_supported?).filter_map do |extension|
            next unless extension_types.fetch(extension.type, false)
            raise ArgumentError, "dsl is unset!" unless @dsl

            [extension, extension.cleanup_items(@dsl.entries)]
          end
          if force
            dsl = @dsl
            raise ArgumentError, "dsl is unset!" unless dsl

            Homebrew::Trust.replace!(Homebrew::Bundle::Trust.entries(dsl.entries))

            # Protect Brewfile formulae from autoremove during uninstall and cleanup.
            Homebrew::Bundle.mark_as_installed_on_request!(dsl.entries)

            if casks.any?
              args = if zap
                ["--zap"]
              else
                []
              end
              if Kernel.system HOMEBREW_BREW_FILE, "uninstall", "--cask", *args, "--force", *casks
                puts "Uninstalled #{Utils.pluralize("cask", casks.size, include_count: true)}"
              else
                ofail "Failed to uninstall casks. Some may have been removed."
              end
            end

            if formulae.any?
              if Kernel.system HOMEBREW_BREW_FILE, "uninstall", "--formula", "--force", *formulae
                puts "Uninstalled #{Utils.pluralize("formula", formulae.size, include_count: true)}"
              else
                ofail "Failed to uninstall formulae. Some may have been removed."
              end
            end

            if taps.any? && !Kernel.system(HOMEBREW_BREW_FILE, "untap", *taps)
              ofail "Failed to untap. Some taps may have been removed."
            end

            cleanup_extensions.each do |extension, items|
              next if items.empty?

              extension.cleanup!(items)
            end

            cleanup = system_output_no_stderr(HOMEBREW_BREW_FILE, "cleanup")
            puts cleanup unless cleanup.empty?
          else
            would_uninstall = false

            if casks.any?
              puts "Would uninstall casks:"
              puts Formatter.columns casks
              would_uninstall = true
            end

            if formulae.any?
              puts "Would uninstall formulae:"
              puts Formatter.columns formulae
              would_uninstall = true
            end

            if taps.any?
              puts "Would untap:"
              puts Formatter.columns taps
              would_uninstall = true
            end

            cleanup_extensions.each do |extension, items|
              next if items.empty?

              puts "Would uninstall #{extension.cleanup_heading}:"
              puts Formatter.columns items.map { |item| extension.cleanup_item_name(item) }
              would_uninstall = true
            end

            would_cleanup = Cleanup.printed_dry_run_output?(Cleanup.dry_run_output(quiet: true))
            would_change = would_uninstall || would_cleanup

            # `Ask.confirm?` only prints a prompt on a TTY; when it does, don't
            # also tell the user to rerun with `--force`.
            if ask && would_change && Homebrew::Ask.confirm?(action: "cleanup")
              cleanup(global:, file:, force: true, zap:, dsl: @dsl, formulae: cleanup_formulae, casks: cleanup_casks,
                      taps: cleanup_taps, extension_types:)
              return
            end

            puts "Run `brew bundle cleanup --force` to make these changes." if would_change
            exit 1 if would_uninstall
          end
        end

        sig { params(global: T::Boolean, file: T.nilable(String), dsl: T.nilable(Homebrew::Bundle::Dsl)).void }
        def self.read_dsl_from_brewfile!(global: false, file: nil, dsl: nil)
          resolved_dsl = if dsl
            dsl
          else
            require "bundle/brewfile"
            Homebrew::Bundle::Brewfile.read(global:, file:)
          end
          @dsl = T.let(resolved_dsl, T.nilable(Homebrew::Bundle::Dsl))
        end

        sig { returns(T.nilable(Homebrew::Bundle::Dsl)) }
        def self.dsl
          T.let(@dsl, T.nilable(Homebrew::Bundle::Dsl))
        end

        sig { params(global: T::Boolean, file: T.nilable(String)).returns(T::Array[String]) }
        def self.casks_to_uninstall(global: false, file: nil)
          raise ArgumentError, "@dsl is unset!" unless @dsl

          require "bundle/cask"
          Homebrew::Bundle::Cask.cask_names - kept_casks(global:, file:)
        end

        sig { params(global: T::Boolean, file: T.nilable(String)).returns(T::Array[String]) }
        def self.formulae_to_uninstall(global: false, file: nil)
          raise ArgumentError, "@dsl is unset!" unless @dsl

          kept_formulae = self.kept_formulae(global:, file:)

          require "bundle/brew"
          current_formulae = Homebrew::Bundle::Brew.formulae
          current_formulae.reject! do |f|
            Homebrew::Bundle::Brew.formula_in_array?(f[:full_name], kept_formulae)
          end
          current_formulae.map { |f| f[:full_name] }
        end

        sig { params(global: T::Boolean, file: T.nilable(String)).returns(T::Array[String]) }
        private_class_method def self.kept_formulae(global: false, file: nil)
          require "bundle/brew"
          require "bundle/cask"

          @kept_formulae ||= begin
            raise ArgumentError, "dsl is unset!" unless @dsl

            kept_formulae = @dsl.entries.select { |e| e.type == :brew }.map(&:name)
            kept_formulae += Homebrew::Bundle::Cask.formula_dependencies(kept_casks)
            kept_formulae.map! do |f|
              Homebrew::Bundle::Brew.formula_aliases.fetch(
                f,
                Homebrew::Bundle::Brew.formula_oldnames.fetch(f, f),
              )
            end

            # Keep formulae with keepme references and what `brew autoremove` keeps
            # for them and the Brewfile, as `brew uninstall` refuses to remove it.
            installed = Homebrew::Bundle::Brew.formulae.map { |f| Formula[f[:full_name]] }
            removable = installed.reject do |f|
              Homebrew::Bundle::Brew.formula_in_array?(f.full_name, kept_formulae) ||
                f.installed_kegs.any? { |keg| keg.keepme_refs.present? }
            end
            kept_formulae +
              (installed - InstalledDependents.formulae_safe_to_remove(removable, installed)).map(&:full_name)
          end
        end

        sig { params(global: T::Boolean, file: T.nilable(String)).returns(T::Array[String]) }
        private_class_method def self.kept_casks(global: false, file: nil)
          return @kept_casks if @kept_casks
          raise ArgumentError, "dsl is unset!" unless @dsl

          kept_casks = @dsl.entries.select { |e| e.type == :cask }.flat_map(&:name)
          kept_casks.map! do |c|
            Homebrew::Bundle::Cask.cask_oldnames.fetch(c, c)
          end
          @kept_casks = T.let(kept_casks, T.nilable(T::Array[String]))
          raise "kept_casks is nil" unless @kept_casks

          @kept_casks
        end

        IGNORED_TAPS = %w[homebrew/core].freeze

        sig { params(global: T::Boolean, file: T.nilable(String)).returns(T::Array[String]) }
        def self.taps_to_untap(global: false, file: nil)
          raise ArgumentError, "@dsl is unset!" unless @dsl

          require "bundle/tap"

          kept_formulae = self.kept_formulae(global:, file:).filter_map { lookup_formula(it) }
          kept_taps = @dsl.entries.select { |e| e.type == :tap }.map(&:name)
          kept_taps += @dsl.entries.filter_map do |entry|
            case entry.type
            when :brew
              Utils.tap_from_full_name(entry.name)
            when :cask
              full_name = entry.options.fetch(:full_name, entry.name)
              Utils.tap_from_full_name(T.cast(full_name, String))
            end
          end
          kept_taps += kept_formulae.filter_map(&:tap).map(&:name)
          current_taps = Homebrew::Bundle::Tap.tap_names
          current_taps - kept_taps - IGNORED_TAPS
        end

        sig { params(formula: String).returns(T.nilable(Formula)) }
        private_class_method def self.lookup_formula(formula)
          Formulary.factory(formula)
        rescue TapFormulaUnavailableError
          # ignore these as an unavailable formula implies there is no tap to worry about
          nil
        end

        sig { params(cmd: T.any(Pathname, String), args: T.anything).returns(String) }
        def self.system_output_no_stderr(cmd, *args)
          Utils.safe_popen_read(cmd, *args, err: File::NULL)
        end
      end
    end
  end
end
