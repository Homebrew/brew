# frozen_string_literal: true

module Gem
  ###
  # This module is used for safely loading YAML specs from a gem.  The
  # `safe_load` method defined on this module is specifically designed for
  # loading Gem specifications.  For loading other YAML safely, please see
  # Psych.safe_load

  module SafeYAML
    PERMITTED_CLASSES = %w[
      Symbol
      Time
      Date
      Gem::Dependency
      Gem::Platform
      Gem::Requirement
      Gem::Specification
      Gem::Version
      Gem::Version::Requirement
    ].freeze

    PERMITTED_SYMBOLS = %w[
      development
      runtime
    ].freeze

    @aliases_enabled = true
    def self.aliases_enabled=(value) # :nodoc:
      @aliases_enabled = !!value
    end

    def self.aliases_enabled? # :nodoc:
      @aliases_enabled
    end

    def self.safe_load(input)
      ::Psych.safe_load(input, permitted_classes: PERMITTED_CLASSES, permitted_symbols: PERMITTED_SYMBOLS, aliases: @aliases_enabled)
    end

    def self.load(input)
      ::Psych.safe_load(input, permitted_classes: [::Symbol])
    end
  end
end
