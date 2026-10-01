# typed: strict
# frozen_string_literal: true

module Homebrew
  # Class handling platform-specific version information.
  class BumpVersionParser
    VERSION_PLATFORMS = T.let({
      arm:         [:macos, :arm],
      intel:       [:macos, :intel],
      linux_arm:   [:linux, :arm],
      linux_intel: [:linux, :intel],
    }.freeze, T::Hash[Symbol, [Symbol, Symbol]])
    VERSION_SYMBOLS = T.let([:general, *VERSION_PLATFORMS.keys].freeze, T::Array[Symbol])
    ParsedVersion = T.type_alias { T.nilable(T.any(Version, Cask::DSL::Version)) }

    sig { returns(ParsedVersion) }
    attr_reader :arm, :general, :intel, :linux_arm, :linux_intel

    sig {
      params(general:     T.nilable(T.any(Version, String)),
             arm:         T.nilable(T.any(Version, String)),
             intel:       T.nilable(T.any(Version, String)),
             linux_arm:   T.nilable(T.any(Version, String)),
             linux_intel: T.nilable(T.any(Version, String))).void
    }
    def initialize(general: nil, arm: nil, intel: nil, linux_arm: nil, linux_intel: nil)
      @general = T.let(parse_version(general), ParsedVersion) if general.present?
      @arm = T.let(parse_version(arm), ParsedVersion) if arm.present?
      @intel = T.let(parse_version(intel), ParsedVersion) if intel.present?
      @linux_arm = T.let(parse_version(linux_arm), ParsedVersion) if linux_arm.present?
      @linux_intel = T.let(parse_version(linux_intel), ParsedVersion) if linux_intel.present?

      return if @general.present?
      raise UsageError, "`--version` must not be empty." if [arm, intel, linux_arm, linux_intel].all?(&:blank?)
    end

    sig {
      params(version: T.any(Version, String))
        .returns(ParsedVersion)
    }
    def parse_version(version)
      if version.is_a?(Version)
        version
      elsif version.is_a?(String)
        parse_cask_version(version)
      else
        # simplecov:disable
        T.absurd(version)
        # simplecov:enable
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
      @general.blank? && @arm.blank? && @intel.blank? && @linux_arm.blank? && @linux_intel.blank?
    end

    sig { params(other: T.anything).returns(T::Boolean) }
    def ==(other)
      case other
      when BumpVersionParser
        (general == other.general) &&
          (arm == other.arm) && (intel == other.intel) &&
          (linux_arm == other.linux_arm) && (linux_intel == other.linux_intel)
      else
        false
      end
    end
  end
end
