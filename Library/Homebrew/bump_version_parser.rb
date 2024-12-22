# typed: strict
# frozen_string_literal: true

module Homebrew
  # Class handling architecture-specific version information.
  class BumpVersionParser
    sig { returns(T.nilable(T.any(Version, Cask::DSL::Version))) }
    attr_reader :arm, :general, :intel

    sig {
      params(general: T.nilable(T.any(Version, String)),
             arm:     T.nilable(T.any(Version, String)),
             intel:   T.nilable(T.any(Version, String))).void
    }
    def initialize(general: nil, arm: nil, intel: nil)
      @general = T.let(parse_version(general), T.nilable(T.any(Version, Cask::DSL::Version))) if general.present?
      @arm = T.let(parse_version(arm), T.nilable(T.any(Version, Cask::DSL::Version))) if arm.present?
      @intel = T.let(parse_version(intel), T.nilable(T.any(Version, Cask::DSL::Version))) if intel.present?

      return if @general.present?
      raise UsageError, "`--version` must not be empty." if arm.blank? && intel.blank?
      raise UsageError, "`--version-arm` must not be empty." if arm.blank?
      raise UsageError, "`--version-intel` must not be empty." if intel.blank?
    end

    sig {
      params(version: T.any(Version, String))
        .returns(T.nilable(T.any(Version, Cask::DSL::Version)))
    }
    def parse_version(version)
      if version.is_a?(Version)
        version
      elsif version.is_a?(String)
        parse_cask_version(version)
      end
    end

    sig { params(version: String).returns(T.nilable(Cask::DSL::Version)) }
    def parse_cask_version(version)
      if version == "latest"
        Cask::DSL::Version.new(:latest)
      else
        Cask::DSL::Version.new(version)
      end
    end

    sig { returns(T::Boolean) }
    def blank?
      @general.blank? && @arm.blank? && @intel.blank?
    end

    sig { params(other: T.untyped).returns(T::Boolean) }
    def ==(other)
      return false unless other.is_a?(BumpVersionParser)

      (general == other.general) && (arm == other.arm) && (intel == other.intel)
    end
  end
end
