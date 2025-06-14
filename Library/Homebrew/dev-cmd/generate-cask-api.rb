# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "cask/cask"
require "fileutils"
require "formula"

module Homebrew
  module DevCmd
    class GenerateCaskApi < AbstractCommand
      CASK_JSON_TEMPLATE = <<~EOS
        ---
        layout: cask_json
        ---
        {{ content }}
      EOS

      cmd_args do
        description <<~EOS
          Generate `homebrew/cask` API data files for <#{HOMEBREW_API_WWW}>.
          The generated files are written to the current directory.
        EOS

        switch "-n", "--dry-run", description: "Generate API data without writing it to files."

        named_args :none
      end

      sig { override.void }
      def run
        tap = CoreCaskTap.instance
        raise TapUnavailableError, tap.name unless tap.installed?

        unless args.dry_run?
          directories = ["_data/cask", "api/cask", "api/cask-source", "cask", "api/internal"].freeze
          FileUtils.rm_rf directories
          FileUtils.mkdir_p directories
        end

        Homebrew.with_no_api_env do
          tap_migrations_json = JSON.dump(tap.tap_migrations)
          File.write("api/cask_tap_migrations.json", tap_migrations_json) unless args.dry_run?

          Cask::Cask.generating_hash!

          all_casks = {}
          latest_macos = MacOSVersion.new(HOMEBREW_MACOS_NEWEST_SUPPORTED).to_sym
          Homebrew::SimulateSystem.with(os: latest_macos, arch: :arm) do
            tap.cask_files.each do |path|
              cask = Cask::CaskLoader.load(path)
              name = cask.token
              all_casks[name] = cask.to_hash_with_variations
              json = JSON.pretty_generate(all_casks[name])
              cask_source = path.read
              html_template_name = html_template(name)

              unless args.dry_run?
                File.write("_data/cask/#{name.tr("+", "_")}.json", "#{json}\n")
                File.write("api/cask/#{name}.json", CASK_JSON_TEMPLATE)
                File.write("api/cask-source/#{name}.rb", cask_source)
                File.write("cask/#{name}.html", html_template_name)
              end
            rescue
              onoe "Error while generating data for cask '#{path.stem}'."
              raise
            end
          end

          canonical_json = JSON.pretty_generate(tap.cask_renames)
          File.write("_data/cask_canonical.json", "#{canonical_json}\n") unless args.dry_run?

          OnSystem::VALID_OS_ARCH_TAGS.each do |bottle_tag|
            variation_casks = all_casks.map do |_, cask|
              Homebrew::API.merge_variations(cask, bottle_tag:)
            end

            File.write("api/internal/cask.#{bottle_tag}.json", JSON.generate(variation_casks)) unless args.dry_run?
          end
        end
      end

      private

      sig { params(title: String).returns(String) }
      def html_template(title)
        <<~EOS
          ---
          title: '#{title}'
          layout: cask
          ---
          {{ content }}
        EOS
      end
    end
  end
end
