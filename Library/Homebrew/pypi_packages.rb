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

  sig {
    params(
      package_name:     T.nilable(String),
      extra_packages:   T::Array[String],
      exclude_packages: T::Array[String],
      dependencies:     T::Array[String],
    ).void
  }
  def initialize(
    package_name: nil,
    extra_packages: [],
    exclude_packages: [],
    dependencies: []
  )
    @package_name = package_name
    @extra_packages = extra_packages
    @exclude_packages = exclude_packages
    @dependencies = dependencies
  end
end
