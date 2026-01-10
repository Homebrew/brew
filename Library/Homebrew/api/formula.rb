# typed: strict
# frozen_string_literal: true

require "cachable"
require "api"
require "api/source_download"
require "download_queue"
require "autobump_constants"

module Homebrew
  module API
    # Helper functions for using the formula JSON API.
    module Formula
      extend Cachable

      DEFAULT_API_FILENAME = "formula.jws.json"

      private_class_method :cache

      sig { params(name: String).returns(T::Hash[String, T.untyped]) }
      def self.formula_json(name)
        fetch_formula_json! name if !cache.key?("formula_json") || !cache.fetch("formula_json").key?(name)

        cache.fetch("formula_json").fetch(name)
      end

      sig { params(name: String, download_queue: T.nilable(DownloadQueue)).void }
      def self.fetch_formula_json!(name, download_queue: nil)
        endpoint = "formula/#{name}.json"
        json_formula, updated = Homebrew::API.fetch_json_api_file endpoint, download_queue: download_queue
        return if download_queue

        json_formula = JSON.parse((HOMEBREW_CACHE_API/endpoint).read) unless updated

        cache["formula_json"] ||= {}
        cache["formula_json"][name] = json_formula
      end

      sig { params(formula: ::Formula, download_queue: T.nilable(Homebrew::DownloadQueue)).returns(Homebrew::API::SourceDownload) }
      def self.source_download(formula, download_queue: nil)
        path = formula.ruby_source_path || "Formula/#{formula.name}.rb"
        git_head = formula.tap_git_head || "HEAD"
        tap = formula.tap&.full_name || "Homebrew/homebrew-core"

        download = Homebrew::API::SourceDownload.new(
          "https://raw.githubusercontent.com/#{tap}/#{git_head}/#{path}",
          formula.ruby_source_checksum,
          cache: HOMEBREW_CACHE_API_SOURCE/"#{tap}/#{git_head}/Formula",
        )

        if download_queue
          download_queue.enqueue(download)
        elsif !download.symlink_location.exist?
          download.fetch
        end

        download
      end

      sig { params(formula: ::Formula).returns(::Formula) }
      def self.source_download_formula(formula)
        download = source_download(formula)

        with_env(HOMEBREW_INTERNAL_ALLOW_PACKAGES_FROM_PATHS: "1") do
          Formulary.factory(download.symlink_location,
                            formula.active_spec_sym,
                            alias_path: formula.alias_path,
                            flags:      formula.class.build_flags)
        end
      end

      sig { returns(Pathname) }
      def self.cached_json_file_path
        HOMEBREW_CACHE_API/DEFAULT_API_FILENAME
      end

      sig {
        params(download_queue: T.nilable(Homebrew::DownloadQueue), stale_seconds: T.nilable(Integer))
          .returns([T.any(T::Array[T.untyped], T::Hash[String, T.untyped]), T::Boolean])
      }
      def self.fetch_api!(download_queue: nil, stale_seconds: nil)
        Homebrew::API.fetch_json_api_file DEFAULT_API_FILENAME, stale_seconds:, download_queue:
      end

      sig {
        params(download_queue: T.nilable(Homebrew::DownloadQueue), stale_seconds: T.nilable(Integer))
          .returns([T.any(T::Array[T.untyped], T::Hash[String, T.untyped]), T::Boolean])
      }
      def self.fetch_tap_migrations!(download_queue: nil, stale_seconds: nil)
        Homebrew::API.fetch_json_api_file "formula_tap_migrations.jws.json", stale_seconds:, download_queue:
      end

      sig { returns(T::Boolean) }
      def self.download_and_cache_data!
        json_formulae, updated = fetch_api!

        cache["aliases"] = {}
        cache["renames"] = {}
        cache["formulae"] = json_formulae.to_h do |json_formula|
          json_formula["aliases"].each do |alias_name|
            cache["aliases"][alias_name] = json_formula["name"]
          end
          (json_formula["oldnames"] || [json_formula["oldname"]].compact).each do |oldname|
            cache["renames"][oldname] = json_formula["name"]
          end

          [json_formula["name"], json_formula.except("name")]
        end

        updated
      end
      private_class_method :download_and_cache_data!

      sig { returns(T::Hash[String, T.untyped]) }
      def self.all_formulae
        unless cache.key?("formulae")
          json_updated = download_and_cache_data!
          write_names_and_aliases(regenerate: json_updated)
        end

        cache.fetch("formulae")
      end

      sig { returns(T::Hash[String, String]) }
      def self.all_aliases
        unless cache.key?("aliases")
          json_updated = download_and_cache_data!
          write_names_and_aliases(regenerate: json_updated)
        end

        cache.fetch("aliases")
      end

      sig { returns(T::Hash[String, String]) }
      def self.all_renames
        unless cache.key?("renames")
          json_updated = download_and_cache_data!
          write_names_and_aliases(regenerate: json_updated)
        end

        cache.fetch("renames")
      end

      sig { returns(T::Hash[String, T.untyped]) }
      def self.tap_migrations
        unless cache.key?("tap_migrations")
          json_migrations, = fetch_tap_migrations!
          cache["tap_migrations"] = json_migrations
        end

        cache.fetch("tap_migrations")
      end

      sig { params(regenerate: T::Boolean).void }
      def self.write_names_and_aliases(regenerate: false)
        download_and_cache_data! unless cache.key?("formulae")

        Homebrew::API.write_names_file!(all_formulae.keys, "formula", regenerate:)
        Homebrew::API.write_aliases_file!(all_aliases, "formula", regenerate:)
      end

      sig { params(hash: T::Hash[String, T.untyped]).returns(FormulaStruct) }
      def self.generate_formula_struct_hash(hash)
        hash = Homebrew::API.merge_variations(hash).dup

        if (caveats = hash["caveats"])
          hash["caveats"] = Formulary.replace_placeholders(caveats)
        end

        hash["bottle_checksums"] = begin
          files = hash.dig("bottle", "stable", "files") || {}
          files.map do |tag, bottle_spec|
            {
              cellar: Utils.convert_to_string_or_symbol(bottle_spec.fetch("cellar")),
              tag.to_sym => bottle_spec.fetch("sha256"),
            }
          end
        end

        hash["bottle_rebuild"] = hash.dig("bottle", "stable", "rebuild")

        conflicts_with = hash["conflicts_with"] || []
        conflicts_with_reasons = hash["conflicts_with_reasons"] || []
        hash["conflicts"] = conflicts_with.zip(conflicts_with_reasons).map do |name, reason|
          if reason.present?
            [name, { because: reason }]
          else
            [name, {}]
          end
        end

        if (deprecate_args = hash["deprecate_args"])
          deprecate_args = deprecate_args.dup.transform_keys(&:to_sym)
          deprecate_args[:because] =
            DeprecateDisable.to_reason_string_or_symbol(deprecate_args[:because], type: :formula)
          hash["deprecate_args"] = deprecate_args
        end

        if (disable_args = hash["disable_args"])
          disable_args = disable_args.dup.transform_keys(&:to_sym)
          disable_args[:because] = DeprecateDisable.to_reason_string_or_symbol(disable_args[:because], type: :formula)
          hash["disable_args"] = disable_args
        end

        hash["head_dependency_hash"] = hash["head_dependencies"]

        hash["head_url_args"] = begin
          # Fall back to "" to satisfy the type checker. If the head URL is missing, head_present will be false.
          url = hash.dig("urls", "head", "url") || ""
          specs = {
            branch: hash.dig("urls", "head", "branch"),
            using:  hash.dig("urls", "head", "using")&.to_sym,
          }.compact_blank
          [url, specs]
        end

        if (keg_only_hash = hash["keg_only_reason"])
          reason = Utils.convert_to_string_or_symbol(keg_only_hash.fetch("reason"))
          explanation = keg_only_hash["explanation"]
          hash["keg_only_args"] = [reason, explanation].compact
        end

        hash["license"] = SPDX.string_to_license_expression(hash["license"])

        hash["link_overwrite_paths"] = hash["link_overwrite"]

        if (reason = hash["no_autobump_message"])
          reason = reason.to_sym if NO_AUTOBUMP_REASONS_LIST.key?(reason.to_sym)
          hash["no_autobump_args"] = { because: reason }
        end

        if (condition = hash["pour_bottle_only_if"])
          hash["pour_bottle_args"] = { only_if: condition.to_sym }
        end

        hash["requirements_array"] = hash["requirements"]

        hash["ruby_source_checksum"] = hash.dig("ruby_source_checksum", "sha256")

        if (service_hash = hash["service"])
          service_hash = Homebrew::Service.from_hash(service_hash)

          hash["service_run_args"], hash["service_run_kwargs"] = case (run = service_hash[:run])
          when Hash
            [[], run]
          when Array, String
            [[run], {}]
          else
            [[], {}]
          end

          hash["service_name_args"] = service_hash[:name]

          hash["service_args"] = service_hash.filter_map do |key, arg|
            [key.to_sym, arg] if key != :name && key != :run
          end
        end

        hash["stable_checksum"] = hash.dig("urls", "stable", "checksum")

        hash["stable_dependency_hash"] = {
          "dependencies"             => hash["dependencies"] || [],
          "build_dependencies"       => hash["build_dependencies"] || [],
          "test_dependencies"        => hash["test_dependencies"] || [],
          "recommended_dependencies" => hash["recommended_dependencies"] || [],
          "optional_dependencies"    => hash["optional_dependencies"] || [],
          "uses_from_macos"          => hash["uses_from_macos"] || [],
          "uses_from_macos_bounds"   => hash["uses_from_macos_bounds"] || [],
        }

        hash["stable_url_args"] = begin
          url = hash.dig("urls", "stable", "url")
          specs = {
            tag:      hash.dig("urls", "stable", "tag"),
            revision: hash.dig("urls", "stable", "revision"),
            using:    hash.dig("urls", "stable", "using")&.to_sym,
          }.compact_blank
          [url, specs]
        end

        hash["stable_version"] = hash.dig("versions", "stable")

        # Should match FormulaStruct::PREDICATES
        hash["bottle_present"] = hash["bottle"].present?
        hash["deprecate_present"] = hash["deprecate_args"].present?
        hash["disable_present"] = hash["disable_args"].present?
        hash["head_present"] = hash.dig("urls", "head").present?
        hash["keg_only_present"] = hash["keg_only_reason"].present?
        hash["no_autobump_message_present"] = hash["no_autobump_message"].present?
        hash["pour_bottle_present"] = hash["pour_bottle_only_if"].present?
        hash["service_present"] = hash["service"].present?
        hash["service_run_present"] = hash.dig("service", "run").present?
        hash["service_name_present"] = hash.dig("service", "name").present?
        hash["stable_present"] = hash.dig("urls", "stable").present?

        FormulaStruct.from_hash(hash)
      end
    end
  end
end
