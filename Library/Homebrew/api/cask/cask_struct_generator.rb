# typed: strict
# frozen_string_literal: true

module Homebrew
  module API
    module Cask
      # Methods for generating CaskStruct instances from API data.
      module CaskStructGenerator
        module_function

        # NOTE: this will be used to load installed cask JSON files,
        # so it must never fail with older JSON API versions
        sig { params(hash: T::Hash[String, T.untyped], bottle_tag: Utils::Bottles::Tag, ignore_types: T::Boolean).returns(CaskStruct) }
        def generate_cask_struct_hash(hash, bottle_tag: Homebrew::SimulateSystem.current_tag, ignore_types: false)
          hash = Homebrew::API.merge_variations(hash, bottle_tag:).dup.deep_symbolize_keys.transform_keys(&:to_s)

          hash["conflicts_with_args"] = hash["conflicts_with"]&.to_h

          hash["container_args"] = hash["container"]&.to_h do |key, value|
            next [key, value.to_sym] if key == :type

            [key, value]
          end

          if (depends_on = hash["depends_on"])
            hash["depends_on_args"] = process_depends_on(depends_on)
          end

          if (deprecate_args = hash["deprecate_args"])
            deprecate_args = deprecate_args.dup
            deprecate_args[:because] =
              DeprecateDisable.to_reason_string_or_symbol(deprecate_args[:because], type: :cask)
            hash["deprecate_args"] = deprecate_args
          end

          if (disable_args = hash["disable_args"])
            disable_args = disable_args.dup
            disable_args[:because] = DeprecateDisable.to_reason_string_or_symbol(disable_args[:because], type: :cask)
            hash["disable_args"] = disable_args
          end

          # Use explicit defaults rather than `nil` for absent keys: when runtime
          # type checking is disabled, `CaskStruct.from_hash` does not apply the
          # struct's prop defaults, so `nil` values would survive into the struct
          # and crash consumers that iterate them (installed cask JSON files omit
          # most keys).
          hash["names"] = hash["name"] || []

          if (artifacts = hash["artifacts"])
            hash["raw_artifacts"] = process_artifacts(artifacts)
          end

          hash["raw_caveats"] = hash["caveats"]

          hash["renames"] = hash["rename"]&.map do |operation|
            [operation[:from], operation[:to]]
          end || []

          hash["ruby_source_checksum"] = {
            sha256: hash.dig("ruby_source_checksum", :sha256),
          }.compact

          hash["ruby_source_path"] = hash["ruby_source_path"]&.to_s

          hash["sha256"] = hash["sha256"].to_s
          hash["sha256"] = :no_check if hash["sha256"] == "no_check"

          hash["tap_string"] = hash["tap"]

          hash["url_args"] = [hash["url"].to_s]

          if (url_specs = hash["url_specs"])
            hash["url_kwargs"] = process_url_specs(url_specs)
          end

          # Should match CaskStruct::PREDICATES
          hash["auto_updates_present"] = hash["auto_updates"].present?
          hash["caveats_present"] = hash["caveats"].present?
          hash["conflicts_present"] = hash["conflicts_with"].present?
          hash["container_present"] = hash["container"].present?
          hash["depends_on_present"] = hash["depends_on_args"].present?
          hash["deprecate_present"] = hash["deprecate_args"].present?
          hash["desc_present"] = hash["desc"].present?
          hash["disable_present"] = hash["disable_args"].present?
          hash["homepage_present"] = hash["homepage"].present?

          CaskStruct.from_hash(hash, ignore_types:)
        end

        sig { params(depends_on: T::Hash[Symbol, T.untyped]).returns(CaskStruct::DependsOnArgs) }
        def process_depends_on(depends_on)
          depends_on.to_h do |key, value|
            # Arch dependencies are encoded like `{ type: :intel, bits: 64 }`
            # but `depends_on arch:` only accepts `:intel` or `:arm64`
            if key == :arch
              next [:arch, :intel] if value.first[:type].to_sym == :intel

              next [:arch, :arm64]
            end
            next [key, :any] if key == :linux

            next [key, value] unless [:macos, :maximum_macos].include?(key)

            value = value.to_h if value.is_a?(MacOSRequirement)
            dep_type = value.keys.first
            next [key, :any] unless dep_type

            if dep_type.to_sym == :==
              version_symbols = value[dep_type].filter_map do |version|
                MacOSVersion::SYMBOLS.key(version)
              end
              next [key, version_symbols.presence]
            end

            version_symbol = value[dep_type].first
            next [key, :any] if version_symbol.blank?

            version_symbol = MacOSVersion::SYMBOLS.key(version_symbol)
            next [key, version_symbol] if [:>=, :<=].include?(dep_type.to_sym) && version_symbol

            version_dep = "#{dep_type} :#{version_symbol}" if version_symbol
            [key, version_dep]
          end.compact
        end

        sig { params(artifacts: T::Array[T::Hash[Symbol, T.untyped]]).returns(T::Array[CaskStruct::ArtifactArgs]) }
        def process_artifacts(artifacts)
          artifacts.map do |artifact|
            key = T.must(artifact.keys.first)

            # Pass an empty block to artifacts like postflight that can't be loaded from the API,
            # but need to be set to something.
            next [key, [], {}, Homebrew::API::CaskStruct::EMPTY_BLOCK] if artifact[key].nil?

            args = artifact[key]
            kwargs = if args.last.is_a?(Hash)
              args.pop
            else
              {}
            end
            [key, args, kwargs, nil]
          end
        end

        sig { params(url_specs: T::Hash[Symbol, T.untyped]).returns(T::Hash[Symbol, T.anything]) }
        def process_url_specs(url_specs)
          url_specs.to_h do |key, value|
            value = case key
            when :user_agent
              Utils.convert_to_string_or_symbol(value)
            when :using
              value.to_sym
            else
              value
            end

            [key, value]
          end.compact_blank
        end
      end
    end
  end
end
