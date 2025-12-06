# typed: strict
# frozen_string_literal: true

require "utils/bottles"

module Homebrew
  module API
    module CompactSerializable
      extend T::Helpers

      requires_ancestor { T::Struct }

      sig { params(args: T.anything).returns(T::Hash[String, T.untyped]) }
      def serialize(*args)
        super.compact_blank
      end
    end

    module StringifySymbols
      sig { params(value: T.nilable(T.any(String, Symbol))).returns(T.nilable(String)) }
      def to_symbolized_string(value)
        return value unless value.is_a? Symbol

        ":#{value}"
      end
    end

    class BottleHash < T::Struct
      include CompactSerializable

      const :rebuild, T.nilable(Integer), default: 0
      const :cellar, T.nilable(String), default: ":any"
      const :sha256, T.nilable(String)
    end

    class DependencyHash < T::Struct
      include CompactSerializable

      const :name, String
      const :context, T.nilable(Symbol)
    end

    class HeadURLHash < T::Struct
      include CompactSerializable

      const :url, String
      const :branch, T.nilable(String)
      const :using, T.nilable(String)
    end

    # TODO: simplify this
    class RequirementHash < T::Struct
      include CompactSerializable

      const :name, String
      const :cask, T.nilable(String)
      const :download, T.nilable(String)
      const :version, T.nilable(String)
      const :contexts, T::Array[T.untyped]
      const :specs, T::Array[T.untyped]
    end

    class ServiceHash < T::Struct
      include CompactSerializable

      const :name, String
      const :run, T.nilable(String)
      const :run_type, T.nilable(String)
      const :interval, T.nilable(Integer)
      const :cron, T.nilable(String)
      const :keep_alive, T.nilable(T::Boolean)
      const :launch_only_once, T.nilable(T::Boolean)
      const :require_root, T.nilable(T::Boolean)
      const :environment_variables, T.nilable(T::Hash[String, String])
      const :working_dir, T.nilable(String)
      const :root_dir, T.nilable(String)
      const :input_path, T.nilable(String)
      const :log_path, T.nilable(String)
      const :error_log_path, T.nilable(String)
      const :restart_delay, T.nilable(Integer)
      const :process_type, T.nilable(String)
      const :macos_legacy_timers, T.nilable(T::Boolean)
      const :sockets, T.nilable(T::Array[String])
    end

    class StableURLHash < T::Struct
      include CompactSerializable

      const :url, String
      const :tag, T.nilable(String)
      const :revision, T.nilable(String)
      const :using, T.nilable(String)
      const :checksum, T.nilable(String)
    end

    class UsesFromMacOSHash < T::Struct
      include CompactSerializable

      const :context, T.nilable(Symbol)
      const :since, T.nilable(String)
    end

    class FormulaHash < T::Struct
      include CompactSerializable
      extend StringifySymbols

      DEPENDENCY_CONTEXTS = T.let([:build, :test, :recommended, :optional].freeze, T::Array[Symbol])

      PROPERTIES = T.let({
        aliases:                         T::Array[String],
        bottle:                          BottleHash,
        caveats:                         T::Array[String],
        conflicts_with:                  T::Array[String],
        conflicts_with_reasons:          T::Array[String],
        deprecation_date:                String,
        deprecation_reason:              String,
        deprecation_replacement_cask:    String,
        deprecation_replacement_formula: String,
        desc:                            String,
        disable_date:                    String,
        disable_reason:                  String,
        disable_replacement_cask:        String,
        disable_replacement_formula:     String,
        head_dependencies:               T::Array[DependencyHash],
        head_url:                        HeadURLHash,
        homepage:                        String,
        keg_only_reason:                 String,
        license:                         String,
        link_overwrite:                  T::Array[String],
        no_autobump_msg:                 String,
        oldnames:                        T::Array[String],
        post_install_defined:            T::Boolean,
        pour_bottle_only_if:             Symbol,
        requirements:                    T::Array[RequirementHash],
        revision:                        Integer,
        ruby_source_sha256:              String,
        ruby_source_path:                String,
        service:                         T::Hash[String, T.untyped],
        stable_dependencies:             T::Array[DependencyHash],
        stable_url:                      StableURLHash,
        stable_version:                  String,
        tap_git_head:                    String,
        uses_from_macos:                 T::Hash[String, UsesFromMacOSHash],
        version_scheme:                  Integer,
        versioned_formulae:              T::Array[String],
      }.freeze, T::Hash[Symbol, T.untyped])

      PROPERTIES.each do |property, type|
        const property, T.nilable(type)
      end

      sig { params(hash: T::Hash[String, T.untyped], bottle_tag: ::Utils::Bottles::Tag).returns(FormulaHash) }
      def self.from_hash(hash, bottle_tag: ::Utils::Bottles.tag)
        hash = Homebrew::API.merge_variations(hash, bottle_tag: bottle_tag)

        hash["bottle"] = begin
          bottle_collector = ::Utils::Bottles::Collector.new
          hash.dig("bottle", "stable", "files")&.each do |tag, data|
            tag = ::Utils::Bottles::Tag.from_symbol(tag)
            bottle_collector.add tag, checksum: Checksum.new(data["sha256"]), cellar: :any
          end
          BottleHash.new(
            rebuild: hash.dig("bottle", "stable", "rebuild"),
            cellar:  to_symbolized_string(bottle_collector.specification_for(bottle_tag)&.cellar),
            sha256:  bottle_collector.specification_for(bottle_tag)&.checksum&.to_s,
          )
        end

        head_dependencies = []
        hash.dig("head_dependencies", "dependencies")&.each do |dep_name|
          head_dependencies << DependencyHash.new(name: dep_name)
        end
        DEPENDENCY_CONTEXTS.each do |context|
          hash.dig("head_dependencies", "#{context}_dependencies")&.each do |dep_name|
            head_dependencies << DependencyHash.new(name: dep_name, context:)
          end
        end
        hash["head_dependencies"] = head_dependencies

        hash["head_url"] = if (specs = hash["head_url"])
          HeadURLHash.new(**specs.transform_keys(&:to_sym))
        end

        hash["requirements"] = hash["requirements"]&.map do |specs|
          RequirementHash.new(**specs.transform_keys(&:to_sym))
        end

        hash["service"] = if (specs = hash["service"])
          ServiceHash.new(**specs.transform_keys(&:to_sym))
        end

        hash["stable_url"] = if (specs = hash["stable_url"])
          StableURLHash.new(**specs.transform_keys(&:to_sym))
        end

        hash["ruby_source_sha256"] = hash.dig("ruby_source_checksum", "sha256")

        stable_dependencies = hash.fetch("dependencies", []).map do |dep_name|
          DependencyHash.new(name: dep_name)
        end
        DEPENDENCY_CONTEXTS.each do |context|
          hash.fetch("#{context}_dependencies", []).each do |dep_name|
            stable_dependencies << DependencyHash.new(name: dep_name, context:)
          end
        end
        hash["stable_dependencies"] = stable_dependencies

        hash["stable_version"] = hash.dig("stable", "version")

        uses_from_macos_bounds = hash.fetch("uses_from_macos_bounds", [])
        hash["uses_from_macos"] = hash["uses_from_macos"].zip(uses_from_macos_bounds).to_h do |name, bounds|
          name, context = if name.is_a?(Hash)
            [name.keys.first, name.values.first.to_sym]
          else
            [name, nil]
          end
          [name, UsesFromMacOSHash.new(context:, since: bounds["since"])]
        end

        new(**hash.transform_keys(&:to_sym).slice(*PROPERTIES.keys))
      end
    end
  end
end
