# typed: strict
# frozen_string_literal: true

module Homebrew
  module API
    module Formula
      # Methods for generating FormulaStruct instances from API data.
      module FormulaStructGenerator
        module_function

        # `:codesign` and custom requirement classes are not supported.
        API_SUPPORTED_REQUIREMENTS = [:arch, :linux, :macos, :maximum_macos, :xcode].freeze
        private_constant :API_SUPPORTED_REQUIREMENTS

        DependencyHash = T.type_alias do
          T::Hash[
            # Keys are strings of the dependency type (e.g. "dependencies", "build_dependencies")
            String,
            # Values are arrays of either:
            T::Array[
              T.any(
                # Formula name: "foo"
                String,
                # Hash like { "foo" => :build } or { "foo" => [:build, :test] }
                T::Hash[
                  String,
                  T.any(Symbol, T::Array[Symbol]),
                ],
                # Hash like { since: :catalina } for uses_from_macos_bounds
                T::Hash[Symbol, Symbol],
              ),
            ],
          ]
        end

        RequirementsArray = T.type_alias do
          T::Array[T::Hash[String, T.untyped]]
        end

        sig { params(hash: T::Hash[String, T.untyped], bottle_tag: Utils::Bottles::Tag).returns(FormulaStruct) }
        def generate_formula_struct_hash(hash, bottle_tag: Utils::Bottles.tag)
          hash = Homebrew::API.merge_variations(hash, bottle_tag:).dup

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
            disable_args[:because] =
              DeprecateDisable.to_reason_string_or_symbol(disable_args[:because], type: :formula)
            hash["disable_args"] = disable_args
          end

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

          # Do dependency processing last because it's more involved and depends on other fields
          hash["requirements_array"] = hash["requirements"]

          stable_dependency_hash = {
            "dependencies"             => hash["dependencies"] || [],
            "build_dependencies"       => hash["build_dependencies"] || [],
            "test_dependencies"        => hash["test_dependencies"] || [],
            "recommended_dependencies" => hash["recommended_dependencies"] || [],
            "optional_dependencies"    => hash["optional_dependencies"] || [],
            "uses_from_macos"          => hash["uses_from_macos"] || [],
            "uses_from_macos_bounds"   => hash["uses_from_macos_bounds"] || [],
          }

          stable_dependencies, stable_uses_from_macos = process_dependencies_and_requirements(
            stable_dependency_hash,
            hash["requirements_array"],
            :stable,
          )

          head_dependencies, head_uses_from_macos = process_dependencies_and_requirements(
            hash["head_dependencies"],
            hash["requirements_array"],
            :head,
          )

          hash["stable_dependencies"] = stable_dependencies
          hash["stable_uses_from_macos"] = stable_uses_from_macos
          hash["head_dependencies"] = head_dependencies
          hash["head_uses_from_macos"] = head_uses_from_macos

          # Should match FormulaStruct::PREDICATES
          hash["bottle_present"] = hash["bottle"].present?
          hash["deprecate_present"] = hash["deprecate_args"].present?
          hash["disable_present"] = hash["disable_args"].present?
          hash["head_present"] = hash.dig("urls", "head").present?
          hash["keg_only_present"] = hash["keg_only_reason"].present?
          hash["no_autobump_present"] = hash["no_autobump_message"].present?
          hash["pour_bottle_present"] = hash["pour_bottle_only_if"].present?
          hash["service_present"] = hash["service"].present?
          hash["service_run_present"] = hash.dig("service", "run").present?
          hash["service_name_present"] = hash.dig("service", "name").present?
          hash["stable_present"] = hash.dig("urls", "stable").present?

          FormulaStruct.from_hash(hash)
        end

        sig {
          params(deps_hash: T.nilable(DependencyHash), requirements_array: T.nilable(RequirementsArray), spec: Symbol)
            .returns([T::Array[FormulaStruct::DependsOnArgs], T::Array[FormulaStruct::UsesFromMacOSArgs]])
        }
        def process_dependencies_and_requirements(deps_hash, requirements_array, spec)
          deps, uses_from_macos = if deps_hash.present?
            deps_hash = symbolize_dependency_hash(deps_hash)
            [process_dependencies(deps_hash), process_uses_from_macos(deps_hash)]
          else
            [[], []]
          end

          requirements = if requirements_array.present?
            process_requirements(requirements_array, spec)
          else
            []
          end

          [deps + requirements, uses_from_macos]
        end

        # Convert from { "dependencies" => ["foo", { "bar" => "build" }, { "baz" => ["build", "test"] }] }
        #           to { "dependencies" => ["foo", { "bar" => :build }, { "baz" => [:build, :test] }] }
        sig { params(hash: DependencyHash).returns(DependencyHash) }
        def symbolize_dependency_hash(hash)
          hash = hash.dup

          if (uses_from_macos_bounds = hash["uses_from_macos_bounds"])
            uses_from_macos_bounds = T.cast(uses_from_macos_bounds, T::Array[T::Hash[Symbol, Symbol]])
            hash["uses_from_macos_bounds"] = uses_from_macos_bounds.map(&:deep_symbolize_keys)
          end

          hash.transform_values do |deps|
            deps.map do |dep|
              next dep unless dep.is_a?(Hash)

              dep.transform_values do |types|
                case types
                when Array
                  types.map(&:to_sym)
                else
                  types.to_sym
                end
              end
            end
          end
        end

        sig { params(deps_hash: DependencyHash).returns(T::Array[FormulaStruct::DependsOnArgs]) }
        def process_dependencies(deps_hash)
          dependencies = deps_hash.fetch("dependencies", [])
          dependencies + [:build, :test, :recommended, :optional].filter_map do |type|
            deps_hash["#{type}_dependencies"]&.map do |dep|
              { dep => type }
            end
          end.flatten(1)
        end

        sig { params(requirements_array: RequirementsArray, spec: Symbol).returns(T::Array[FormulaStruct::DependsOnArgs]) }
        def process_requirements(requirements_array, spec)
          requirements_array.filter_map do |req|
            next unless req["specs"].include?(spec.to_s)

            req_name = req["name"].to_sym
            next if API_SUPPORTED_REQUIREMENTS.exclude?(req_name)

            req_version = case req_name
            when :arch
              req["version"]&.to_sym
            when :macos, :maximum_macos
              MacOSVersion::SYMBOLS.key(req["version"])
            else
              req["version"]
            end

            req_tags = []
            req_tags << req_version if req_version.present?
            req_tags += req.fetch("contexts", []).map do |tag|
              case tag
              when String
                tag.to_sym
              when Hash
                tag.deep_transform_keys(&:to_sym)
              else
                tag
              end
            end

            if req_tags.empty?
              req_name
            else
              { req_name => req_tags }
            end
          end
        end

        sig { params(deps_hash: DependencyHash).returns(T::Array[FormulaStruct::UsesFromMacOSArgs]) }
        def process_uses_from_macos(deps_hash)
          uses_from_macos = deps_hash.fetch("uses_from_macos", [])

          uses_from_macos_bounds = deps_hash.fetch("uses_from_macos_bounds", [])
          uses_from_macos_bounds = T.cast(uses_from_macos_bounds, T::Array[T::Hash[Symbol, Symbol]])

          uses_from_macos.zip(uses_from_macos_bounds).map do |entry, bounds|
            bounds ||= {}
            bounds = bounds.transform_keys(&:to_sym).transform_values(&:to_sym)

            if entry.is_a?(Hash)
              # The key is the dependency name, the value is the dep type. Only the type should be a symbol
              entry = entry.deep_transform_values(&:to_sym)
              # When passing both a dep type and bounds, uses_from_macos expects them both in the first argument
              entry = entry.merge(bounds)
              [entry, {}]
            else
              [entry, bounds]
            end
          end
        end
      end
    end
  end
end
