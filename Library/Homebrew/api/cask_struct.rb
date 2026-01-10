# typed: strict
# frozen_string_literal: true

module Homebrew
  module API
    class CaskStruct < T::Struct
      sig { params(cask_hash: T::Hash[String, T.untyped], ignore_types: T::Boolean).returns(CaskStruct) }
      def self.from_hash(cask_hash, ignore_types: false)
        return super(cask_hash) if ignore_types

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
      const :conflicts_with_args, T::Hash[Symbol, T::Array[String]], default: {}
      const :container_args, T::Hash[Symbol, T.any(Symbol, T.anything)], default: {}
      const :depends_on_args, DependsOnArgs, default: {}
      const :deprecate_args, T::Hash[Symbol, T.nilable(T.any(String, Symbol))], default: {}
      const :desc, T.nilable(String)
      const :disable_args, T::Hash[Symbol, T.nilable(T.any(String, Symbol))], default: {}
      const :homepage, T.nilable(String)
      const :languages, T::Array[String], default: []
      const :names, T::Array[String], default: []
      const :renames, T::Array[[String, String]], default: []
      const :ruby_source_checksum, T::Hash[Symbol, String]
      const :ruby_source_path, T.nilable(String)
      const :sha256, T.any(String, Symbol)
      const :tap_git_head, T.nilable(String)
      const :tap_string, T.nilable(String)
      const :url_args, T::Array[String], default: []
      const :url_kwargs, T::Hash[Symbol, T.anything], default: {}
      const :version, T.any(String, Symbol)

      sig { params(appdir: T.any(Pathname, String)).returns(T::Array[ArtifactArgs]) }
      def artifacts(appdir:)
        deep_remove_placeholders(raw_artifacts, appdir.to_s)
      end

      sig { params(appdir: T.any(Pathname, String)).returns(T.nilable(String)) }
      def caveats(appdir:)
        deep_remove_placeholders(raw_caveats, appdir.to_s)
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
