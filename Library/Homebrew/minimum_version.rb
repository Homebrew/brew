# typed: strict
# frozen_string_literal: true

require "cask/cask"
require "cask/dsl/version"
require "formula"
require "pkg_version"

module Homebrew
  module MinimumVersion
    sig {
      params(formula: Formula, minimum_version: T.nilable(String), fetch_head: T::Boolean).returns(T::Array[Keg])
    }
    def self.formula_outdated_kegs(formula, minimum_version, fetch_head:)
      return formula.outdated_kegs(fetch_head:) if minimum_version.blank?

      minimum_pkg_version = PkgVersion.parse(minimum_version)
      formula.installed_kegs.select do |keg|
        keg.version_scheme < formula.version_scheme ||
          (keg.version_scheme == formula.version_scheme && keg.version < minimum_pkg_version)
      end
    end

    sig { params(cask: Cask::Cask, minimum_version: String).returns(T::Boolean) }
    def self.cask_installed_below?(cask, minimum_version)
      minimum_cask_version = comparable_cask_version(minimum_version)
      raise UsageError, "invalid `--minimum-version`: #{minimum_version}" if minimum_cask_version.nil?

      installed_version = cask.installed_version
      return false if installed_version.blank?

      installed_cask_version = comparable_cask_version(installed_version)
      return false if installed_cask_version.nil?

      installed_cask_version < minimum_cask_version
    end

    sig { params(version: String).returns(T.nilable(::Version)) }
    def self.comparable_cask_version(version)
      cask_version = Cask::DSL::Version.new(version)
      return if cask_version.latest?

      ::Version.new(cask_version.to_s)
    rescue TypeError
      nil
    end
    private_class_method :comparable_cask_version
  end
end
