# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "fileutils"
require "formula"
require "cask/cask"

module Homebrew
  module DevCmd
    class GenerateInternalApi < AbstractCommand
      cmd_args do
        description <<~EOS
          Generate internal API data files for <#{HOMEBREW_API_WWW}>.
          The generated files are written to the current directory.
        EOS
        switch "-n", "--dry-run",
               description: "Generate internal API data without writing it to files."

        named_args :none
      end

      sig { override.void }
      def run
        core_tap = CoreTap.instance
        cask_tap = CoreCaskTap.instance
        raise TapUnavailableError, core_tap.name unless core_tap.installed?
        raise TapUnavailableError, cask_tap.name unless cask_tap.installed?

        unless args.dry_run?
          FileUtils.rm_rf "api/internal"
          FileUtils.mkdir_p "api/internal"
        end

        Homebrew.with_no_api_env do
          Formulary.enable_factory_cache!
          Formula.generating_hash!
          Cask::Cask.generating_hash!

          all_formulae = {}
          all_casks = {}
          latest_macos = MacOSVersion.new(HOMEBREW_MACOS_NEWEST_SUPPORTED).to_sym
          Homebrew::SimulateSystem.with(os: latest_macos, arch: :arm) do
            core_tap.formula_names.each do |name|
              formula = Formulary.factory(name)
              name = formula.name
              all_formulae[name] = formula.to_hash_with_variations
            rescue
              onoe "Error while generating data for formula '#{name}'."
              raise
            end

            cask_tap.cask_files.each do |path|
              cask = Cask::CaskLoader.load(path)
              name = cask.token
              all_casks[name] = cask.to_hash_with_variations
            rescue
              onoe "Error while generating data for cask '#{path.stem}'."
              raise
            end
          end

          OnSystem::VALID_OS_ARCH_TAGS.each do |bottle_tag|
            formulae = all_formulae.to_h do |name, hash|
              hash = Homebrew::API::Formula::FormulaStructGenerator.generate_formula_struct_hash(hash, bottle_tag:)
                                                                   .serialize(bottle_tag:)
              [name, hash]
            end

            casks = all_casks.to_h do |token, hash|
              hash = Homebrew::API::Cask::CaskStructGenerator.generate_cask_struct_hash(hash, bottle_tag:)
                                                             .serialize
              [token, hash]
            end

            json_contents = {
              formulae:,
              casks:,
              formula_aliases:        core_tap.alias_table,
              formula_renames:        core_tap.formula_renames,
              cask_renames:           cask_tap.cask_renames,
              formula_tap_git_head:   core_tap.git_head,
              cask_tap_git_head:      cask_tap.git_head,
              formula_tap_migrations: core_tap.tap_migrations,
              cask_tap_migrations:    cask_tap.tap_migrations,
            }

            File.write("api/internal/packages.#{bottle_tag}.json", JSON.generate(json_contents)) unless args.dry_run?
          end
        end
      end
    end
  end
end
