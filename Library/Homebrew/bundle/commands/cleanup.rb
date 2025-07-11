# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

require "utils/formatter"

module Homebrew
  module Bundle
    module Commands
      # TODO: refactor into multiple modules
      module Cleanup
        def self.reset!
          require "bundle/cask_dumper"
          require "bundle/formula_dumper"
          require "bundle/tap_dumper"
          require "bundle/vscode_extension_dumper"
          require "bundle/brew_services"

          @dsl = nil
          @kept_casks = nil
          @kept_formulae = nil
          Homebrew::Bundle::CaskDumper.reset!
          Homebrew::Bundle::FormulaDumper.reset!
          Homebrew::Bundle::TapDumper.reset!
          Homebrew::Bundle::VscodeExtensionDumper.reset!
          Homebrew::Bundle::BrewServices.reset!
        end

        def self.run(global: false, file: nil, force: false, zap: false, dsl: nil,
                     formulae: true, casks: true, taps: true, vscode: true)
          @dsl ||= dsl

          casks = casks ? casks_to_uninstall(global:, file:) : []
          formulae = formulae ? formulae_to_uninstall(global:, file:) : []
          taps = taps ? taps_to_untap(global:, file:) : []
          vscode_extensions = vscode ? vscode_extensions_to_uninstall(global:, file:) : []
          if force
            if casks.any?
              args = zap ? ["--zap"] : []
              Kernel.system HOMEBREW_BREW_FILE, "uninstall", "--cask", *args, "--force", *casks
              puts "Uninstalled #{casks.size} cask#{"s" if casks.size != 1}"
            end

            if formulae.any?
              Kernel.system HOMEBREW_BREW_FILE, "uninstall", "--formula", "--force", *formulae
              puts "Uninstalled #{formulae.size} formula#{"e" if formulae.size != 1}"
            end

            Kernel.system HOMEBREW_BREW_FILE, "untap", *taps if taps.any?

            Bundle.exchange_uid_if_needed! do
              vscode_extensions.each do |extension|
                Kernel.system(T.must(Bundle.which_vscode).to_s, "--uninstall-extension", extension)
              end
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

            if vscode_extensions.any?
              puts "Would uninstall VSCode extensions:"
              puts Formatter.columns vscode_extensions
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

        def self.casks_to_uninstall(global: false, file: nil)
          require "bundle/cask_dumper"
          Homebrew::Bundle::CaskDumper.cask_names - kept_casks(global:, file:)
        end

        def self.formulae_to_uninstall(global: false, file: nil)
          kept_formulae = self.kept_formulae(global:, file:)

          require "bundle/formula_dumper"
          require "bundle/formula_installer"
          current_formulae = Homebrew::Bundle::FormulaDumper.formulae
          current_formulae.reject! do |f|
            Homebrew::Bundle::FormulaInstaller.formula_in_array?(f[:full_name], kept_formulae)
          end

          # Don't try to uninstall formulae with keepme references
          current_formulae.reject! do |f|
            Formula[f[:full_name]].installed_kegs.any? do |keg|
              keg.keepme_refs.present?
            end
          end
          current_formulae.map { |f| f[:full_name] }
        end

        private_class_method def self.kept_formulae(global: false, file: nil)
          require "bundle/brewfile"
          require "bundle/formula_dumper"
          require "bundle/cask_dumper"

          @kept_formulae ||= begin
            @dsl ||= Brewfile.read(global:, file:)

            kept_formulae = @dsl.entries.select { |e| e.type == :brew }.map(&:name)
            kept_formulae += Homebrew::Bundle::CaskDumper.formula_dependencies(kept_casks)
            kept_formulae.map! do |f|
              Homebrew::Bundle::FormulaDumper.formula_aliases.fetch(
                f,
                Homebrew::Bundle::FormulaDumper.formula_oldnames.fetch(f, f),
              )
            end

            kept_formulae + recursive_dependencies(Homebrew::Bundle::FormulaDumper.formulae, kept_formulae)
          end
        end

        private_class_method def self.kept_casks(global: false, file: nil)
          require "bundle/brewfile"
          return @kept_casks if @kept_casks

          @dsl ||= Brewfile.read(global:, file:)
          kept_casks = @dsl.entries.select { |e| e.type == :cask }.flat_map(&:name)
          kept_casks.map! do |c|
            Homebrew::Bundle::CaskDumper.cask_oldnames.fetch(c, c)
          end
          @kept_casks = kept_casks
        end

        private_class_method def self.recursive_dependencies(current_formulae, formulae_names, top_level: true)
          @checked_formulae_names = [] if top_level
          dependencies = T.let([], T::Array[Formula])

          formulae_names.each do |name|
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

        def self.taps_to_untap(global: false, file: nil)
          require "bundle/brewfile"
          require "bundle/tap_dumper"

          @dsl ||= Brewfile.read(global:, file:)
          kept_formulae = self.kept_formulae(global:, file:).filter_map(&method(:lookup_formula))
          kept_taps = @dsl.entries.select { |e| e.type == :tap }.map(&:name)
          kept_taps += kept_formulae.filter_map(&:tap).map(&:name)
          current_taps = Homebrew::Bundle::TapDumper.tap_names
          current_taps - kept_taps - IGNORED_TAPS
        end

        def self.lookup_formula(formula)
          Formulary.factory(formula)
        rescue TapFormulaUnavailableError
          # ignore these as an unavailable formula implies there is no tap to worry about
          nil
        end

        def self.vscode_extensions_to_uninstall(global: false, file: nil)
          require "bundle/brewfile"
          @dsl ||= Brewfile.read(global:, file:)
          kept_extensions = @dsl.entries.select { |e| e.type == :vscode }.map { |x| x.name.downcase }

          # To provide a graceful migration from `Brewfile`s that don't yet or
          # don't want to use `vscode`: don't remove any extensions if we don't
          # find any in the `Brewfile`.
          return [].freeze if kept_extensions.empty?

          require "bundle/vscode_extension_dumper"
          current_extensions = Homebrew::Bundle::VscodeExtensionDumper.extensions
          current_extensions - kept_extensions
        end

        def self.system_output_no_stderr(cmd, *args)
          IO.popen([cmd, *args], err: :close).read
        end
      end
    end
  end
end
