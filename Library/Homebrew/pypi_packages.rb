# typed: strict
# frozen_string_literal: true

# Helper class for `pypi_packages` DSL.
# @api internal
class PypiPackages
  sig { returns(T.nilable(String)) }
  attr_reader :package_name

  sig { returns(T::Array[String]) }
  attr_reader :extra_packages

  sig { returns(T::Array[String]) }
  attr_reader :exclude_packages

  sig { returns(T::Array[String]) }
  attr_reader :dependencies

  sig { params(tap: T.nilable(Tap), formula_name: String).returns(T.attached_class) }
  def self.from_json_file(tap, formula_name)
    list_entry = tap&.pypi_formula_mappings&.fetch(formula_name, nil)

    return new(defined_pypi_mapping: false) if list_entry.nil?

    case T.cast(list_entry, T.any(FalseClass, String, T::Hash[String, T.any(String, T::Array[String])]))
    when false
      new needs_manual_update: true
    when String
      new package_name: list_entry
    when Hash
      package_name = list_entry["package_name"]
      extra_packages = list_entry.fetch("extra_packages", [])
      exclude_packages = list_entry.fetch("exclude_packages", [])
      dependencies = list_entry.fetch("dependencies", [])

      new package_name:, extra_packages:, exclude_packages:, dependencies:
    end
  end

  sig {
    params(
      package_name:         T.nilable(String),
      extra_packages:       T::Array[String],
      exclude_packages:     T::Array[String],
      dependencies:         T::Array[String],
      needs_manual_update:  T::Boolean,
      defined_pypi_mapping: T::Boolean,
    ).void
  }
  def initialize(
    package_name: nil,
    extra_packages: [],
    exclude_packages: [],
    dependencies: [],
    needs_manual_update: false,
    defined_pypi_mapping: true
  )
    @package_name = T.let(package_name, T.nilable(String))
    @extra_packages = T.let(extra_packages, T::Array[String])
    @exclude_packages = T.let(exclude_packages, T::Array[String])
    @dependencies = T.let(dependencies, T::Array[String])
    @needs_manual_update = T.let(needs_manual_update, T::Boolean)
    @defined_pypi_mapping = T.let(defined_pypi_mapping, T::Boolean)
  end

  sig { returns(T::Boolean) }
  def defined_pypi_mapping? = @defined_pypi_mapping

  sig { returns(T::Boolean) }
  def needs_manual_update? = @needs_manual_update
end
