# typed: strict
# frozen_string_literal: true

class FormulaStruct < T::Struct
  const :uses_from_macos, T::Array[T.any(String, T::Hash[String, String])], default: []
  const :requirements, T::Array[T::Hash[String, T.untyped]], default: []
  const :dependencies, T::Array[String], default: []
  const :build_dependencies, T::Array[String], default: []
  const :test_dependencies, T::Array[String], default: []
  const :recommended_dependencies, T::Array[String], default: []
  const :optional_dependencies, T::Array[String], default: []
  const :stable_dependencies, T::Hash[String, T::Array[String]], default: { dependencies: [], build_dependencies: [], test_dependencies: [], recommended_dependencies: [], optional_dependencies: [], uses_from_macos_bounds: [] }
  const :head_dependencies, T::Hash[String, T::Array[String]], default: { dependencies: [], build_dependencies: [], test_dependencies: [], recommended_dependencies: [], optional_dependencies: [], uses_from_macos_bounds: [] }
  const :caveats, T.nilable(String)
  const :desc, String
  const :homepage, String
  const :license, String
  const :revision, Integer, default: 0
  const :version_scheme, Integer, default: 0
  const :no_autobump_msg, T.nilable(String)
  const :pour_bottle_only_if, T.nilable(String)
  const :keg_only_reason, T.nilable(T::Hash[String, String])
  const :deprecation_date, T.nilable(String)
  const :deprecation_reason, T.nilable(String)
  const :deprecation_replacement_formula, T.nilable(String)
  const :deprecation_replacement_cask, T.nilable(String)
  const :disable_date, T.nilable(String)
  const :disable_reason, T.nilable(String)
  const :disable_replacement_formula, T.nilable(String)
  const :disable_replacement_cask, T.nilable(String)
  const :conflicts_with, T::Array[String], default: []
  const :conflicts_with_reasons, T::Array[String], default: []
  const :link_overwrite, T::Array[String], default: []
  const :post_install_defined, T::Boolean, default: false
  const :service, T.nilable(T::Hash[String, T.untyped])
  const :tap_git_head, String
  const :oldnames, T.nilable(T::Array[String])
  const :oldname, T.nilable(String)
  const :ruby_source_path, String
  const :ruby_source_checksum, T::Hash[String, String]
  const :urls, T::Hash[String, T::Hash[String, T.nilable(String)]]
  const :ruby_source_sha256, T.nilable(String)
  const :aliases, T::Array[String], default: []
  const :versioned_formulae, T::Array[String], default: []
  const :versions, T::Hash[String, String]
  const :bottle, T::Hash[String, T.untyped], default: {}
  const :uses_from_macos_bounds, T.nilable(T::Array[T::Hash[String, String]])

  sig { params(hash: T::Hash[String, T.untyped]).returns(FormulaStruct) }
  def self.from_hash(hash)
    hash["stable_dependencies"] ||= {
      "dependencies"             => hash["dependencies"] || [],
      "build_dependencies"       => hash["build_dependencies"] || [],
      "test_dependencies"        => hash["test_dependencies"] || [],
      "recommended_dependencies" => hash["recommended_dependencies"] || [],
      "optional_dependencies"    => hash["optional_dependencies"] || [],
      "uses_from_macos_bounds"   => hash["uses_from_macos_bounds"] || [],
    }

    super
  end
end
