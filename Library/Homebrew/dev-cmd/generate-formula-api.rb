# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "fileutils"
require "formula"

module Homebrew
  module DevCmd
    class GenerateFormulaApi < AbstractCommand
      FORMULA_JSON_TEMPLATE = <<~EOS
        ---
        layout: formula_json
        ---
        {{ content }}
      EOS

      cmd_args do
        description <<~EOS
          Generate `homebrew/core` API data files for <#{HOMEBREW_API_WWW}>.
          The generated files are written to the current directory.
        EOS
        switch "-n", "--dry-run",
               description: "Generate API data without writing it to files."

        named_args :none
      end

      sig { override.void }
      def run
        tap = CoreTap.instance
        raise TapUnavailableError, tap.name unless tap.installed?

        unless args.dry_run?
          directories = ["_data/formula", "api/formula", "formula", "api/internal"]
          FileUtils.rm_rf directories + ["_data/formula_canonical.json"]
          FileUtils.mkdir_p directories
        end

        Homebrew.with_no_api_env do
          tap_migrations_json = JSON.dump(tap.tap_migrations)
          File.write("api/formula_tap_migrations.json", tap_migrations_json) unless args.dry_run?

          Formulary.enable_factory_cache!
          Formula.generating_hash!

          all_formulae = {}
          latest_macos = MacOSVersion.new((HOMEBREW_MACOS_NEWEST_UNSUPPORTED.to_i - 1).to_s).to_sym
          Homebrew::SimulateSystem.with(os: latest_macos, arch: :arm) do
            tap.formula_names.each do |name|
              formula = Formulary.factory(name)
              name = formula.name
              all_formulae[name] = formula.to_hash_with_variations
              json = JSON.pretty_generate(all_formulae[name])
              html_template_name = html_template(name)

              unless args.dry_run?
                File.write("_data/formula/#{name.tr("+", "_")}.json", "#{json}\n")
                File.write("api/formula/#{name}.json", FORMULA_JSON_TEMPLATE)
                File.write("formula/#{name}.html", html_template_name)
              end
            rescue
              onoe "Error while generating data for formula '#{name}'."
              raise
            end
          end

          canonical_json = JSON.pretty_generate(tap.formula_renames.merge(tap.alias_table))
          File.write("_data/formula_canonical.json", "#{canonical_json}\n") unless args.dry_run?

          OnSystem::VALID_OS_ARCH_TAGS.each do |bottle_tag|
            macos_version = bottle_tag.to_macos_version if bottle_tag.macos?

            aliases = {}
            renames = {}
            variation_formulae = all_formulae.to_h do |name, formula|
              formula = Homebrew::API.merge_variations(formula, bottle_tag:)

              formula["aliases"]&.each do |alias_name|
                aliases[alias_name] = name
              end

              formula["oldnames"]&.each do |oldname|
                renames[oldname] = name
              end

              version = Version.new(formula.dig("versions", "stable"))
              pkg_version = PkgVersion.new(version, formula["revision"])
              version_scheme = formula.fetch("version_scheme", 0)
              rebuild = formula.dig("bottle", "stable", "rebuild") || 0

              bottle_collector = Utils::Bottles::Collector.new
              formula.dig("bottle", "stable", "files")&.each do |tag, data|
                tag = Utils::Bottles::Tag.from_symbol(tag)
                bottle_collector.add tag, checksum: Checksum.new(data["sha256"]), cellar: :any
              end

              sha256 = bottle_collector.specification_for(bottle_tag)&.checksum&.to_s

              dependencies = Set.new(formula["dependencies"])

              if macos_version
                uses_from_macos = formula["uses_from_macos"].zip(formula["uses_from_macos_bounds"])
                dependencies += uses_from_macos.filter_map do |dep, bounds|
                  next if bounds.blank?

                  since = bounds[:since]
                  next if since.blank?

                  since_macos_version = MacOSVersion.from_symbol(since)
                  next if since_macos_version <= macos_version

                  dep
                end
              else
                dependencies += formula["uses_from_macos"]
              end

              [name, [pkg_version.to_s, version_scheme, rebuild, sha256, dependencies.to_a]]
            end

            json_contents = {
              formulae:       variation_formulae,
              casks:          [],
              aliases:        aliases,
              renames:        renames,
              tap_migrations: CoreTap.instance.tap_migrations,
            }

            File.write("api/internal/formula.#{bottle_tag}.json", JSON.generate(json_contents)) unless args.dry_run?
          end
        end
      end

      private

      sig { params(title: String).returns(String) }
      def html_template(title)
        <<~EOS
          ---
          title: '#{title}'
          layout: formula
          redirect_from: /formula-linux/#{title}
          ---
          {{ content }}
        EOS
      end
    end
  end
end
