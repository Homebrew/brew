# typed: strict
# frozen_string_literal: true

require "utils/formatter"
require "bundle/dsl"
require "bundle/extensions"

module Homebrew
  module Bundle
    module Commands
      # Uninstalls formulae, casks, taps, VSCode extensions and Flatpak packages not listed in the Brewfile.
      module Cleanup
        sig { void }
        def self.reset!
          require "bundle/cask"
          require "bundle/brew"
          require "bundle/tap"
          require "bundle/brew_services"

          @dsl = T.let(nil, T.nilable(Homebrew::Bundle::Dsl))
          @kept_casks = nil
          @kept_formulae = nil
          Homebrew::Bundle::Cask.reset!
          Homebrew::Bundle::Brew.reset!
          Homebrew::Bundle::Tap.reset!
          Homebrew::Bundle::Brew::Services.reset!
          Homebrew::Bundle.extensions.each(&:reset!)
        end

        sig {
          params(global: T::Boolean, file: T.nilable(String), force: T::Boolean, zap: T::Boolean,
                 dsl: T.nilable(Homebrew::Bundle::Dsl), formulae: T::Boolean, casks: T::Boolean, taps: T::Boolean,
                 extension_types: Homebrew::Bundle::ExtensionTypes).void
        }
        def self.run(global: false, file: nil, force: false, zap: false, dsl: nil,
                     formulae: true, casks: true, taps: true, extension_types: {})
          read_dsl_from_brewfile!(global:, file:, dsl:)

          extension_types = Homebrew::Bundle.extensions.select(&:cleanup_supported?).to_h do |extension|
            [extension.type, true]
          end.merge(extension_types)
          casks = casks ? casks_to_uninstall(global:, file:) : []
          formulae = formulae ? formulae_to_uninstall(global:, file:) : []
          taps = taps ? taps_to_untap(global:, file:) : []
          cleanup_extensions = Homebrew::Bundle.extensions.select(&:cleanup_supported?).filter_map do |extension|
            next unless extension_types.fetch(extension.type, false)
            raise ArgumentError, "dsl is unset!" unless @dsl

            [extension, extension.cleanup_items(@dsl.entries)]
          end
          if force
            if casks.any?
              args = zap ? ["--zap"] : []
              Kernel.system HOMEBREW_BREW_FILE, "uninstall", "--cask", *args, "--force", *casks
              puts "Uninstalled #{casks.size} cask#{"s" if casks.size != 1}"
            end

            if formulae.any?
              raise ArgumentError, "dsl is unset!" unless @dsl

              # Mark Brewfile formulae as installed_on_request to prevent autoremove
              # from removing them when their dependents are uninstalled
              Homebrew::Bundle.mark_as_installed_on_request!(@dsl.entries)

              Kernel.system HOMEBREW_BREW_FILE, "uninstall", "--formula", "--force", *formulae
              puts "Uninstalled #{formulae.size} formula#{"e" if formulae.size != 1}"
            end

            Kernel.system HOMEBREW_BREW_FILE, "untap", *taps if taps.any?

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
              puts Formatter.columns items
              would_uninstall = true
            end

            cleanup = system_output_no_stderr(HOMEBREW_BREW_FILE, "cleanup", "--dry-run")
            unless cleanup.empty?
              puts "Would `brew cleanup`:"
              puts cleanup
            end

            puts "Run `brew bundle cleanup --force` to make these changes." if would_uninstall || !cleanup.empty?
            exit 1 if would_uninstall
          end
        end

        sig { params(global: T::Boolean, file: T.nilable(String), dsl: T.nilable(Homebrew::Bundle::Dsl)).void }
        def self.read_dsl_from_brewfile!(global: false, file: nil, dsl: nil)
          @dsl = T.let(
            if dsl
              dsl
            else
              require "bundle/brewfile"
              Brewfile.read(global:, file:)
            end,
            T.nilable(Homebrew::Bundle::Dsl),
          )
        end

        sig { returns(T.nilable(Homebrew::Bundle::Dsl)) }
        def self.dsl
          @dsl
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

          # Don't try to uninstall formulae with keepme references
          current_formulae.reject! do |f|
            Formula[f[:full_name]].installed_kegs.any? do |keg|
              keg.keepme_refs.present?
            end
          end
          current_formulae.map { |f| f[:full_name] }
        end

        sig { params(global: T::Boolean, file: T.nilable(String)).returns(T::Array[String]) }
        private_class_method def self.kept_formulae(global: false, file: nil)
          require "bundle/brew"
          require "bundle/cask"

          @kept_formulae ||= T.let(
            begin
              raise ArgumentError, "dsl is unset!" unless @dsl

              kept_formulae = @dsl.entries.select { |e| e.type == :brew }.map(&:name)
              kept_formulae += Homebrew::Bundle::Cask.formula_dependencies(kept_casks)
              kept_formulae.map! do |f|
                Homebrew::Bundle::Brew.formula_aliases.fetch(
                  f,
                  Homebrew::Bundle::Brew.formula_oldnames.fetch(f, f),
                )
              end

              kept_formulae + recursive_dependencies(Homebrew::Bundle::Brew.formulae, kept_formulae)
            end,
            T.nilable(T::Array[String]),
          )
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

        sig {
          params(current_formulae: T::Array[T::Hash[Symbol, T.untyped]], formulae_names: T::Array[String],
                 top_level: T::Boolean).returns(T::Array[String])
        }
        private_class_method def self.recursive_dependencies(current_formulae, formulae_names, top_level: true)
          @checked_formulae_names = T.let([], T.nilable(T::Array[String])) if top_level
          dependencies = T.let([], T::Array[String])

          formulae_names.each do |name|
            raise "checked_formulae_names is unset!" unless @checked_formulae_names
            next if @checked_formulae_names.include?(name)

            formula = current_formulae.find { |f| f[:full_name] == name }
            next unless formula

            f_deps = formula[:dependencies]
            unless formula[:poured_from_bottle?]
              f_deps += formula[:build_dependencies]
              f_deps.uniq!
            end
            next unless f_deps
            next if f_deps.empty?

            @checked_formulae_names << name
            f_deps += recursive_dependencies(current_formulae, f_deps, top_level: false)
            dependencies += f_deps
          end

          dependencies.uniq
        end

        IGNORED_TAPS = %w[homebrew/core].freeze

        sig { params(global: T::Boolean, file: T.nilable(String)).returns(T::Array[String]) }
        def self.taps_to_untap(global: false, file: nil)
          raise ArgumentError, "@dsl is unset!" unless @dsl

          require "bundle/tap"

          kept_formulae = self.kept_formulae(global:, file:).filter_map { lookup_formula(it) }
          kept_taps = @dsl.entries.select { |e| e.type == :tap }.map(&:name)
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
          IO.popen([cmd, *args], err: :close).read
        end
      end
    end
  end
end
