# typed: strict
# frozen_string_literal: true

module Homebrew
  module API
    class CaskStruct < T::Struct
      sig { params(cask_hash: T::Hash[String, T.untyped], ignore_types: T::Boolean).returns(CaskStruct) }
      def self.from_hash(cask_hash, ignore_types: false)
        return super(cask_hash) if ignore_types

        cask_hash = ::Cask::Cask.deep_remove_placeholders(cask_hash)
        cask_hash = cask_hash.transform_keys(&:to_sym)
                             .slice(*decorator.all_props)
                             .compact_blank
        new(**cask_hash)
      end

      PREDICATES = [
        :auto_updates,
        :caveats,
        :conflicts,
        :container,
        :depends_on,
        :deprecate,
        :desc,
        :disable,
        :homepage,
      ].freeze

      EMPTY_BLOCK = T.let(-> {}.freeze, T.proc.void)
      EMPTY_BLOCK_PLACEHOLDER = :empty_block

      ArtifactArgs = T.type_alias do
        [
          Symbol,
          T::Array[T.anything],
          T::Hash[Symbol, T.anything],
          T.nilable(T.proc.void),
        ]
      end

      PREDICATES.each do |predicate_name|
        present_method_name = :"#{predicate_name}_present"
        predicate_method_name = :"#{predicate_name}?"

        const present_method_name, T::Boolean, default: false

        define_method(predicate_method_name) do
          send(present_method_name)
        end
      end

      DependsOnArgs = T.type_alias do
        T::Hash[
          # Keys are dependency types like :macos, :arch, :cask, :formula
          Symbol,
          # Values can be any of:
          T.any(
            # Strings like ">= :catalina" for :macos
            String,
            # Symbols like :intel or :arm64 for :arch
            Symbol,
            # Array of strings or symbols for :cask and :formula
            T::Array[T.any(String, Symbol)],
          ),
        ]
      end

      # Changes to this struct must be mirrored in Homebrew::API::Cask.generate_cask_struct_hash
      const :auto_updates, T::Boolean, default: false
      const :caveats_rosetta, T::Boolean, default: false
      const :conflicts_with_args, T::Hash[Symbol, T::Array[String]], default: {}
      const :container_args, { nested: T.nilable(String), type: T.nilable(Symbol) },
            default: { nested: nil, type: nil }
      const :depends_on_args, DependsOnArgs, default: {}
      const :deprecate_args, T::Hash[Symbol, T.nilable(T.any(String, Symbol))], default: {}
      const :desc, T.nilable(String)
      const :disable_args, T::Hash[Symbol, T.nilable(T.any(String, Symbol))], default: {}
      const :homepage, T.nilable(String)
      const :languages, T::Array[String], default: []
      const :names, T::Array[String], default: []
      const :renames, T::Array[[String, String]], default: []
      const :ruby_source_checksum, T::Hash[Symbol, T.nilable(String)], default: { sha256: nil }
      const :ruby_source_path, T.nilable(String)
      const :sha256, T.any(String, Symbol)
      const :tap_string, T.nilable(String)
      const :url_args, T::Array[String], default: []
      const :url_kwargs, T::Hash[Symbol, T.anything], default: {}
      const :version, T.any(String, Symbol)

      sig { params(other: T.anything).returns(T::Boolean) }
      def ==(other)
        case other
        when CaskStruct
          serialize == other.serialize
        else
          false
        end
      end

      sig { params(appdir: T.any(Pathname, String)).returns(T::Array[ArtifactArgs]) }
      def artifacts(appdir:)
        deep_remove_placeholders(raw_artifacts, appdir.to_s)
      end

      sig { params(appdir: T.any(Pathname, String)).returns(T.nilable(String)) }
      def caveats(appdir:)
        deep_remove_placeholders(raw_caveats, appdir.to_s)
      end

      sig { returns(T::Hash[String, T.untyped]) }
      def serialize
        hash = self.class.decorator.all_props.filter_map do |prop|
          next if PREDICATES.any? { |predicate| prop == :"#{predicate}_present" }

          [prop.to_s, send(prop)]
        end.to_h

        hash["raw_artifacts"] = raw_artifacts.map do |artifact|
          serialize_artifact_args(artifact)
        end

        hash = ::Utils.deep_stringify_symbols(hash)
        ::Utils.deep_compact_blank(hash)
      end

      sig { params(hash: T::Hash[String, T.untyped]).returns(CaskStruct) }
      def self.deserialize(hash)
        hash = ::Utils.deep_unstringify_symbols(hash)

        PREDICATES.each do |name|
          source_value = case name
          when :auto_updates then hash["auto_updates"]
          when :caveats      then hash["raw_caveats"]
          when :conflicts    then hash["conflicts_with_args"]
          when :desc         then hash["desc"]
          when :homepage     then hash["homepage"]
          else                    hash["#{name}_args"]
          end

          hash["#{name}_present"] = source_value.present?
        end

        hash["raw_artifacts"] = if (raw_artifacts = hash["raw_artifacts"])
          raw_artifacts.map { |artifact| deserialize_artifact_args(artifact) }
        end

        from_hash(hash)
      end

      sig { params(artifact: ArtifactArgs).returns(T::Array[T.untyped]) }
      def serialize_artifact_args(artifact)
        key, args, kwargs, block = artifact

        # We can't serialize Procs, so always use an empty block placeholder to be deserialized as `-> {}`.
        block = EMPTY_BLOCK_PLACEHOLDER unless block.nil?

        [key, args, kwargs, block]
      end

      # Format artifact args pairs into proper [key, args, kwargs, block] format since serialization removed blanks.
      sig {
        params(
          args: T.any(
            [Symbol],
            [Symbol, T::Array[T.anything]],
            [Symbol, T::Hash[Symbol, T.anything]],
            [Symbol, Symbol],
            [Symbol, T::Array[T.anything], T::Hash[Symbol, T.anything]],
            [Symbol, T::Array[T.anything], Symbol],
            [Symbol, T::Hash[Symbol, T.anything], Symbol],
            [Symbol, T::Array[T.anything], T::Hash[Symbol, T.anything], Symbol],
          ),
        ).returns(ArtifactArgs)
      }
      def self.deserialize_artifact_args(args)
        case args
        in [key]                                                        then [key, [], {}, nil]
        in [key, Array => array]                                        then [key, array, {}, nil]
        in [key, Hash => hash]                                          then [key, [], hash, nil]
        in [key, EMPTY_BLOCK_PLACEHOLDER]                               then [key, [], {}, EMPTY_BLOCK]
        in [key, Array => array, Hash => hash]                          then [key, array, hash, nil]
        in [key, Array => array, EMPTY_BLOCK_PLACEHOLDER]               then [key, array, {}, EMPTY_BLOCK]
        in [key, Hash => hash, EMPTY_BLOCK_PLACEHOLDER]                 then [key, [], hash, EMPTY_BLOCK]
        in [key, Array => array, Hash => hash, EMPTY_BLOCK_PLACEHOLDER] then [key, array, hash, EMPTY_BLOCK]
        else
          # The block argument should only ever be EMPTY_BLOCK_PLACEHOLDER or nil, so we should never reach this case.
          raise "Invalid artifact args: #{args.inspect}"
        end
      end

      private

      const :raw_artifacts, T::Array[ArtifactArgs], default: []
      const :raw_caveats, T.nilable(String)

      sig {
        type_parameters(:U)
          .params(
            value:  T.type_parameter(:U),
            appdir: String,
          )
          .returns(T.type_parameter(:U))
      }
      def deep_remove_placeholders(value, appdir)
        value = case value
        when Hash
          value.transform_values do |v|
            deep_remove_placeholders(v, appdir)
          end
        when Array
          value.map do |v|
            deep_remove_placeholders(v, appdir)
          end
        when String
          value.gsub(HOMEBREW_HOME_PLACEHOLDER, Dir.home)
               .gsub(HOMEBREW_PREFIX_PLACEHOLDER, HOMEBREW_PREFIX)
               .gsub(HOMEBREW_CELLAR_PLACEHOLDER, HOMEBREW_CELLAR)
               .gsub(HOMEBREW_CASK_APPDIR_PLACEHOLDER, appdir)
        else
          value
        end

        T.cast(value, T.type_parameter(:U))
      end
    end
  end
end
