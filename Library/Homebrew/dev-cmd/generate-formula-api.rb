# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "api"
require "executables_db"
require "fileutils"
require "formula"
require "vulns/advisory_database"

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

        hide_from_man_page!
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

        executables_path = Pathname("api/internal/executables.txt")
        # Use the existing executables database as the API generation source.
        # It is generated from GitHub Packages metadata, not generated API JSON.
        if !args.dry_run? &&
           !Homebrew::API.download_executables_file_from_github_packages!(executables_path)
          odie "Failed to download #{executables_path}"
        end
        executables = ExecutablesDB.new(executables_path.to_s).to_hash
        advisories = load_advisory_database

        Homebrew::API.with_no_api_env do
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
              all_formulae[name]["executables"] = executables[name] if executables.key?(name)
              if (vulns = advisories&.status_for(name, formula.pkg_version))
                all_formulae[name]["vulnerabilities"] = vulns
              end
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
            formulae = all_formulae.to_h do |name, hash|
              hash = Homebrew::API::Formula::FormulaStructGenerator.generate_formula_struct_hash(hash, bottle_tag:)
                                                                   .serialize(bottle_tag:)
              [name, hash]
            end

            json_contents = {
              formulae:,
              aliases:        tap.alias_table,
              renames:        tap.formula_renames,
              tap_git_head:   tap.git_head,
              tap_migrations: tap.tap_migrations,
            }

            File.write("api/internal/formula.#{bottle_tag}.json", JSON.generate(json_contents)) unless args.dry_run?
          end
        end
      end

      private

      # An advisory-database or network failure must not break the API build;
      # the `vulnerabilities` field is omitted and the build proceeds.
      sig { returns(T.nilable(Homebrew::Vulns::AdvisoryDatabase)) }
      def load_advisory_database
        Homebrew::Vulns::AdvisoryDatabase.load
      rescue Homebrew::Vulns::CachedFeed::Error, ErrorDuringExecution => e
        opoo "Skipping vulnerabilities field: #{e.message.lines.first&.strip}"
        nil
      end

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
