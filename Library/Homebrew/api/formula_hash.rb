# typed: strict
# frozen_string_literal: true

# require "utils/bottles"

require "api/generator_mixin"

module Homebrew
  module API
    class FormulaHash < T::Struct
      include GeneratorMixin

      class BottleHash < T::Struct
        include GeneratorMixin

        elem :rebuild, Integer
        elem :cellar, String, default: ":any", from: ["files", bottle_tag, "cellar"]
        elem :sha256, String, from: ["files", bottle_tag, "sha256"]
      end

      class DependencyHash < T::Struct
        include GeneratorMixin

        elem :runtime, T::Array[String], from: "dependencies"
        elem :build, T::Array[String], from: "build_dependencies"
        elem :test, T::Array[String], from: "test_dependencies"
      end

      class HeadURLHash < T::Struct
        include GeneratorMixin

        elem :url, String
        elem :branch, String
        elem :using, String
      end

      class KegOnlyReasonHash < T::Struct
        include GeneratorMixin

        elem :reason, String
        elem :explanation, String
      end

      # # TODO: simplify this
      # class RequirementHash < T::Struct
      #   include GeneratorMixin

      #   elem :name, String
      #   elem :cask, String
      #   elem :download, String
      #   elem :version, String
      #   elem :contexts, T::Array[T.untyped]
      #   elem :specs, T::Array[T.untyped]
      # end

      class ServiceHash < T::Struct
        include GeneratorMixin

        class KeepAlive < T::Struct
          include GeneratorMixin

          elem :always, T::Boolean
          elem :crashed, T::Boolean
          elem :path, String
          elem :successful_exit, T::Boolean
        end

        class NameHash < T::Struct
          include GeneratorMixin

          elem :macos, String
          elem :linux, String
        end

        class RunHash < T::Struct
          include GeneratorMixin

          elem :macos, T::Array[String]
          elem :linux, T::Array[String]
          elem :all, T::Array[String]
        end

        elem :name, hash_as: NameHash
        elem :run, hash_as: RunHash do |h|
          case (run = h["run"])
          when Hash, nil
            run
          else
            { "all" => Array(run) }
          end
        end
        elem :run_type, String
        elem :interval, Integer
        elem :cron, String
        elem :keep_alive, hash_as: KeepAlive
        elem :launch_only_once, T::Boolean
        elem :require_root, T::Boolean
        elem :environment_variables, T::Hash[String, String]
        elem :working_dir, String
        elem :root_dir, String
        elem :input_path, String
        elem :log_path, String
        elem :error_log_path, String
        elem :restart_delay, Integer
        elem :process_type, String
        elem :macos_legacy_timers, T::Boolean
        elem :sockets, T::Array[String] do |h|
          Array(h["sockets"])
        end
      end

      class StableURLHash < T::Struct
        include GeneratorMixin

        elem :url, String
        elem :tag, String
        elem :revision, String
        elem :using, String
        elem :checksum, String
      end

      # class UsesFromMacOSHash < T::Struct
      #   include GeneratorMixin

      #   elem :context, Symbol
      #   elem :since, String
      # end

      elem :aliases, T::Array[String]
      elem :bottle, hash_as: BottleHash, from: ["bottle", "stable"]
      elem :caveats, String

      # elem :conflicts_with, T::Array[String] # TODO: simplify as a hash?
      # elem :conflicts_with_reasons, T::Array[String]

      elem :deprecation_date, String
      elem :deprecation_reason, String
      elem :deprecation_replacement_cask, String
      elem :deprecation_replacement_formula, String
      elem :desc, String
      elem :disable_date, String
      elem :disable_reason, String
      elem :disable_replacement_cask, String
      elem :disable_replacement_formula, String
      elem :head_dependencies, hash_as: DependencyHash, from: "head_dependencies"
      elem :head_url, hash_as: HeadURLHash, from: ["urls", "head"]
      elem :homepage, String
      elem :keg_only_reason, hash_as: KegOnlyReasonHash
      elem :license, String
      elem :link_overwrite, T::Array[String]
      elem :no_autobump_msg, String
      elem :oldnames, T::Array[String]
      elem :post_install_defined, T::Boolean
      elem :pour_bottle_only_if, String # TODO: symbolify

      #     requirements:                    T::Array[RequirementHash],

      elem :revision, Integer
      elem :ruby_source_sha256, String, from: ["ruby_source_checksum", "sha256"]
      elem :service, hash_as: ServiceHash
      elem :stable_dependencies, hash_as: DependencyHash, from: []
      elem :stable_url, hash_as: StableURLHash, from: ["urls", "stable"]
      elem :stable_version, String, from: ["stable", "version"]

      #     uses_from_macos:                 T::Hash[String, UsesFromMacOSHash],

      elem :version_scheme, Integer
      elem :versioned_formulae, T::Array[String]
    end

    #     uses_from_macos_bounds = hash.fetch("uses_from_macos_bounds", [])
    #     hash["uses_from_macos"] = hash["uses_from_macos"].zip(uses_from_macos_bounds).to_h do |name, bounds|
    #       name, context = if name.is_a?(Hash)
    #         [name.keys.first, name.values.first.to_sym]
    #       else
    #         [name, nil]
    #       end
    #       [name, UsesFromMacOSHash.new(context:, since: bounds["since"])]
    #     end
  end
end
